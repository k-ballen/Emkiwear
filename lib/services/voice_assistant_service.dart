import 'dart:async';

import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Callback invoked with the words recognized by the microphone and whether
/// they are the final transcription for the current utterance.
typedef OnSpeechResult = void Function(String recognizedWords, bool isFinal);

/// Base service for the AI voice assistant.
///
/// Combines three capabilities:
///  1. [speech_to_text]  -> capture the user's voice (Spanish by default).
///  2. [firebase_vertexai] -> Gemini (Vertex AI) generates the assistant reply.
///  3. [flutter_tts]     -> speak the reply out loud.
///
/// It is intentionally decoupled from the UI so any screen or feature can
/// reuse it (e.g. appointment reminders, medication queries, daily check-ins).
class VoiceAssistantService {
  VoiceAssistantService({this.geminiModel = 'gemini-1.5-flash'});

  /// Model name used when calling Gemini through Vertex AI.
  final String geminiModel;

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  /// Lazily created Gemini model (requires Firebase initialized first).
  GenerativeModel? _model;

  /// Locale reported by the speech recognizer (e.g. `es_ES`),
  /// filled during [initialize].
  String _localeName = '';

  /// True when speech recognition services were initialized successfully.
  bool get isAvailable => _speech.isAvailable;

  /// True while the microphone is capturing audio.
  bool get isListening => _speech.isListening;

  /// Locale reported by the speech recognizer (e.g. `es_ES`).
  String get localeName => _localeName;

  /// Requests the microphone permission and initializes the speech
  /// recognizer plus the TTS engine in Spanish.
  ///
  /// Returns `false` if the permission was denied or recognition is not
  /// supported on the device.
  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String errorMessage)? onError,
  }) async {
    // 1. Microphone permission (Android 12+ shows a one-time dialog).
    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      onError?.call('error_permission');
      return false;
    }

    // 2. Speech recognition.
    final bool ready = await _speech.initialize(
      onStatus: onStatus,
      onError: (error) => onError?.call(error.errorMsg),
    );
    if (!ready) return false;

    // 2b. Remember the device locale (fallback: Spanish).
    final LocaleName? locale = await _speech.systemLocale();
    _localeName = locale?.localeId ?? 'es_ES';

    // 3. Text-to-speech in Spanish, slow enough for Parkinson's patients.
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    return true;
  }

  /// Starts listening for a voice command.
  ///
  /// [duration] bounds the recognition window; [onResult] is called
  /// continuously as words are recognized and once more with [isFinal] true.
  Future<bool> listen({
    Duration duration = const Duration(seconds: 25),
    OnSpeechResult? onResult,
  }) async {
    if (!_speech.isAvailable) return false;
    if (_speech.isListening) await _speech.stop();

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'es_ES',
        listenFor: duration,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
      ),
      onResult: (result) =>
          onResult?.call(result.recognizedWords, result.finalResult),
    );
    return true;
  }

  /// Stops the current recognition session.
  Future<void> stopListening() async => _speech.stop();

  /// Speaks [text] out loud in Spanish.
  Future<void> speak(String text) async => _tts.speak(text);

  /// Stops any ongoing speech synthesis.
  Future<void> stopSpeaking() async => _tts.stop();

  /// Sends a prompt to Gemini (via Firebase Vertex AI) and returns the full
  /// text reply. Throws if Firebase is not initialized or the request fails.
  Future<String> askGemini(String prompt) async {
    final GenerativeModel model = _model ??=
        FirebaseVertexAI.instance.generativeModel(model: geminiModel);
    final GenerateContentResponse response =
        await model.generateContent([Content.text(prompt)]);
    return response.text ?? '';
  }

  /// Streams the answer of Gemini token by token so the UI can show it
  /// while it is being generated.
  Stream<String> askGeminiStream(String prompt) async* {
    final GenerativeModel model = _model ??=
        FirebaseVertexAI.instance.generativeModel(model: geminiModel);
    final Stream<GenerateContentResponse> stream =
        model.generateContentStream([Content.text(prompt)]);
    await for (final GenerateContentResponse chunk in stream) {
      if (chunk.text case final String text?) yield text;
    }
  }

  /// Full hands-free round-trip:
  /// recognizes the user's utterance, asks Gemini and speaks the reply.
  /// Returns the assistant's answer (or an empty string on failure).
  Future<String> askAndSpeak(
    String prompt, {
    void Function(String errorMessage)? onError,
  }) async {
    try {
      final String reply = await askGemini(prompt);
      if (reply.isNotEmpty) await speak(reply);
      return reply;
    } catch (error) {
      onError?.call(error.toString());
      return '';
    }
  }

  /// Releases all native resources (call when the widget is disposed).
  Future<void> dispose() async {
    await _speech.stop();
    await _tts.stop();
  }
}
