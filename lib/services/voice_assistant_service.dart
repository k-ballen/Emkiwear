 import 'dart:async';
import 'dart:io' show Socket, SocketException;

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'firebase_service.dart';
import 'offline_speech_service.dart';
import '../models/medication_reminder.dart';
import '../models/medication_task.dart';
import '../models/emergency_contact.dart';
import 'call_service.dart';

/// Callback invoked with the words recognized by the microphone and whether
/// they are the final transcription for the current utterance.
typedef OnSpeechResult = void Function(String recognizedWords, bool isFinal);

/// Possible navigation or app actions the assistant can execute.
enum AppVoiceAction {
  none,
  openHome,
  queryTremorToday,
  queryMedicationToday,
  openReminders,
  emergency, // se siente mal: mostrar botones para llamar a sus contactos
  callContact, // "llama a mi hija": abrir el marcador con ese número
  openTremor,
  openMedication,
  openHabits,
  openHabitsFood,
  openHabitsActivity,
  openCommunity,
  openCommunityCompanions,
  openCommunityGroups,
  openCommunityLessons,
  openCompanionProfile,
  openCommunityGroup,
  openCommunityLesson,
  togglePrivacyPrivate,
  togglePrivacyPublic,
  openProfile,
}

/// Known first names of demo companions for voice-driven lookup.
/// These are matched case-insensitively when the user mentions a companion
/// by name within the Comunidad Parkinson context.
const List<String> knownCompanionFirstNames = [
  'maría', 'maria', 'daniela', 'juan', 'carlos', 'ana', 'sofía', 'sofia',
  'luis', 'pedro', 'laura', 'carmen', 'josé', 'jose', 'elena', 'diego',
  'valentina', 'martina', 'verónica', 'veronica', 'patricia', 'robert',
  'fernando', 'isabel', 'catalina',
];

/// Known group names for voice-driven lookup (normalized for matching).
const List<String> knownGroupNames = [
  'club parkinson bogotá',
  'grupo de caminatas',
  'asociación de pacientes',
];

/// Known lesson titles for voice-driven lookup (normalized for matching).
const List<String> knownLessonTitles = [
  '¿qué es el parkinson?',
  'importancia de la actividad física',
  'alimentación y bienestar',
  'mitos y realidades',
];

/// Stages of the sequential step-by-step registration flow.
enum StepState {
  categoryIdentified, // Step 1: Category known ('food', 'medication', 'activity'), waiting for item name
  itemNameExtracted,  // Step 2: Category & itemName known, waiting for event time
}

/// Represents stateful multi-turn conversation context for step-by-step registration.
class PendingVoiceContext {
  final String category; // 'medication', 'food', 'activity'
  StepState step;
  String? itemName;
  String? mealType;
  int? durationMinutes;
  String? intensity;

  PendingVoiceContext({
    required this.category,
    this.step = StepState.categoryIdentified,
    this.itemName,
    this.mealType,
    this.durationMinutes,
    this.intensity,
  });

  String toPromptContext() {
    return 'Contexto conversacional previo activo: {pasoActual: ${step.name}, categoría: $category, nombreElemento: ${itemName ?? "pendiente"}, tipoComida: ${mealType ?? "pendiente"}, duracionMinutos: ${durationMinutes ?? "pendiente"}, intensidad: ${intensity ?? "pendiente"}}';
  }
}

/// Represents the assistant's processed response and optional action.
class VoiceAssistantResponse {
  final String textResponse;
  final AppVoiceAction action;
  final bool isRegistrationExecuted;
  final String? targetName;

  /// Para openReminders: recordatorio prellenado con lo que dijo el usuario.
  final MedicationReminder? reminderDraft;

  /// Para emergency: contactos a mostrar como botones de llamada.
  final List<EmergencyContact>? emergencyContacts;

  /// Para callContact: número a marcar.
  final String? phoneToCall;

  const VoiceAssistantResponse({
    required this.textResponse,
    this.action = AppVoiceAction.none,
    this.isRegistrationExecuted = false,
    this.targetName,
    this.reminderDraft,
    this.emergencyContacts,
    this.phoneToCall,
  });
}

/// Base service for the AI voice assistant.
///
/// Instancia ÚNICA compartida ([VoiceAssistantService.instance]): conserva el
/// modelo, la sesión de chat y el contexto pendiente aunque el modal se cierre.
class VoiceAssistantService {
  VoiceAssistantService._();

  static final VoiceAssistantService instance = VoiceAssistantService._();

  /// Devuelve siempre la misma instancia (compatibilidad con `VoiceAssistantService()`).
  factory VoiceAssistantService() => instance;

  /// Clave de Remote Config con el nombre del modelo y su valor por defecto.
  static const String remoteConfigModelKey = 'voice_model';
  static const String defaultModelName = 'gemini-3.8-flash';
  // 12 s: en las pruebas Gemini tardó hasta 7,7 s con buena señal.
  static const Duration geminiTimeout = Duration(seconds: 12);
  static const Duration chatIdleReset = Duration(minutes: 2);

  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final FirebaseService _firebaseService = FirebaseService();

  /// Holds multi-turn conversational context when information is missing or in progress.
  PendingVoiceContext? _pendingContext;

  /// Última vez que se actualizó el contexto pendiente (vence a los 2 min).
  DateTime? _pendingContextAt;
  static const Duration pendingContextTtl = Duration(minutes: 2);

  /// Lo pone en true [_registerLocally] cuando el respaldo local guardó algo.
  bool _localRegisteredFlag = false;

  GenerativeModel? _model;
  String? _modelName;
  Future<void>? _modelInit;
  ChatSession? _chat;
  DateTime? _chatLastUsed;

  bool _lastReplyFromGemini = false;
  String? _lastGeminiError;

  String _localeName = '';
  bool _speechReady = false;

  // Callbacks del modal actualmente abierto (el servicio sobrevive al modal).
  void Function(String status)? _onStatus;
  void Function(String errorMessage)? _onError;

  bool get isAvailable => _speech.isAvailable;
  bool get isListening => _speech.isListening;
  String get localeName => _localeName;

  /// true si la última respuesta la generó Gemini; false si fue el respaldo local.
  bool get lastReplyFromGemini => _lastReplyFromGemini;

  /// Último error de Gemini (null si la última llamada fue exitosa).
  String? get lastGeminiError => _lastGeminiError;

  /// Nombre de modelo en uso (Remote Config 'voice_model' o el valor por defecto).
  String get modelName => _modelName ?? defaultModelName;

  /// Precarga Remote Config y crea el modelo (se puede llamar al iniciar la app).
  Future<void> warmUp() async {
    await _ensureModel();
    unawaited(_profileMissingSummary());
  }

  Future<void> _ensureModel() => _modelInit ??= _createModel();

  /// Clave de Remote Config para el nivel de "razonamiento" del modelo:
  /// minimal (por defecto, respuestas más rápidas), low, medium, high u off.
  static const String remoteConfigThinkingKey = 'voice_thinking_level';
  // 'minimal' no es aceptado por gemini-3.8-flash en Vertex AI ("Thinking level
  // is unsupported: THINKING_LEVEL_MINIMAL"); 'low' sí y responde más rápido
  // que el valor por defecto. Si tampoco lo aceptara, se desactiva solo.
  static const String defaultThinkingLevel = 'low';
  String _thinkingLevel = defaultThinkingLevel;
  bool _thinkingDisabledByError = false;

  Future<void> _createModel() async {
    String name = defaultModelName;
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval:
            kDebugMode ? const Duration(minutes: 1) : const Duration(hours: 1),
      ));
      await rc.setDefaults(const {
        remoteConfigModelKey: defaultModelName,
        remoteConfigThinkingKey: defaultThinkingLevel,
      });
      try {
        await rc.fetchAndActivate();
      } catch (e) {
        debugPrint('[Emki] Remote Config fetch falló, uso valor activo/por defecto: $e');
      }
      final value = rc.getString(remoteConfigModelKey).trim();
      if (value.isNotEmpty) name = value;
      final level = rc.getString(remoteConfigThinkingKey).trim().toLowerCase();
      if (level.isNotEmpty) _thinkingLevel = level;
    } catch (e) {
      debugPrint('[Emki] Remote Config no disponible: $e');
    }
    _modelName = name;
    _buildModel();
  }

  /// Nivel de razonamiento: los modelos Gemini 3 "piensan" antes de responder
  /// y eso sumaba varios segundos (respuestas de 11-12 s). Para frases cortas
  /// de voz basta el mínimo.
  ThinkingConfig? get _thinkingConfig {
    if (_thinkingDisabledByError) return null;
    switch (_thinkingLevel) {
      case 'minimal':
        return ThinkingConfig.withThinkingLevel(ThinkingLevel.minimal);
      case 'low':
        return ThinkingConfig.withThinkingLevel(ThinkingLevel.low);
      case 'medium':
        return ThinkingConfig.withThinkingLevel(ThinkingLevel.medium);
      case 'high':
        return ThinkingConfig.withThinkingLevel(ThinkingLevel.high);
      default:
        return null; // 'off' u otro: el valor por defecto del modelo
    }
  }

  void _buildModel() {
    final name = _modelName ?? defaultModelName;
    // Backend Vertex AI ("Agent Platform Gemini API"). En firebase_ai 4.x,
    // FirebaseAI.vertexAI() está obsoleto y es un alias de agentPlatform()
    // (mismo backend). App Check se adjunta solo: app.getService<FirebaseAppCheck>().
    final thinking = _thinkingConfig;
    _model = FirebaseAI.agentPlatform(location: 'global').generativeModel(
      model: name,
      systemInstruction: Content.system(_systemInstruction),
      generationConfig: GenerationConfig(temperature: 0.2, thinkingConfig: thinking),
    );
    _chat = null;
    debugPrint('[Emki] Modelo Vertex AI listo: $name (location: global, '
        'razonamiento: ${thinking == null ? 'por defecto' : _thinkingLevel})');
  }

  /// Reinicia la memoria de la conversación con Gemini.
  void resetChat() {
    _chat = null;
    _chatLastUsed = null;
  }

  /// Sin conexión, el Future de Firestore (.add/.set/.update) no termina hasta
  /// que el servidor confirma, y el asistente se quedaba colgado. El dato ya
  /// queda en la caché local de Firestore y se sube solo al volver internet,
  /// así que solo esperamos 3 s la confirmación.
  Future<void> _saveOfflineSafe(Future<void> write) async {
    try {
      await write.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('[Emki] Firestore sin confirmación (¿sin internet?): queda en cola local.');
    }
  }

  /// Comprobación rápida de red para no esperar los 8 s del timeout de Gemini.
  /// Abre una conexión real: solo resolver el DNS no sirve, porque Android lo
  /// tiene en caché y responde aunque el teléfono esté en modo avión.
  Future<bool> _hasInternet() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        'firebasevertexai.googleapis.com',
        443,
        timeout: const Duration(seconds: 2),
      ).timeout(const Duration(milliseconds: 2500));
      return true;
    } catch (e) {
      debugPrint('[Emki] Sin conexión a internet ($e)');
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static const Map<String, int> _numberWords = {
    'un': 1, 'una': 1, 'uno': 1, 'dos': 2, 'tres': 3, 'cuatro': 4, 'cinco': 5,
    'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10, 'once': 11,
    'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15, 'dieciseis': 16,
    'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19, 'veinte': 20,
    'veinticinco': 25, 'treinta': 30, 'cuarenta': 40, 'cuarenta y cinco': 45,
    'cincuenta': 50, 'sesenta': 60, 'noventa': 90,
  };

  static int? _parseNumber(String token) =>
      int.tryParse(token) ?? _numberWords[token];

  static const String _periodPattern =
      'am|pm|a m|p m|de la mañana|de la manana|de la tarde|de la noche|de la madrugada';
  static const Set<String> _durationUnits = {'min', 'minuto', 'minutos', 'hora', 'horas'};

  /// ¿La frase dice CUÁNDO ocurrió (hora concreta o tiempo relativo)?
  @visibleForTesting
  static bool hasSpecificTimeReference(String prompt) =>
      extractEventDateTime(prompt, DateTime.now()) != null;

  /// Fecha y hora del evento según la frase, o null si no hay una hora concreta
  /// (p. ej. "en la mañana" sola -> null, para preguntar).
  ///  - ahora / ahorita / recién / acabo de
  ///  - hace N minutos/horas, hace media hora, hace un rato (20 min)
  ///  - a las H [MM | y media | y cuarto | menos cuarto] [am/pm/de la mañana...]
  ///  - H [MM] am/pm/de la mañana-tarde-noche; mediodía; medianoche
  ///  - números en dígitos o en palabras.
  /// Un número solo es hora tras "a las/a la" o antes de am/pm/"de la ...";
  /// nunca si va antes de min/minutos/hora(s) ("30 minutos" es duración).
  /// Sin periodo y H de 1 a 11: se elige la más reciente no futura entre H y H+12.
  @visibleForTesting
  static DateTime? extractEventDateTime(String prompt, DateTime now) {
    final n = normalizeText(prompt);
    if (n.isEmpty) return null;

    // 1. Ahora
    if (hasAnyWord(n, const [
      'ahora', 'ahorita', 'ahora mismo', 'recien', 'acabo de', 'acaba de',
      'en este momento', 'hace un momento', 'hace un momentico',
    ])) {
      return now;
    }

    // 2. Relativo
    if (hasWord(n, 'hace media hora')) return now.subtract(const Duration(minutes: 30));
    if (hasAnyWord(n, const ['hace un rato', 'hace rato', 'hace un ratico'])) {
      return now.subtract(const Duration(minutes: 20));
    }
    final rel = RegExp(r'(?:^| )hace (\d{1,3}|[a-z]+(?: y [a-z]+)?) (minuto|minutos|hora|horas)( y media)?(?: |$)')
        .firstMatch(n);
    if (rel != null) {
      final amount = _parseNumber(rel.group(1)!);
      if (amount != null) {
        final isHours = rel.group(2)!.startsWith('hora');
        var minutes = isHours ? amount * 60 : amount;
        if (rel.group(3) != null) minutes += 30;
        return now.subtract(Duration(minutes: minutes));
      }
    }

    // 3. Mediodía / medianoche
    final today = DateTime(now.year, now.month, now.day);
    if (hasAnyWord(n, const ['mediodia', 'medio dia'])) return today.add(const Duration(hours: 12));
    if (hasAnyWord(n, const ['medianoche', 'media noche'])) return today;

    // 4. Hora de reloj
    final numberToken = r'(\d{1,2}|[a-z]+)';
    final tail = '(?: (\\d{2}))?(?: (y media|y cuarto|menos cuarto))?(?: ($_periodPattern))?';
    final patterns = <RegExp>[
      RegExp('(?:^| )a las? $numberToken$tail(?= |\$)'),                // "a las 8 30 de la noche"
      RegExp('(?:^| )(\\d{1,2})(?: (\\d{2}))?()(?: ?($_periodPattern))(?= |\$)'), // "8 pm", "8 30 de la mañana"
      RegExp('^(?:las? )?$numberToken$tail\$'),                         // respuesta corta: "8", "ocho y media"
    ];

    for (final re in patterns) {
      for (final m in re.allMatches(n)) {
        final hour0 = _parseNumber(m.group(1)!);
        if (hour0 == null) continue;
        // ¿Lo que sigue es una unidad de duración ("a las 2 horas")? Entonces no es hora.
        final after = n.substring(m.end).trim();
        final nextWord = after.isEmpty ? '' : after.split(' ').first;
        if (_durationUnits.contains(nextWord)) continue;

        var hour = hour0;
        var minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
        final frac = m.group(3);
        if (frac == 'y media') minute = 30;
        if (frac == 'y cuarto') minute = 15;
        if (frac == 'menos cuarto') {
          minute = 45;
          hour = hour - 1;
          if (hour < 0) hour = 23;
        }
        if (hour > 23 || minute > 59) continue;

        final period = m.group(4);
        if (period != null) {
          final pm = period == 'pm' || period == 'p m' || period.contains('tarde') || period.contains('noche');
          if (pm && hour < 12) hour += 12;
          if (period.contains('noche') && hour0 == 12) hour = 0;
          if (!pm && hour == 12) hour = 0;
          return _mostRecentNotFuture([today.add(Duration(hours: hour, minutes: minute))], now);
        }

        if (hour >= 1 && hour <= 11) {
          return _mostRecentNotFuture([
            today.add(Duration(hours: hour, minutes: minute)),
            today.add(Duration(hours: hour + 12, minutes: minute)),
          ], now);
        }
        return _mostRecentNotFuture([today.add(Duration(hours: hour, minutes: minute))], now);
      }
    }

    // "en la mañana/tarde/noche" sin hora -> null (preguntar)
    return null;
  }

  /// De los candidatos de hoy (y los mismos de ayer), el más reciente que no
  /// esté en el futuro (tolerancia de 5 min).
  static DateTime _mostRecentNotFuture(List<DateTime> todayCandidates, DateTime now) {
    final limit = now.add(const Duration(minutes: 5));
    final all = [
      ...todayCandidates,
      ...todayCandidates.map((d) => d.subtract(const Duration(days: 1))),
    ].where((d) => !d.isAfter(limit)).toList()
      ..sort();
    return all.isNotEmpty ? all.last : todayCandidates.first;
  }

  /// Hora HH:MM válida en 24 h (sin recortar: "30:00" es inválida, no 23:00).
  static bool _isValidHhMm(String s) =>
      RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(s.trim());

  Future<bool> initialize({
    void Function(String status)? onStatus,
    void Function(String errorMessage)? onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;

    final PermissionStatus status = await Permission.microphone.request();
    if (!status.isGranted) {
      onError?.call('error_permission');
      return false;
    }

    if (_speechReady && _speech.isAvailable) return true;

    final bool ready = await _speech.initialize(
      onStatus: (s) {
        debugPrint('[Emki] STT estado: $s');
        if (s == 'done' || s == 'notListening') _onListeningEnded();
        _onStatus?.call(s);
      },
      onError: (error) {
        debugPrint('[Emki] STT error: ${error.errorMsg} (permanente: ${error.permanent})');
        // En la ventana de continuación, "no te escuché" solo significa que la
        // persona ya terminó: se envía lo acumulado.
        if (_utteranceActive && _accumulated.isNotEmpty) {
          _finishUtterance();
          return;
        }
        if (_retrySttWithNextLocale(error.errorMsg)) return;
        _utteranceActive = false;
        _onError?.call(error.errorMsg);
      },
    );
    if (!ready) return false;
    _speechReady = true;

    final LocaleName? locale = await _speech.systemLocale();
    _localeName = locale?.localeId ?? '';

    await _setBestSpanishVoice();
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    return true;
  }

  // --- Reconocimiento sin internet ---
  // Con red, Google reconoce cualquier variante de español (es_CO incluido).
  // Sin red solo funciona un idioma con paquete offline descargado: es_CO
  // suele no tenerlo (error_language_not_supported / error_network), así que
  // se prueba en el dispositivo es_US y luego es_ES, y se recuerda el que sirva.
  static const Set<String> _sttRetryableErrors = {
    'error_language_not_supported',
    'error_language_unavailable',
    'error_network',
    'error_network_timeout',
    // error_server_disconnected NO: es una sesión bloqueada del servicio de
    // Google y cambiar de idioma no la arregla.
  };
  final List<String> _sttLocaleQueue = [];
  String? _workingOfflineLocale;
  String? _currentSttLocale;
  bool _currentSttOnDevice = false;
  Duration _currentListenDuration = const Duration(seconds: 25);
  OnSpeechResult? _currentOnResult;

  Future<bool> listen({
    Duration duration = const Duration(seconds: 25),
    OnSpeechResult? onResult,
  }) async {
    if (!_speech.isAvailable) return false;
    _ensureLifecycleObserver();
    // Cierra cualquier sesión anterior antes de abrir otra.
    await _cancelSpeechSession();

    _currentListenDuration = duration;
    _currentOnResult = onResult;
    _sttLocaleQueue.clear();
    _continuationTimer?.cancel();
    _accumulated = '';
    _utteranceActive = true;
    _utteranceStart = DateTime.now();

    final online = await _hasInternet();
    if (online) {
      _sttLocaleQueue.add(sttLocaleId);
      _currentSttOnDevice = false;
    } else {
      final offline = await OfflineSpeechService.cachedStatus();
      final candidates = <String>[
        ?_workingOfflineLocale,
        ...offline.installedSpanishLocaleIds,
        'es_US',
        'es_ES',
        sttLocaleId,
      ];
      for (final c in candidates) {
        if (!_sttLocaleQueue.contains(c)) _sttLocaleQueue.add(c);
      }
      _currentSttOnDevice = true;
    }
    await _startListeningWith(_sttLocaleQueue.removeAt(0));
    return true;
  }

  // El reconocedor sin conexión es continuo: tras el resultado final con la
  // frase puede mandar más resultados finales VACÍOS. Se guarda el último texto
  // oído y, si la escucha termina sin un final con texto, se entrega ese.
  String _lastHeardText = '';
  bool _finalDelivered = true;

  // --- Escucha continua ---
  // El reconocedor de Android corta en cuanto detecta una pausa corta (a
  // veces antes de que el paciente termine). Cuando cierra un tramo, se
  // sigue escuchando [continuationWindow]: si la persona continúa, el texto
  // nuevo se UNE al anterior; si se queda en silencio, se envía todo junto.
  static const Duration continuationWindow = Duration(seconds: 3);
  static const Duration maxUtterance = Duration(seconds: 40);
  String _accumulated = '';
  bool _utteranceActive = false;
  DateTime? _utteranceStart;
  Timer? _continuationTimer;

  String _combined(String segment) =>
      [_accumulated, segment.trim()].where((s) => s.isNotEmpty).join(' ');

  /// ¿[current] es un tramo NUEVO y no una corrección/continuación de [previous]?
  /// Una corrección conserva la primera palabra o no se acorta mucho.
  @visibleForTesting
  static bool isNewSegment(String previous, String current) {
    final p = normalizeText(previous);
    final c = normalizeText(current);
    if (p.isEmpty || c.isEmpty) return false;
    if (c.startsWith(p) || p.startsWith(c)) return false; // continuación o revisión
    final sameFirstWord = p.split(' ').first == c.split(' ').first;
    return !sameFirstWord && c.length < p.length * 0.8;
  }

  /// Un tramo terminó: se acumula y se sigue escuchando un momento más.
  void _deliverFinal(String text) {
    if (_finalDelivered || text.trim().isEmpty) return;
    _finalDelivered = true;
    _accumulated = _combined(text);
    debugPrint('[Emki] STT tramo: "$text" -> acumulado: "$_accumulated"');
    // Se cierra la sesión (el modo sin conexión es CONTINUO y si no se cancela
    // bloquea las escuchas siguientes con error_server_disconnected).
    _cancelSpeechSession();
    _currentOnResult?.call(_accumulated, false);

    final elapsed = DateTime.now().difference(_utteranceStart ?? DateTime.now());
    if (!_utteranceActive || elapsed > maxUtterance) {
      _finishUtterance();
      return;
    }
    _continuationTimer?.cancel();
    _continuationTimer = Timer(continuationWindow, () {
      debugPrint('[Emki] Silencio tras la frase: la envío.');
      _finishUtterance();
    });
    final locale = _currentSttLocale;
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_utteranceActive && locale != null) _startListeningWith(locale);
    });
  }

  /// Termina la frase completa y la entrega al modal (también lo usa el botón
  /// "TERMINÉ DE HABLAR").
  void _finishUtterance() {
    if (!_utteranceActive) return;
    _utteranceActive = false;
    _continuationTimer?.cancel();
    // Si se estaba hablando un tramo nuevo, también cuenta lo ya oído.
    final text = _finalDelivered ? _accumulated : _combined(_lastHeardText);
    _finalDelivered = true;
    _cancelSpeechSession();
    if (text.trim().isEmpty) return;
    debugPrint('[Emki] STT frase final: "$text"');
    _currentOnResult?.call(text, true);
  }

  /// Botón "TERMINÉ DE HABLAR": envía ya lo que se ha dicho.
  void finishListening() => _finishUtterance();

  Future<void> _cancelSpeechSession() async {
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('[Emki] No se pudo cancelar la sesión de voz: $e');
    }
  }

  bool _lifecycleObserverAdded = false;

  /// Si la app pasa a segundo plano o se cierra mientras escucha, se cancela
  /// la sesión (si no, el servicio de Google la deja abierta).
  void _ensureLifecycleObserver() {
    if (_lifecycleObserverAdded) return;
    _lifecycleObserverAdded = true;
    WidgetsBinding.instance.addObserver(_SpeechLifecycleObserver(() {
      if (_speech.isListening) {
        debugPrint('[Emki] App en segundo plano: cancelo la escucha.');
        _finalDelivered = true;
        _utteranceActive = false;
        _continuationTimer?.cancel();
        _cancelSpeechSession();
      }
    }));
  }

  /// Llamado cuando la escucha termina (estado done/notListening).
  void _onListeningEnded() {
    if (!_finalDelivered && _lastHeardText.isNotEmpty) {
      debugPrint('[Emki] La escucha terminó sin final con texto; uso lo último que oí.');
      _deliverFinal(_lastHeardText);
    }
  }

  Future<void> _startListeningWith(String localeId) async {
    _currentSttLocale = localeId;
    _lastHeardText = '';
    _finalDelivered = false;
    debugPrint('[Emki] Escuchando con idioma $localeId '
        '(${_currentSttOnDevice ? "sin internet, en el dispositivo" : "en línea"}; sistema: "$_localeName")');
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: _currentListenDuration,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onDevice: _currentSttOnDevice,
      ),
      onResult: (result) {
        if (_finalDelivered) return;
        final words = result.recognizedWords;
        if (words.trim().isNotEmpty) {
          // El reconocedor en línea a veces, tras una pausa, sigue en la misma
          // sesión pero REINICIA los parciales con la frase nueva (se perdía
          // "Hoy desayuné..." y solo quedaba "a las 8 de la mañana"). Si el
          // parcial nuevo no continúa el anterior, el anterior se guarda.
          if (_lastHeardText.isNotEmpty && isNewSegment(_lastHeardText, words)) {
            _accumulated = _combined(_lastHeardText);
            debugPrint('[Emki] STT tramo (mismo micrófono): "$_lastHeardText" -> acumulado: "$_accumulated"');
          }
          _lastHeardText = words;
          if (_currentSttOnDevice) _workingOfflineLocale = localeId;
          // Siguió hablando dentro de la ventana: no se envía todavía.
          _continuationTimer?.cancel();
        }
        if (result.finalResult) {
          // Un final vacío no borra lo que ya se oyó.
          _deliverFinal(words.trim().isNotEmpty ? words : _lastHeardText);
        } else if (words.trim().isNotEmpty) {
          _currentOnResult?.call(_combined(words), false);
        }
      },
    );
  }

  /// Si el idioma actual no sirve sin internet, prueba el siguiente.
  /// Devuelve true si se reintentó (el error no se muestra en el modal).
  bool _retrySttWithNextLocale(String errorMsg) {
    if (!_sttRetryableErrors.contains(errorMsg) || _sttLocaleQueue.isEmpty) {
      return false;
    }
    if (_workingOfflineLocale == _currentSttLocale) _workingOfflineLocale = null;
    final next = _sttLocaleQueue.removeAt(0);
    debugPrint('[Emki] $errorMsg con $_currentSttLocale; reintento con $next');
    Future.delayed(const Duration(milliseconds: 300), () => _startListeningWith(next));
    return true;
  }

  /// Idioma de reconocimiento: el del sistema si es español; si no, español de Colombia.
  String get sttLocaleId =>
      _localeName.toLowerCase().startsWith('es') ? _localeName : 'es_CO';

  /// Voz TTS en orden es-CO, es-US, es-ES. Primero busca una voz INSTALADA en
  /// el teléfono (funciona sin internet); si ninguna lo está, usa la primera
  /// disponible (puede requerir red).
  Future<void> _setBestSpanishVoice() async {
    const langs = ['es-CO', 'es-US', 'es-ES'];
    for (final lang in langs) {
      try {
        if (await _tts.isLanguageInstalled(lang) == true) {
          await _tts.setLanguage(lang);
          debugPrint('[Emki] Voz TTS: $lang (instalada, funciona sin internet)');
          return;
        }
      } catch (_) {}
    }
    for (final lang in langs) {
      try {
        final available = await _tts.isLanguageAvailable(lang);
        if (available == true || available == 1) {
          await _tts.setLanguage(lang);
          debugPrint('[Emki] Voz TTS: $lang (NO instalada: puede no sonar sin internet)');
          return;
        }
      } catch (_) {}
    }
    await _tts.setLanguage('es-ES');
    debugPrint('[Emki] Voz TTS: es-ES (por defecto)');
  }

  /// Termina la escucha. Usa cancel(): el modo sin conexión es continuo e
  /// ignora stop(), y la sesión quedaba abierta bloqueando el micrófono.
  Future<void> stopListening() async {
    _finalDelivered = true; // al detener a mano no se entrega nada más
    _utteranceActive = false;
    _continuationTimer?.cancel();
    await _cancelSpeechSession();
  }
  Future<void> speak(String text) async => _tts.speak(text);
  Future<void> stopSpeaking() async => _tts.stop();

  /// Envía un turno a Gemini dentro de la sesión de chat (recuerda turnos previos).
  /// Lanza excepción si falla, tarda más de [geminiTimeout] o responde vacío.
  Future<String> askGemini(String turnMessage) async {
    if (!await _hasInternet()) {
      throw const SocketException('Sin conexión a internet: uso el respaldo local');
    }
    await _ensureModel();
    final model = _model;
    if (model == null) throw StateError('Modelo Gemini no inicializado');

    final now = DateTime.now();
    if (_chat == null ||
        (_chatLastUsed != null && now.difference(_chatLastUsed!) > chatIdleReset)) {
      _chat = model.startChat();
    }
    _chatLastUsed = now;

    final started = DateTime.now();
    GenerateContentResponse response;
    try {
      response = await _chat!.sendMessage(Content.text(turnMessage)).timeout(geminiTimeout);
    } catch (e) {
      // Si el modelo no acepta el nivel de razonamiento, se quita y se reintenta una vez.
      if (!_thinkingDisabledByError && _thinkingConfig != null &&
          e.toString().toLowerCase().contains('thinking')) {
        debugPrint('[Emki] El modelo no acepta thinkingLevel=$_thinkingLevel ($e); lo desactivo.');
        _thinkingDisabledByError = true;
        _buildModel();
        _chat = _model!.startChat();
        response = await _chat!.sendMessage(Content.text(turnMessage)).timeout(geminiTimeout);
      } else {
        rethrow;
      }
    }
    debugPrint('[Emki] Gemini respondió en ${DateTime.now().difference(started).inMilliseconds} ms');
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) throw StateError('Gemini devolvió una respuesta vacía');
    return text;
  }

  /// Processes user's voice prompt using Gemini AI + stateful multi-turn entity extraction.
  Future<VoiceAssistantResponse> processPrompt(String userPrompt) async {
    final cleanPrompt = userPrompt.trim();
    if (cleanPrompt.isEmpty) {
      const response = VoiceAssistantResponse(
        textResponse: 'No alcancé a escucharte bien. ¿Podrías repetir?',
        action: AppVoiceAction.none,
      );
      await speak(response.textResponse);
      return response;
    }

    // El contexto pendiente vence a los 2 minutos sin uso.
    if (_pendingContext != null &&
        _pendingContextAt != null &&
        DateTime.now().difference(_pendingContextAt!) > pendingContextTtl) {
      debugPrint('[Emki] Contexto pendiente vencido (> 2 min): se descarta.');
      _pendingContext = null;
      resetChat();
    }

    debugPrint('[Emki] Usuario: "$cleanPrompt" (contexto: ${_pendingContext?.toPromptContext() ?? "ninguno"})');

    // Cancelación (única regla, la misma que usa el respaldo local).
    if (isCancel(cleanPrompt)) {
      final hadContext = _pendingContext != null;
      _pendingContext = null;
      resetChat();
      _lastReplyFromGemini = false;
      final response = VoiceAssistantResponse(
        textResponse: hadContext
            ? 'Listo, cancelé el registro. No guardé nada.'
            : 'Listo, no hice ningún registro.',
        action: AppVoiceAction.none,
      );
      debugPrint('[Emki] Cancelado por el usuario (había contexto: $hadContext).');
      await speak(response.textResponse);
      return response;
    }

    // Un comando de navegación ("vuelve al inicio", "abre comunidad") en medio
    // de un registro guiado NO es el nombre ni la hora: se abandona el registro
    // y se procesa el comando.
    if (_pendingContext != null && isNavigationCommand(cleanPrompt)) {
      debugPrint('[Emki] Comando de navegación durante un registro: se descarta el contexto.');
      _pendingContext = null;
      resetChat();
    }

    // Emergencia ("me siento mal", "me caí") o llamada ("llama a mi hija"):
    // se resuelve aquí, sin Gemini: es lo más importante que sea rápido y fiable.
    final emergencyResponse = await _handleEmergencyOrCall(cleanPrompt);
    if (emergencyResponse != null) {
      _pendingContext = null;
      resetChat();
      debugPrint('[Emergencia] "${emergencyResponse.textResponse}" acción=${emergencyResponse.action.name} '
          'contactos=${emergencyResponse.emergencyContacts?.length ?? 0}');
      await speak(emergencyResponse.textResponse);
      return emergencyResponse;
    }

    // Recordatorio (aviso FUTURO): se resuelve aquí, sin Gemini, para que nunca
    // se guarde como una toma ya hecha. Se abre el editor prellenado.
    if (isReminderRequest(cleanPrompt)) {
      _pendingContext = null;
      resetChat();
      final draft = extractReminderDraft(cleanPrompt, DateTime.now());
      final response = VoiceAssistantResponse(
        textResponse: reminderReply(draft),
        action: AppVoiceAction.openReminders,
        targetName: draft.name.isEmpty ? null : draft.name,
        reminderDraft: draft,
      );
      debugPrint('[Emki] Recordatorio (local): "${response.textResponse}" '
          'horas=${draft.times.length} días=${draft.weekdaysLabel} fin=${draft.endDate}');
      await speak(response.textResponse);
      return response;
    }

    // Para reiniciar la sesión de chat cuando el contexto pendiente pasa a null.
    final bool hadPendingContext = _pendingContext != null;

    // Si responde Gemini, SOLO valen sus etiquetas. La detección local por
    // palabras se usa únicamente en el respaldo (catch).
    AppVoiceAction detectedAction = AppVoiceAction.none;
    String? targetName;
    String rawReply = '';
    bool localRegistered = false;

    try {
      final nowTime = TimeOfDay.now();
      final formattedNow =
          '${nowTime.hour.toString().padLeft(2, '0')}:${nowTime.minute.toString().padLeft(2, '0')}';

      // Campos vacíos del perfil (en caché; si aún no está, se carga para el próximo turno).
      if (_profileMissingCache == null) unawaited(_profileMissingSummary());

      // Mensaje del turno: solo datos dinámicos. Las reglas van en systemInstruction.
      final turnMessage = '''
HORA DE REFERENCIA DEL DISPOSITIVO: $formattedNow
ESTADO CONVERSACIONAL PREVIO ACTIVO: ${_pendingContext != null ? _pendingContext!.toPromptContext() : "Sin contexto previo activo."}
CAMPOS VACÍOS DEL PERFIL: ${_profileMissingCache ?? 'desconocido'}
Mensaje del usuario: "$cleanPrompt"
''';

      rawReply = await askGemini(turnMessage);
      _lastReplyFromGemini = true;
      _lastGeminiError = null;
    } catch (e, st) {
      _lastReplyFromGemini = false;
      _lastGeminiError = e.toString();
      debugPrint('[Emki] Gemini error: $e\n$st');
      detectedAction = _detectActionFromPrompt(cleanPrompt);
      targetName = _extractCommunityTargetName(cleanPrompt, detectedAction);
      // Las consultas del día se responden más abajo con datos reales; no
      // pasan por el respaldo de registro.
      final fallback = _isDayQuery(detectedAction)
          ? null
          : await _tryLocalRegistrationFallback(cleanPrompt);
      if (detectedAction == AppVoiceAction.openReminders) {
        targetName = extractReminderMedication(cleanPrompt);
        rawReply = _getFallbackResponse(cleanPrompt, detectedAction, targetName);
      } else if (_isDayQuery(detectedAction)) {
        rawReply = '';
      } else if (fallback != null) {
        rawReply = fallback.reply;
        localRegistered = fallback.registered;
      } else {
        rawReply = _getFallbackResponse(cleanPrompt, detectedAction, targetName);
      }
    }

    // Execute Registration Tag if present
    final regResult = await _executeDataRegistration(rawReply, cleanPrompt);
    if (regResult.executed) {
      _pendingContext = null; // Registration complete! Clear pending state.
      rawReply = regResult.cleanReply;
    } else if (regResult.rejected) {
      // Gemini quiso registrar sin hora concreta: se pregunta la hora y se
      // reinicia el chat (Gemini cree que ya registró). El contexto pendiente
      // con nombre/duración viaja en el siguiente mensaje.
      rawReply = regResult.cleanReply;
      resetChat();
    } else if (_lastReplyFromGemini) {
      // SOLO con respuesta de Gemini. Tras un registro del respaldo local esto
      // recreaba el contexto, y la frase siguiente se guardaba como un
      // medicamento falso en Firestore.
      _updatePendingContextFromQuery(cleanPrompt, rawReply);
    }
    _pendingContextAt = _pendingContext != null ? DateTime.now() : null;

    // El registro guiado terminó (contexto pasó a null): nueva conversación.
    if (hadPendingContext && _pendingContext == null) {
      resetChat();
    }

    // Parse navigation action tag from AI reply
    final reminderTag =
        RegExp(r'\[ACTION:OPEN_REMINDERS(?:\|name=([^\]]*))?\]').firstMatch(rawReply);
    if (rawReply.contains('[ACTION:EMERGENCY]')) {
      detectedAction = AppVoiceAction.emergency;
    } else if (reminderTag != null) {
      detectedAction = AppVoiceAction.openReminders;
      final tagName = reminderTag.group(1)?.trim();
      targetName = (tagName != null && tagName.isNotEmpty)
          ? _cleanEntityName(tagName)
          : extractReminderMedication(cleanPrompt);
    } else if (rawReply.contains('[ACTION:QUERY_TREMOR_TODAY]')) {
      detectedAction = AppVoiceAction.queryTremorToday;
    } else if (rawReply.contains('[ACTION:QUERY_MEDS_TODAY]')) {
      detectedAction = AppVoiceAction.queryMedicationToday;
    } else if (rawReply.contains('[ACTION:OPEN_HOME]')) {
      detectedAction = AppVoiceAction.openHome;
    } else if (rawReply.contains('[ACTION:OPEN_MEDICATION]')) {
      detectedAction = AppVoiceAction.openMedication;
    } else if (rawReply.contains('[ACTION:OPEN_TREMOR]')) {
      detectedAction = AppVoiceAction.openTremor;
    } else if (rawReply.contains('[ACTION:OPEN_HABITS_ACTIVITY]')) {
      detectedAction = AppVoiceAction.openHabitsActivity;
    } else if (rawReply.contains('[ACTION:OPEN_HABITS_FOOD]') || rawReply.contains('[ACTION:OPEN_HABITS]')) {
      detectedAction = AppVoiceAction.openHabitsFood;
    } else if (rawReply.contains('[ACTION:OPEN_COMMUNITY_COMPANIONS]')) {
      detectedAction = AppVoiceAction.openCommunityCompanions;
    } else if (rawReply.contains('[ACTION:OPEN_COMMUNITY_GROUPS]')) {
      detectedAction = AppVoiceAction.openCommunityGroups;
    } else if (rawReply.contains('[ACTION:OPEN_COMMUNITY_LESSONS]')) {
      detectedAction = AppVoiceAction.openCommunityLessons;
    } else if (rawReply.contains('[ACTION:OPEN_COMMUNITY]')) {
      detectedAction = AppVoiceAction.openCommunity;
    } else if (rawReply.contains('[ACTION:OPEN_PROFILE]')) {
      detectedAction = AppVoiceAction.openProfile;
    } else if (rawReply.contains('[ACTION:PRIVACY_PRIVATE]')) {
      detectedAction = AppVoiceAction.togglePrivacyPrivate;
    } else if (rawReply.contains('[ACTION:PRIVACY_PUBLIC]')) {
      detectedAction = AppVoiceAction.togglePrivacyPublic;
    }

    // Parse parameterized companion / group / lesson tags
    if (detectedAction == AppVoiceAction.none ||
        detectedAction == AppVoiceAction.openCommunity) {
      final companionMatch =
          RegExp(r'\[ACTION:OPEN_COMPANION\|name=([^\]]+)\]').firstMatch(rawReply);
      if (companionMatch != null) {
        detectedAction = AppVoiceAction.openCompanionProfile;
        targetName = _cleanEntityName(companionMatch.group(1)!);
      }
    }
    if (detectedAction == AppVoiceAction.none ||
        detectedAction == AppVoiceAction.openCommunity) {
      final groupMatch =
          RegExp(r'\[ACTION:OPEN_GROUP\|name=([^\]]+)\]').firstMatch(rawReply);
      if (groupMatch != null) {
        detectedAction = AppVoiceAction.openCommunityGroup;
        targetName = _cleanEntityName(groupMatch.group(1)!);
      }
    }
    if (detectedAction == AppVoiceAction.none ||
        detectedAction == AppVoiceAction.openCommunity) {
      final lessonMatch =
          RegExp(r'\[ACTION:OPEN_LESSON\|name=([^\]]+)\]').firstMatch(rawReply);
      if (lessonMatch != null) {
        detectedAction = AppVoiceAction.openCommunityLesson;
        targetName = _cleanEntityName(lessonMatch.group(1)!);
      }
    }

    // If only a companion / group / lesson tag was emitted (without a
    // specific section tag), the action above was already set.
    final companionOnly =
        RegExp(r'\[ACTION:OPEN_COMPANION\|name=([^\]]+)\]').firstMatch(rawReply);
    if (companionOnly != null &&
        detectedAction != AppVoiceAction.openCompanionProfile) {
      detectedAction = AppVoiceAction.openCompanionProfile;
      targetName = _cleanEntityName(companionOnly.group(1)!);
    }
    final groupOnly =
        RegExp(r'\[ACTION:OPEN_GROUP\|name=([^\]]+)\]').firstMatch(rawReply);
    if (groupOnly != null &&
        detectedAction != AppVoiceAction.openCommunityGroup) {
      detectedAction = AppVoiceAction.openCommunityGroup;
      targetName = _cleanEntityName(groupOnly.group(1)!);
    }
    final lessonOnly =
        RegExp(r'\[ACTION:OPEN_LESSON\|name=([^\]]+)\]').firstMatch(rawReply);
    if (lessonOnly != null &&
        detectedAction != AppVoiceAction.openCommunityLesson) {
      detectedAction = AppVoiceAction.openCommunityLesson;
      targetName = _cleanEntityName(lessonOnly.group(1)!);
    }

    // Execute privacy toggle directly if the command was understood
    if (detectedAction == AppVoiceAction.togglePrivacyPrivate) {
      await _saveOfflineSafe(_firebaseService.updatePrivacy(false));
    } else if (detectedAction == AppVoiceAction.togglePrivacyPublic) {
      await _saveOfflineSafe(_firebaseService.updatePrivacy(true));
    }

    // En el respaldo local, si no hubo nombre en una etiqueta, se extrae del
    // texto del usuario. Con Gemini, solo vale el nombre de su etiqueta.
    if (!_lastReplyFromGemini) {
      targetName ??= _extractCommunityTargetName(cleanPrompt, detectedAction);
    }

    // Perfil: [UPDATE_PROFILE|...] de Gemini o, sin Gemini, el extractor local.
    final profileTag = RegExp(r'\[UPDATE_PROFILE\|([^\]]+)\]').firstMatch(rawReply);
    final profileUpdates = profileTag != null
        ? parseProfileTag(profileTag.group(1)!)
        : (!_lastReplyFromGemini ? extractProfileUpdates(cleanPrompt) : const <String, Object>{});
    if (profileUpdates.isNotEmpty) {
      await _saveOfflineSafe(_firebaseService.updateProfileFields(profileUpdates));
      _profileMissingCache = null; // se recalcula con los datos nuevos
      _pendingContext = null;
      debugPrint('[Emki] Perfil actualizado: $profileUpdates');
      // Si Gemini preguntó por el siguiente dato, se conserva su pregunta.
      final geminiText = rawReply.replaceAll(RegExp(r'\[[^\]]*\]'), '').trim();
      rawReply = profileUpdateReply(profileUpdates);
      if (_lastReplyFromGemini && geminiText.contains('?')) {
        final question = geminiText.substring(geminiText.lastIndexOf(RegExp(r'[.!]\s')) + 1).trim();
        if (question.endsWith('?')) rawReply = rawReply.replaceFirst(' Te abro tu perfil para que lo revises.', ' $question');
      }
      detectedAction = rawReply.contains('Te abro tu perfil') ? AppVoiceAction.openProfile : AppVoiceAction.none;
    }

    // Consultas del día: la respuesta se arma EN EL CÓDIGO con datos reales
    // (no con lo que diga Gemini) y después se abre la sección.
    if (detectedAction == AppVoiceAction.queryTremorToday) {
      _pendingContext = null;
      rawReply = await _buildTremorTodayReply();
    } else if (detectedAction == AppVoiceAction.queryMedicationToday) {
      _pendingContext = null;
      rawReply = await _buildMedicationsTodayReply();
    }

    // Completely strip ALL technical tags before UI rendering or TTS speech!
    final cleanReply = rawReply
        .replaceAll(RegExp(r'\[ACTION:[A-Z_]+\]'), '')
        .replaceAll(RegExp(r'\[ACTION:[A-Z_]+\|[^\]]*\]'), '')
        .replaceAll(RegExp(r'\[REGISTER_[A-Z_]+\|[^\]]+\]'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        // "8:00 a. m.." -> "8:00 a. m." (no toca los puntos suspensivos)
        .replaceAll(RegExp(r'(?<!\.)\.\s*\.(?!\.)'), '.')
        .trim();

    // Gemini detectó una emergencia con otras palabras: botones de llamada.
    final emergencyContacts =
        detectedAction == AppVoiceAction.emergency ? await _loadEmergencyContacts() : null;

    final finalResponse = VoiceAssistantResponse(
      textResponse: cleanReply.isNotEmpty
          ? cleanReply
          : 'Entendido, procesando tu solicitud.',
      action: detectedAction,
      isRegistrationExecuted: regResult.executed || localRegistered,
      targetName: targetName,
      emergencyContacts: emergencyContacts,
    );

    debugPrint('[Emki] Respuesta (${_lastReplyFromGemini ? "Gemini" : "respaldo local"}): '
        '"${finalResponse.textResponse}" acción=${finalResponse.action.name} '
        'registró=${finalResponse.isRegistrationExecuted}');

    // Speak ONLY the 100% clean conversational text
    await speak(finalResponse.textResponse);

    return finalResponse;
  }

  /// Parses and executes database inserts in Firestore when registration tags are present
  /// Ejecuta las etiquetas [REGISTER_...]. NO confía ciegamente en Gemini:
  /// si la frase del usuario no dice una hora concreta, o la hora de la
  /// etiqueta no es HH:MM válida, no guarda nada y pregunta la hora.
  Future<_RegistrationResult> _executeDataRegistration(String rawReply, String userPrompt) async {
    final bool userGaveTime = hasSpecificTimeReference(userPrompt);

    _RegistrationResult askTime({
      required String category,
      required String itemName,
      String? mealType,
      int? durationMinutes,
      String? intensity,
    }) {
      _pendingContext = PendingVoiceContext(
        category: category,
        step: StepState.itemNameExtracted,
        itemName: itemName,
        mealType: mealType,
        durationMinutes: durationMinutes,
        intensity: intensity,
      );
      final String question;
      switch (category) {
        case 'medication':
          question = '¿A qué hora tomaste $itemName? [ACTION:OPEN_MEDICATION]';
          break;
        case 'food':
          question = '¿A qué hora comiste $itemName? [ACTION:OPEN_HABITS_FOOD]';
          break;
        default:
          final dur = durationMinutes != null ? ' de $durationMinutes minutos' : '';
          question = '¿A qué hora hiciste tu ${itemName.toLowerCase()}$dur? [ACTION:OPEN_HABITS_ACTIVITY]';
      }
      debugPrint('[Emki] Registro rechazado: falta una hora concreta en "$userPrompt".');
      return _RegistrationResult(executed: false, rejected: true, cleanReply: question);
    }

    try {
      final now = DateTime.now();

      // 1. Medication Registration Tag
      final medMatch = RegExp(r'\[REGISTER_MEDICATION\|name=([^|]+)\|time=([^\]]+)\]')
          .firstMatch(rawReply);
      if (medMatch != null) {
        final name = _sanitizeTagName(medMatch.group(1)!, userPrompt, 'medication');
        final timeStr = medMatch.group(2)!.trim();
        if (!userGaveTime || !_isValidHhMm(timeStr)) {
          return askTime(category: 'medication', itemName: name);
        }
        final eventDateTime = _resolveEventDateTime(timeStr, now);
        final eventTimeOfDay =
            TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

        await _saveOfflineSafe(_firebaseService.addMedicationTask(
            name, eventDateTime, eventTimeOfDay, false));
        return _RegistrationResult(executed: true, cleanReply: rawReply);
      }

      // 2. Food Registration Tag
      final foodMatch = RegExp(
              r'\[REGISTER_FOOD\|food=([^|]+)\|mealType=([^|]+)\|time=([^\]]+)\]')
          .firstMatch(rawReply);
      if (foodMatch != null) {
        final food = _sanitizeTagName(foodMatch.group(1)!, userPrompt, 'food');
        final timeStr = foodMatch.group(3)!.trim();
        // Lo que dijo el usuario ("desayuné") manda sobre lo que puso Gemini;
        // si nadie lo dijo, se deduce por la hora del evento.
        final tagMeal = mealTypeKeyword(foodMatch.group(2)!);
        final mealType = mealTypeKeyword(userPrompt) ??
            tagMeal ??
            (_isValidHhMm(timeStr) ? mealTypeForHour(_resolveEventDateTime(timeStr, now)) : 'Almuerzo');
        if (!userGaveTime || !_isValidHhMm(timeStr)) {
          return askTime(category: 'food', itemName: food, mealType: mealType);
        }
        final eventDateTime = _resolveEventDateTime(timeStr, now);
        final eventTimeOfDay =
            TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

        await _saveOfflineSafe(_firebaseService.logFoodHabit(
            food, mealType, eventDateTime, eventTimeOfDay));
        return _RegistrationResult(executed: true, cleanReply: rawReply);
      }

      // 3. Activity Registration Tag
      final actMatch = RegExp(
              r'\[REGISTER_ACTIVITY\|activityType=([^|]+)\|duration=([^|]+)\|intensity=([^|]+)\|time=([^\]]+)\]')
          .firstMatch(rawReply);
      if (actMatch != null) {
        final activityType = _sanitizeTagName(actMatch.group(1)!, userPrompt, 'activity');
        final duration = int.tryParse(actMatch.group(2)!.trim()) ??
            extractDurationMinutes(userPrompt) ??
            30;
        final intensity = extractIntensity(actMatch.group(3)!);
        final timeStr = actMatch.group(4)!.trim();
        if (!userGaveTime || !_isValidHhMm(timeStr)) {
          return askTime(category: 'activity', itemName: activityType, durationMinutes: duration, intensity: intensity);
        }
        final eventDateTime = _resolveEventDateTime(timeStr, now);
        final eventTimeOfDay =
            TimeOfDay(hour: eventDateTime.hour, minute: eventDateTime.minute);

        await _saveOfflineSafe(_firebaseService.logActivityHabit(
            activityType, duration, intensity, eventDateTime, eventTimeOfDay));
        return _RegistrationResult(executed: true, cleanReply: rawReply);
      }
    } catch (e) {
      debugPrint('[Emki] Error al guardar el registro: $e');
    }

    return const _RegistrationResult(executed: false, cleanReply: '');
  }

  /// Nombre de la etiqueta de Gemini, corregido si copió la frase del usuario
  /// (p. ej. "Poner que me tomé la levodopa"): entonces se extrae del texto.
  static String _sanitizeTagName(String tagValue, String userPrompt, String category) {
    final n = normalizeText(tagValue);
    final looksLikePhrase = n.split(' ').length > 5 ||
        hasAnyWord(n, const [
          'tome', 'me tome', 'comi', 'desayune', 'almorce', 'cene', 'camine',
          'hice', 'poner', 'pon', 'registra', 'registrar', 'quiero', 'a las',
          'hace', 'minutos',
        ]);
    if (looksLikePhrase) {
      final fromUser = extractItemName(userPrompt, category);
      if (fromUser != null) return fromUser;
    }
    if (category == 'activity') return normalizeActivityName(tagValue);
    return _cleanEntityName(tagValue);
  }

  /// Nombre de actividad normalizado (Caminata, Trote, Natación, Bicicleta,
  /// Estiramientos, Yoga); si no se reconoce, el nombre limpio.
  static String normalizeActivityName(String raw) {
    final words = normalizeText(raw).split(' ');
    bool starts(String prefix) => words.any((w) => w.startsWith(prefix));
    if (starts('camin')) return 'Caminata';
    if (starts('trot') || starts('corr')) return 'Trote';
    if (starts('nad') || starts('natac') || starts('piscina')) return 'Natación';
    if (starts('bici') || starts('ciclis')) return 'Bicicleta';
    if (starts('estir')) return 'Estiramientos';
    if (starts('yoga')) return 'Yoga';
    return _cleanEntityName(raw);
  }

  /// Actualiza el contexto pendiente a partir de una respuesta de GEMINI
  /// (solo se llama si respondió Gemini). Solo crea contexto si Gemini hizo
  /// una pregunta sobre un registro; si pregunta la hora, guarda el nombre del
  /// elemento (y tipo de comida, duración, intensidad) dicho por el usuario.
  void _updatePendingContextFromQuery(String query, String assistantReply) {
    final q = normalizeText(query);
    final a = normalizeText(assistantReply);
    final isQuestion = assistantReply.contains('?');
    final asksTime = hasAnyWord(a, const ['a que hora', 'cuando', 'que hora']);

    var ctx = _pendingContext;
    final isNew = ctx == null;
    if (ctx == null) {
      if (!isQuestion) return; // sin pregunta, no hay registro en curso
      String? category;
      if (assistantReply.contains('[ACTION:OPEN_MEDICATION]') || hasAnyWord(q, _medicationWords)) {
        category = 'medication';
      } else if (assistantReply.contains('[ACTION:OPEN_HABITS_FOOD]') || hasAnyWord(q, _foodWords)) {
        category = 'food';
      } else if (assistantReply.contains('[ACTION:OPEN_HABITS_ACTIVITY]') || hasAnyWord(q, _activityWords)) {
        category = 'activity';
      }
      if (category == null) return;
      ctx = PendingVoiceContext(category: category, step: StepState.categoryIdentified);
    }

    // Si el usuario respondía "¿qué medicamento?", su frase completa es el nombre.
    final name = extractItemName(
      query,
      ctx.category,
      wholeIfNoMarker: !isNew && ctx.step == StepState.categoryIdentified,
    );
    if (name != null) ctx.itemName ??= name;
    if (ctx.category == 'food') ctx.mealType ??= mealTypeKeyword(query);
    if (ctx.category == 'activity') {
      ctx.durationMinutes ??= extractDurationMinutes(query);
      if (hasAnyWord(q, const ['leve', 'suave', 'alta', 'fuerte', 'intensidad'])) {
        ctx.intensity = extractIntensity(query);
      }
    }
    if (asksTime && ctx.itemName != null) ctx.step = StepState.itemNameExtracted;
    _pendingContext = ctx;
  }

  /// ¿La frase cancela? Frases: cancela, cancelar, cancélalo, olvídalo,
  /// déjalo, ya no, mejor no, no gracias, detente. "no" solo si es la frase
  /// completa (bug real: "Cancela" no cancelaba y se guardaba como nombre).
  @visibleForTesting
  static bool isCancel(String prompt) {
    final n = normalizeText(prompt);
    if (n.isEmpty) return false;
    if (const {'no', 'no no', 'nada', 'no nada'}.contains(n)) return true;
    // Verbos de cancelar: valen en cualquier parte de una frase corta.
    const verbs = [
      'cancela', 'cancelar', 'cancelalo', 'cancelala', 'cancelemos', 'cancelo',
      'olvidalo', 'olvidala', 'olvida eso', 'olvidate', 'dejalo', 'dejala',
      'deja eso', 'detente', 'detenlo', 'no lo registres', 'no registres',
      'no lo guardes', 'no guardes',
    ];
    if (n.split(' ').length <= 6 && hasAnyWord(n, verbs)) return true;
    // Expresiones que solo cancelan si inician la frase ("ya no me tiembla" no).
    const starts = ['ya no', 'mejor no', 'no gracias', 'no quiero', 'no mejor no'];
    for (final s in starts) {
      if (n == s || (n.startsWith('$s ') && n.split(' ').length <= 5)) return true;
    }
    return false;
  }

  /// ¿Es un comando para ir a otra parte de la app (no un nombre ni una hora)?
  @visibleForTesting
  static bool isNavigationCommand(String prompt) {
    final n = normalizeText(prompt);
    final action = _detectActionFromPrompt(prompt);
    const strong = {
      AppVoiceAction.openHome,
      AppVoiceAction.queryTremorToday,
      AppVoiceAction.queryMedicationToday,
      AppVoiceAction.openReminders,
      AppVoiceAction.emergency,
      AppVoiceAction.callContact,
      AppVoiceAction.openTremor,
      AppVoiceAction.openCommunity,
      AppVoiceAction.openCommunityCompanions,
      AppVoiceAction.openCommunityGroups,
      AppVoiceAction.openCommunityLessons,
      AppVoiceAction.openCompanionProfile,
      AppVoiceAction.openCommunityGroup,
      AppVoiceAction.openCommunityLesson,
      AppVoiceAction.openProfile,
      AppVoiceAction.togglePrivacyPrivate,
      AppVoiceAction.togglePrivacyPublic,
    };
    if (strong.contains(action)) return true;
    // "abre medicamentos" sí es navegación; "levodopa" sola no.
    const navVerbs = [
      'abre', 'abrir', 'abreme', 'ir a', 've a', 'vamos a', 'llevame',
      'muestrame', 'mostrar', 'ensename', 'vuelve', 'regresa', 'volver',
    ];
    return action != AppVoiceAction.none && hasAnyWord(n, navVerbs);
  }

  /// Respaldo local (sin Gemini). Devuelve la respuesta y si se guardó algo.
  Future<({String reply, bool registered})?> _tryLocalRegistrationFallback(String prompt) async {
    _localRegisteredFlag = false;
    final reply = await _localFallbackReply(prompt);
    if (reply == null) return null;
    return (reply: reply, registered: _localRegisteredFlag);
  }

  Future<String?> _localFallbackReply(String prompt) async {
    final norm = normalizeText(prompt);
    final now = DateTime.now();

    // Cancelación (misma regla que processPrompt).
    if (isCancel(prompt)) {
      _pendingContext = null;
      return 'Listo, cancelé el registro. No guardé nada.';
    }

    // Comando de navegación en medio de un registro: no es nombre ni hora.
    if (_pendingContext != null && isNavigationCommand(prompt)) {
      _pendingContext = null;
      return null; // processPrompt responde con la navegación
    }

    // Privacy toggle commands
    if (hasAnyWord(norm, _privatePhrases)) {
      await _saveOfflineSafe(_firebaseService.updatePrivacy(false));
      return 'Tu perfil ahora es privado. [ACTION:PRIVACY_PRIVATE]';
    }
    if (hasAnyWord(norm, _publicPhrases)) {
      await _saveOfflineSafe(_firebaseService.updatePrivacy(true));
      return 'Tu perfil ahora es público. [ACTION:PRIVACY_PUBLIC]';
    }

    // Step 1: User indicates category intent without item name
    // ("registra un medicamento", "quiero registrar mi comida", "anota ejercicio").
    final categoryIntent = RegExp(
      r'^(?:quiero |voy a |puedes |me ayudas a )?(?:registrar|registra|registrame|anotar|anota|apunta) '
      r'(?:un |una |mi |el |la )?(medicamento|medicina|pastilla|comida|alimento|desayuno|almuerzo|cena|actividad fisica|actividad|ejercicio)$',
    ).firstMatch(norm);
    if (categoryIntent != null) {
      final noun = categoryIntent.group(1)!;
      if (const ['medicamento', 'medicina', 'pastilla'].contains(noun)) {
        _pendingContext = PendingVoiceContext(category: 'medication', step: StepState.categoryIdentified);
        return 'Por supuesto, vamos a registrar tu medicamento. ¿Qué medicamento tomaste?';
      }
      if (const ['actividad fisica', 'actividad', 'ejercicio'].contains(noun)) {
        _pendingContext = PendingVoiceContext(category: 'activity', step: StepState.categoryIdentified);
        return '¡Claro! Vamos a registrar tu actividad física. ¿Qué actividad física realizaste?';
      }
      _pendingContext = PendingVoiceContext(category: 'food', step: StepState.categoryIdentified);
      return '¡Claro! Vamos a registrar tu comida. ¿Qué comiste?';
    }

    // Step 2 & 3: Sequential Handling with Pending Context
    if (_pendingContext != null) {
      final ctx = _pendingContext!;

      if (ctx.step == StepState.categoryIdentified) {
        // El usuario dice el elemento en este turno (y quizá también la hora).
        final name = extractItemName(prompt, ctx.category, wholeIfNoMarker: true);
        if (name == null) return _askItemName(ctx.category);
        ctx.itemName = name;
        ctx.mealType ??= mealTypeKeyword(prompt);
        ctx.durationMinutes ??= extractDurationMinutes(prompt);
        if (hasAnyWord(norm, const ['leve', 'suave', 'alta', 'fuerte', 'intensidad'])) {
          ctx.intensity = extractIntensity(prompt);
        }
        ctx.step = StepState.itemNameExtracted;
        final at = extractEventDateTime(prompt, now);
        if (at != null) return _registerLocally(ctx, at);
        return _askTimeFor(ctx);
      } else if (ctx.step == StepState.itemNameExtracted) {
        // El usuario dice la hora en este turno. Si no se entiende, se vuelve a
        // preguntar (antes registraba con la hora actual).
        final at = extractEventDateTime(prompt, now);
        if (at == null) {
          return 'No entendí la hora. ¿A qué hora fue? Por ejemplo: a las 8 de la mañana, o hace media hora.';
        }
        return _registerLocally(ctx, at);
      }
    }

    // Registro directo en una frase (palabras completas: 'tomate' ya no es 'tome').
    String? category;
    if (hasAnyWord(norm, const ['tome', 'me tome', 'ya tome', 'tomo', 'levodopa'])) {
      category = 'medication';
    } else if (hasAnyWord(norm, const ['comi', 'me comi', 'desayune', 'almorce', 'cene', 'merende'])) {
      category = 'food';
    } else if (hasAnyWord(norm, const [
      'camine', 'trote', 'nade', 'hice ejercicio', 'caminata', 'ejercicio',
      'estiramiento', 'estiramientos', 'yoga', 'bicicleta',
    ])) {
      category = 'activity';
    }
    if (category != null) {
      final ctx = PendingVoiceContext(
        category: category,
        itemName: extractItemName(prompt, category),
        mealType: category == 'food' ? mealTypeKeyword(prompt) : null,
        durationMinutes: category == 'activity' ? extractDurationMinutes(prompt) : null,
        intensity: category == 'activity' ? extractIntensity(prompt) : null,
      );
      _pendingContext = ctx;
      if (ctx.itemName == null) {
        // "Me tomé el medicamento" / "hice ejercicio": falta el nombre.
        ctx.step = StepState.categoryIdentified;
        return _askItemName(category);
      }
      ctx.step = StepState.itemNameExtracted;
      final at = extractEventDateTime(prompt, now);
      if (at == null) return _askTimeFor(ctx);
      return _registerLocally(ctx, at);
    }

    return null;
  }

  static String _askItemName(String category) {
    switch (category) {
      case 'medication':
        return '¿Qué medicamento tomaste? [ACTION:OPEN_MEDICATION]';
      case 'food':
        return '¿Qué comiste? [ACTION:OPEN_HABITS_FOOD]';
      default:
        return '¿Qué actividad hiciste? Por ejemplo: caminata, estiramientos o yoga. [ACTION:OPEN_HABITS_ACTIVITY]';
    }
  }

  static String _askTimeFor(PendingVoiceContext ctx) {
    final name = ctx.itemName ?? '';
    switch (ctx.category) {
      case 'medication':
        return '¿A qué hora tomaste $name? [ACTION:OPEN_MEDICATION]';
      case 'food':
        return '¿A qué hora comiste ${name.toLowerCase()}? [ACTION:OPEN_HABITS_FOOD]';
      default:
        final dur = ctx.durationMinutes != null ? ' de ${ctx.durationMinutes} minutos' : '';
        return '¿A qué hora hiciste tu ${name.toLowerCase()}$dur? [ACTION:OPEN_HABITS_ACTIVITY]';
    }
  }

  /// Guarda el registro del respaldo local con los datos del contexto y
  /// devuelve la respuesta (con su etiqueta de navegación).
  Future<String> _registerLocally(PendingVoiceContext ctx, DateTime at) async {
    final timeOfDay = TimeOfDay(hour: at.hour, minute: at.minute);
    final formattedTime = _formatTimeDisplay(timeOfDay);
    final name = ctx.itemName ?? 'Elemento';
    _pendingContext = null;
    _localRegisteredFlag = true;
    switch (ctx.category) {
      case 'medication':
        await _saveOfflineSafe(_firebaseService.addMedicationTask(name, at, timeOfDay, false));
        return 'Registré la toma de $name a las $formattedTime [ACTION:OPEN_MEDICATION]';
      case 'food':
        final mealType = ctx.mealType ?? mealTypeForHour(at);
        await _saveOfflineSafe(_firebaseService.logFoodHabit(name, mealType, at, timeOfDay));
        return 'Registré tu ${mealType.toLowerCase()}: ${name.toLowerCase()}, a las $formattedTime [ACTION:OPEN_HABITS_FOOD]';
      default:
        final duration = ctx.durationMinutes ?? 30;
        final intensity = ctx.intensity ?? 'Media';
        await _saveOfflineSafe(_firebaseService.logActivityHabit(name, duration, intensity, at, timeOfDay));
        return 'Registré tu ${name.toLowerCase()} de $duration minutos, intensidad ${intensity.toLowerCase()}, '
            'a las $formattedTime [ACTION:OPEN_HABITS_ACTIVITY]';
    }
  }

  DateTime _resolveEventDateTime(String timeStr, DateTime referenceNow) {
    final cleanStr = timeStr.trim().toUpperCase();
    if (cleanStr == 'NOW' ||
        cleanStr.contains('AHORITA') ||
        cleanStr.contains('ACTUAL')) {
      return referenceNow;
    }

    final parsedTime = _parseTimeOfDay(timeStr);
    return DateTime(
      referenceNow.year,
      referenceNow.month,
      referenceNow.day,
      parsedTime.hour,
      parsedTime.minute,
    );
  }

  static String _cleanEntityName(String raw) {
    var s = raw.trim();

    // Remove leading conversational noise, verbs, politeness, and articles
    final leadingNoise = RegExp(
      r'^(hola|por favor|buenas|buenos días|buenas tardes|porfa|me gustaría|quisiera|quiero|necesito|puedes|registra que|registra|registrar|me tomé|me tome|ya tomé|ya tome|tomé|tome|tomar|me comí|me comi|ya comí|ya comi|comí|comi|comer|hice|hacer|fui a|fui|realicé|realice|acabo de|mi|mis|el|la|los|las|un|una|unos|unas|medicamento|alimento|comida|ejercicio|actividad|de)\s+',
      caseSensitive: false,
    );

    while (leadingNoise.hasMatch(s)) {
      s = s.replaceAll(leadingNoise, '').trim();
    }

    // Remove trailing time phrases or noise
    s = s.replaceAll(RegExp(r'\s+(ahorita|recien|recién|hoy|ayer|hace un momento|a las \d+.*)$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'[.,;:!?]+$'), '').trim();

    if (s.isEmpty) return raw.trim();

    // Capitalize first letter while preserving multi-word phrases (e.g. "Arroz con pollo")
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Duración en minutos: "30 minutos", "treinta minutos", "media hora" (30),
  /// "una hora" (60), "hora y media" (90), "2 horas". Ignora tiempos relativos
  /// ("hace 20 minutos") y horas de reloj ("a las 2").
  @visibleForTesting
  static int? extractDurationMinutes(String prompt) {
    final n = normalizeText(prompt);

    bool isRelativeOrClock(int start) {
      final before = n.substring(0, start).trimRight();
      return before.endsWith('hace') || before.endsWith('a las') || before.endsWith('a la');
    }

    // "una hora y media" / "hora y media"
    for (final m in RegExp(r'(?:^| )((?:una )?hora y media)(?= |$)').allMatches(n)) {
      if (!isRelativeOrClock(m.start + (m.group(0)!.startsWith(' ') ? 1 : 0))) return 90;
    }
    // "media hora"
    for (final m in RegExp(r'(?:^| )(media hora)(?= |$)').allMatches(n)) {
      if (!isRelativeOrClock(m.start + (m.group(0)!.startsWith(' ') ? 1 : 0))) return 30;
    }
    // "N minutos" / "N horas [y media]" (N en dígitos o palabras)
    final re = RegExp(r'(?:^| )(\d{1,3}|[a-z]+(?: y [a-z]+)?) (min|minuto|minutos|hora|horas)( y media)?(?= |$)');
    for (final m in re.allMatches(n)) {
      final start = m.start + (m.group(0)!.startsWith(' ') ? 1 : 0);
      if (isRelativeOrClock(start)) continue;
      final amount = _parseNumber(m.group(1)!);
      if (amount == null || amount <= 0) continue;
      final isHours = m.group(2)!.startsWith('hora');
      var minutes = isHours ? amount * 60 : amount;
      if (isHours && m.group(3) != null) minutes += 30;
      return minutes;
    }
    return null;
  }

  String _formatTimeDisplay(TimeOfDay timeOfDay) {
    final hour = timeOfDay.hourOfPeriod == 0 ? 12 : timeOfDay.hourOfPeriod;
    final min = timeOfDay.minute.toString().padLeft(2, '0');
    final period = timeOfDay.period == DayPeriod.am ? 'a. m.' : 'p. m.';
    return '$hour:$min $period';
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final clean = timeStr.toLowerCase().replaceAll(' ', '');
      final isPm = clean.contains('pm') || clean.contains('p.m.');
      final digits = clean.replaceAll(RegExp(r'[^0-9:]'), '');
      final parts = digits.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (!isPm && clean.contains('am') && hour == 12) hour = 0;

      return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
    } catch (_) {
      return TimeOfDay.now();
    }
  }

  /// Tipo de comida dicho explícitamente, o null si la frase no lo dice.
  /// desayun* -> Desayuno; almorz*/almuerz* -> Almuerzo; cena/cené/cenar -> Cena;
  /// merend*/onces/snack -> Merienda.
  @visibleForTesting
  static String? mealTypeKeyword(String raw) {
    final words = normalizeText(raw).split(' ');
    bool starts(String p) => words.any((w) => w.startsWith(p));
    if (starts('desayun')) return 'Desayuno';
    // "almorcé" -> almorce (c), "almorzar" -> almorz (z), "almuerzo" -> almuerz
    if (starts('almorc') || starts('almorz') || starts('almuerz')) return 'Almuerzo';
    if (words.any((w) => const {'cena', 'cene', 'cenar', 'ceno', 'cenamos', 'cenando'}.contains(w))) {
      return 'Cena';
    }
    if (starts('merend') || starts('merienda') || words.contains('onces') || words.contains('snack')) {
      return 'Merienda';
    }
    return null;
  }

  /// Tipo de comida según la hora: 4-10 Desayuno, 11-15 Almuerzo,
  /// 16-17 Merienda, resto Cena.
  @visibleForTesting
  static String mealTypeForHour(DateTime at) {
    final h = at.hour;
    if (h >= 4 && h <= 10) return 'Desayuno';
    if (h >= 11 && h <= 15) return 'Almuerzo';
    if (h >= 16 && h <= 17) return 'Merienda';
    return 'Cena';
  }

  /// Tipo de comida: el que dice la frase; si no dice ninguno, por la hora.
  @visibleForTesting
  static String normalizeMealType(String raw, {DateTime? at}) =>
      mealTypeKeyword(raw) ?? mealTypeForHour(at ?? DateTime.now());

  /// Intensidad de la actividad (Leve/Media/Alta); Media si no se indica.
  @visibleForTesting
  static String extractIntensity(String raw) {
    final n = normalizeText(raw);
    if (hasAnyWord(n, const [
      'alta', 'intensidad alta', 'alta intensidad', 'fuerte', 'intenso',
      'intensa', 'rapido', 'rapida', 'vigoroso', 'vigorosa',
    ])) {
      return 'Alta';
    }
    if (hasAnyWord(n, const [
      'leve', 'baja', 'intensidad baja', 'suave', 'despacio', 'ligero',
      'ligera', 'tranquilo', 'tranquila', 'lento', 'lenta',
    ])) {
      return 'Leve';
    }
    return 'Media';
  }

  // Palabras tras las que viene el nombre del elemento, por categoría.
  static const Map<String, List<String>> _itemMarkers = {
    'medication': [
      'tome', 'tomo', 'tomado', 'tomar', 'tomarme', 'tomarse', 'medicamento',
      'medicamentos', 'medicina', 'pastilla', 'pastillas', 'remedio', 'dosis',
    ],
    'food': [
      'comi', 'comimos', 'comer', 'desayune', 'desayunar', 'desayuno',
      'almorce', 'almorzar', 'almuerzo', 'cene', 'cenar', 'cena', 'merende',
      'merendar', 'merienda', 'onces',
    ],
    'activity': ['hice', 'realice', 'practique', 'hacer', 'actividad', 'ejercicio'],
  };

  // Palabras que, al inicio del nombre, se quitan (artículos, relleno, genéricos).
  static const Set<String> _leadingNoise = {
    'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'mi', 'mis', 'su',
    'sus', 'de', 'del', 'que', 'me', 'ya', 'se', 'lo', 'le', 'al', 'poner',
    'pon', 'registra', 'registrar', 'registrame', 'anota', 'anotar', 'apunta',
    'medicamento', 'medicamentos', 'medicina', 'medicinas', 'pastilla',
    'pastillas', 'remedio', 'remedios', 'pildora', 'pildoras', 'dosis',
    'comida', 'alimento', 'alimentos', 'actividad', 'fisica', 'tome', 'comi',
    'desayune', 'almorce', 'cene', 'hice', 'por', 'favor', 'porfa', 'hoy',
    'ayer', 'y',
  };

  // Palabras que, al final del nombre, se quitan (conectores sueltos).
  static const Set<String> _trailingNoise = {
    'y', 'de', 'del', 'con', 'la', 'el', 'los', 'las', 'a', 'en', 'que', 'mi',
    'un', 'una', 'para', 'por', 'hoy', 'ya',
  };

  // Nombres que no sirven: se pregunta qué fue exactamente.
  static const Set<String> _genericItemNames = {
    'algo', 'eso', 'esto', 'ejercicio', 'ejercicios', 'actividad',
    'actividad fisica', 'deporte', 'comida', 'medicamento', 'medicina',
    'pastilla', 'remedio', 'alimento', 'registrarlo', 'registrar', 'nada',
  };

  /// ¿En la posición [i] de [norm] empieza algo que corta el nombre?
  /// (tiempo, duración, intensidad o relleno).
  static bool _isNameStop(List<String> norm, int i) {
    final w = norm[i];
    final next = i + 1 < norm.length ? norm[i + 1] : '';
    final next2 = i + 2 < norm.length ? norm[i + 2] : '';
    if (const {'hace', 'ahora', 'ahorita', 'recien', 'hoy', 'ayer', 'anoche',
        'quiero', 'quisiera', 'porfa', 'durante', 'mientras', 'acabo',
        'esta', 'este', 'al', 'apenas'}.contains(w)) {
      return true;
    }
    if (w == 'por' && next == 'favor') return true;
    if (w == 'a' && const {'las', 'la', 'eso', 'intensidad', 'mediodia', 'medianoche'}.contains(next)) return true;
    if (w == 'en' && const {'la', 'el', 'este', 'esta'}.contains(next) &&
        const {'mañana', 'tarde', 'noche', 'desayuno', 'almuerzo', 'cena', 'momento', 'rato'}.contains(next2)) {
      return true;
    }
    if (const {'de', 'con'}.contains(w) && next == 'intensidad') return true;
    if (const {'intensidad', 'leve', 'suave', 'fuerte'}.contains(w)) return true;
    // Duración: "30 minutos", "treinta minutos", "una hora", "media hora"
    if ((int.tryParse(w) != null || _numberWords.containsKey(w) || w == 'media') &&
        const {'min', 'minuto', 'minutos', 'hora', 'horas'}.contains(next)) {
      return true;
    }
    return false;
  }

  /// Nombre del elemento (medicamento, comida o actividad) o null si no se
  /// dijo uno concreto (entonces se pregunta). Busca el verbo de la categoría
  /// en CUALQUIER posición y toma lo que sigue, cortando en expresiones de
  /// tiempo, duración, intensidad o relleno.
  /// Si [wholeIfNoMarker] es true y no hay verbo, usa la frase completa
  /// (respuesta a "¿qué medicamento tomaste?").
  @visibleForTesting
  static String? extractItemName(String prompt, String category, {bool wholeIfNoMarker = false}) {
    if (category == 'activity') {
      final known = normalizeActivityName(prompt);
      if (const {'Caminata', 'Trote', 'Natación', 'Bicicleta', 'Estiramientos', 'Yoga'}.contains(known)) {
        return known;
      }
    }

    // Tokens originales (conservan tildes) y normalizados, en paralelo.
    final original = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final norm = original.map(normalizeText).toList();

    final markers = _itemMarkers[category] ?? const <String>[];
    var start = -1;
    for (var i = 0; i < norm.length; i++) {
      if (markers.contains(norm[i])) start = i + 1; // el ÚLTIMO verbo/sustantivo marcador
      if (start >= 0 && i >= start && _isNameStop(norm, i)) break;
    }
    if (start < 0) {
      if (!wholeIfNoMarker) return null;
      start = 0;
    }

    var end = start;
    while (end < norm.length && !_isNameStop(norm, end)) {
      end++;
    }
    var from = start;
    var to = end;
    while (from < to && _leadingNoise.contains(norm[from])) {
      from++;
    }
    while (to > from && _trailingNoise.contains(norm[to - 1])) {
      to--;
    }
    if (from >= to) return null;

    final name = original.sublist(from, to).join(' ');
    if (_genericItemNames.contains(normalizeText(name))) return null;
    if (category == 'activity') {
      final known = normalizeActivityName(name);
      return known;
    }
    return name[0].toUpperCase() + name.substring(1);
  }

  // ================= CONSULTAS DEL DÍA (FASE 5) =================

  static bool _isDayQuery(AppVoiceAction a) =>
      a == AppVoiceAction.queryTremorToday ||
      a == AppVoiceAction.queryMedicationToday ||
      a == AppVoiceAction.openReminders; // tampoco pasa por el respaldo de registro

  /// "Quiero poner un recordatorio para tomar la amoxicilina", "recuérdame la
  /// levodopa", "prográmame una alarma de mis pastillas" -> openReminders.
  @visibleForTesting
  static bool isReminderRequest(String prompt) {
    final n = normalizeText(prompt);
    if (hasAnyWord(n, const [
      'recordatorio', 'recordatorios', 'recuerdame', 'recordarme', 'recuerdeme',
      'alarma', 'alarmas', 'avisame', 'avisarme', 'notificacion', 'notificaciones',
    ])) {
      return true;
    }
    return hasAnyWord(n, const ['programa', 'programar', 'programame']) &&
        hasAnyWord(n, _medicationWords);
  }

  static const Map<String, int> _weekdayWords = {
    'lunes': 1, 'martes': 2, 'miercoles': 3, 'jueves': 4, 'viernes': 5,
    'sabado': 6, 'sabados': 6, 'domingo': 7, 'domingos': 7,
  };

  /// Borrador de recordatorio a partir de la frase (para prellenar el editor):
  /// medicamento, horas ("a las 8 y a las 8 de la noche", "cada 8 horas"),
  /// días ("todos los días", "lunes y jueves", "entre semana") y duración
  /// ("durante 7 días", "por 2 semanas"). Lo que no se diga queda vacío.
  @visibleForTesting
  static MedicationReminder extractReminderDraft(String prompt, DateTime now) {
    final n = normalizeText(prompt);
    final today = DateTime(now.year, now.month, now.day);

    // --- Horas ---
    final times = <TimeOfDay>[];
    void addTime(int hour, int minute) {
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return;
      if (times.any((t) => t.hour == hour && t.minute == minute)) return;
      times.add(TimeOfDay(hour: hour, minute: minute));
    }

    // "ahorita", "hoy", "en un rato": la hora sin a. m./p. m. es la próxima.
    final soonish = hasAnyWord(n, const [
      'ahorita', 'ahora', 'hoy', 'en un rato', 'dentro de', 'mas tarde', 'esta tarde', 'esta noche',
    ]);
    final clock = RegExp('(?:^| )(?:a las?|y las?) (\\d{1,2}|[a-z]+)(?: (\\d{2}))?'
        '(?: (y media|y cuarto|menos cuarto))?(?: ($_periodPattern))?(?= |\$)');
    for (final m in clock.allMatches(n)) {
      final h0 = _parseNumber(m.group(1)!);
      if (h0 == null || h0 > 23) continue;
      var hour = h0;
      var minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
      final frac = m.group(3);
      if (frac == 'y media') minute = 30;
      if (frac == 'y cuarto') minute = 15;
      if (frac == 'menos cuarto') {
        minute = 45;
        hour = (hour + 23) % 24;
      }
      final period = m.group(4);
      if (period != null) {
        final pm = period == 'pm' || period == 'p m' || period.contains('tarde') || period.contains('noche');
        if (pm && hour < 12) hour += 12;
        if (!pm && hour == 12) hour = 0;
      } else if (soonish && hour >= 1 && hour <= 11) {
        // "ahorita a las 4:55" dicho a las 4:53 p. m. -> 16:55, no 4:55 a. m.:
        // la próxima vez que llegue esa hora.
        final nowMin = now.hour * 60 + now.minute;
        if (hour * 60 + minute < nowMin && (hour + 12) * 60 + minute >= nowMin) hour += 12;
      }
      addTime(hour, minute);
    }

    // "cada 8 horas" -> desde la primera hora dicha (o 8:00) hasta completar el día
    final every = RegExp(r'(?:^| )cada (\d{1,2}|[a-z]+) horas?(?= |$)').firstMatch(n);
    final step = every != null ? _parseNumber(every.group(1)!) : null;
    if (step != null && step >= 1 && step <= 12) {
      final first = times.isNotEmpty ? times.first : const TimeOfDay(hour: 8, minute: 0);
      var minutes = first.hour * 60 + first.minute;
      for (var i = 0; i < 24 ~/ step; i++) {
        addTime((minutes ~/ 60) % 24, minutes % 60);
        minutes += step * 60;
      }
    }
    times.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    // --- Días ---
    final weekdays = <int>{};
    if (hasAnyWord(n, const ['entre semana', 'dias de semana', 'de lunes a viernes'])) {
      weekdays.addAll([1, 2, 3, 4, 5]);
    } else if (hasAnyWord(n, const ['fines de semana', 'fin de semana'])) {
      weekdays.addAll([6, 7]);
    } else if (!hasAnyWord(n, const ['todos los dias', 'diario', 'diariamente', 'cada dia'])) {
      _weekdayWords.forEach((w, d) {
        if (hasWord(n, w)) weekdays.add(d);
      });
    }

    // --- Duración ---
    DateTime? endDate;
    final dur = RegExp(r'(?:^| )(?:durante|por) (\d{1,3}|[a-z]+) (dia|dias|semana|semanas|mes|meses)(?= |$)')
        .firstMatch(n);
    final amount = dur != null ? _parseNumber(dur.group(1)!) : null;
    if (amount != null && amount > 0) {
      final unit = dur!.group(2)!;
      final days = unit.startsWith('dia') ? amount : unit.startsWith('semana') ? amount * 7 : amount * 30;
      endDate = today.add(Duration(days: days - 1));
    }

    return MedicationReminder(
      id: '',
      name: extractReminderMedication(prompt) ?? '',
      times: times,
      weekdays: weekdays.toList()..sort(),
      startDate: today,
      endDate: endDate,
    );
  }

  /// Respuesta hablada para un pedido de recordatorio.
  static String reminderReply(MedicationReminder d) {
    String fmt(TimeOfDay t) {
      final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
      return '$h12:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'a. m.' : 'p. m.'}';
    }

    final parts = <String>[];
    if (d.name.isNotEmpty) parts.add('de ${d.name}');
    if (d.times.isNotEmpty) {
      final ts = d.times.map(fmt).toList();
      parts.add(ts.length == 1
          ? 'a las ${ts.first}'
          : 'a las ${ts.sublist(0, ts.length - 1).join(', ')} y ${ts.last}');
    }
    if (d.weekdays.isNotEmpty) parts.add(d.weekdaysLabel.toLowerCase());
    if (d.endDate != null) {
      final days = d.endDate!.difference(d.startDate).inDays + 1;
      parts.add('durante $days ${days == 1 ? 'día' : 'días'}');
    }
    final what = parts.isEmpty ? '' : ' ${parts.join(', ')}';
    final missing = <String>[
      if (d.name.isEmpty) 'el medicamento',
      if (d.times.isEmpty) 'las horas',
    ];
    final ask = missing.isEmpty
        ? 'Revisa los datos y toca Guardar.'
        : 'Completa ${missing.join(' y ')} y toca Guardar.';
    final head = 'Te abro el recordatorio$what';
    return '${head.endsWith('.') ? head : '$head.'} $ask'; // sin "a. m.."
  }

  /// Medicamento mencionado en un pedido de recordatorio (o null).
  @visibleForTesting
  static String? extractReminderMedication(String prompt) {
    final fromVerb = extractItemName(prompt, 'medication');
    if (fromVerb != null && !_genericItemNames.contains(normalizeText(fromVerb))) {
      return fromVerb;
    }
    // "recuérdame la levodopa", "recordatorio de amoxicilina"
    final m = RegExp(
      r'(?:recuerdame|recordarme|recuerdeme|recordatorio|alarma|avisame)'
      r'(?: de| para| que)?(?: tomar| tome| tomarme)?(?: la| el| mi| mis| las| los)?'
      r' ([a-zñ0-9 ]+?)(?= a las| todos| cada| por la| en la| hoy| manana| mañana|$)',
    ).firstMatch(normalizeText(prompt));
    final raw = m?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    var words = raw.split(' ');
    // Lo que viene después del último "tomar/tome" ("que me tengo que tomar la X").
    final lastTake = words.lastIndexWhere((w) => const {'tomar', 'tome', 'tomarme', 'tomo'}.contains(w));
    if (lastTake >= 0) words = words.sublist(lastTake + 1);
    const filler = {'tengo', 'debo', 'quiero', 'poner', 'pon', 'hay', 'necesito'};
    words = words.where((w) => !_leadingNoise.contains(w) && !filler.contains(w)).toList();
    if (words.isEmpty) return null;
    final normName = words.join(' ');
    if (_genericItemNames.contains(normName)) return null;

    // Recupera las palabras como se dijeron (con tildes): "losartán", no "losartan".
    final original = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .split(' ');
    final norm = original.map(normalizeText).toList();
    for (var i = 0; i + words.length <= norm.length; i++) {
      if (norm.sublist(i, i + words.length).join(' ') == normName) {
        final name = original.sublist(i, i + words.length).join(' ');
        return name[0].toUpperCase() + name.substring(1);
      }
    }
    return normName[0].toUpperCase() + normName.substring(1);
  }

  /// "¿Cómo ha estado mi temblor hoy?" -> queryTremorToday;
  /// "¿Qué medicamentos tengo hoy?" -> queryMedicationToday; si no, none.
  /// Una frase de registro ("me tomé...") nunca es consulta.
  @visibleForTesting
  static AppVoiceAction detectDayQuery(String prompt) {
    final n = normalizeText(prompt);
    if (hasAnyWord(n, const [
      'tome', 'me tome', 'ya tome', 'comi', 'desayune', 'almorce', 'cene',
      'camine', 'registra', 'registrar', 'anota', 'apunta',
    ])) {
      return AppVoiceAction.none;
    }
    // Pregunta: palabra interrogativa AL INICIO ("siento que tengo temblor" no
    // es pregunta) o un verbo de consulta en cualquier parte.
    final start = n.replaceFirst(RegExp(r'^(?:oye |hola |emki |oye emki |por favor )+'), '');
    final firstWord = start.split(' ').first;
    final asks = const {
          'como', 'que', 'cuales', 'cual', 'cuantas', 'cuantos', 'cuanto', 'cuanta',
        }.contains(firstWord) ||
        hasAnyWord(n, const ['resumen', 'dime', 'cuentame', 'revisa', 'consulta', 'muestrame', 'quiero saber']);
    if (!asks) return AppVoiceAction.none;

    if (hasAnyWord(n, const ['temblor', 'temblores', 'tiemblo', 'temblado'])) {
      if (hasAnyWord(n, const [
        'hoy', 'dia', 'ha estado', 'he estado', 'como va', 'como voy',
        'como estuvo', 'como esta', 'resumen', 'cuanto', 'cuanta',
      ])) {
        return AppVoiceAction.queryTremorToday;
      }
    }
    if (hasAnyWord(n, const [
      'medicamento', 'medicamentos', 'medicina', 'medicinas', 'pastilla',
      'pastillas', 'remedio', 'remedios', 'dosis', 'tomas',
    ])) {
      if (hasAnyWord(n, const [
        'hoy', 'tengo', 'me toca', 'me tocan', 'me falta', 'me faltan',
        'pendiente', 'pendientes', 'debo tomar', 'tengo que tomar', 'faltan',
      ])) {
        return AppVoiceAction.queryMedicationToday;
      }
    }
    return AppVoiceAction.none;
  }

  static const String _noDataConnection =
      'No pude consultar tus datos ahora mismo. Te abro la sección para que los revises.';

  /// "12 minutos", "1 hora y 5 minutos", "menos de un minuto".
  static String _fmtMinutes(double minutes) {
    final total = minutes.round();
    if (minutes < 1) return 'menos de un minuto';
    if (total < 60) return total == 1 ? '1 minuto' : '$total minutos';
    final h = total ~/ 60;
    final m = total % 60;
    final hs = h == 1 ? '1 hora' : '$h horas';
    if (m == 0) return hs;
    return '$hs y ${m == 1 ? '1 minuto' : '$m minutos'}';
  }

  /// Resumen de temblor de hoy con datos de tremor_summaries. Sin diagnóstico.
  Future<String> _buildTremorTodayReply() async {
    if (!await _hasInternet()) return _noDataConnection;
    try {
      final s = await _firebaseService.getTodayTremorSummary();
      if (s == null || s.totalSamples == 0) {
        return 'Hoy todavía no tengo datos de temblor registrados. Usa el reloj un rato '
            'y vuelve a preguntarme. Te abro la sección de temblor.';
      }
      final monitored = _fmtMinutes(s.monitoredMinutes);
      final tremor = s.tremorMinutes;
      if (tremor < 0.5) {
        return 'Hoy el reloj te ha monitoreado $monitored y no detectó temblor '
            'parkinsoniano. Te abro la sección de temblor.';
      }
      final pct = (tremor / s.monitoredMinutes * 100).round();
      final parts = <String>[
        if (s.count('LEVE') > 0) '${_fmtMinutes(s.minutesOf('LEVE'))} leve',
        if (s.count('MODERADO') > 0) '${_fmtMinutes(s.minutesOf('MODERADO'))} moderado',
        if (s.count('GRAVE') > 0) '${_fmtMinutes(s.minutesOf('GRAVE'))} grave',
      ];
      final detail = parts.length > 1
          ? '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}'
          : parts.first;
      final buffer = StringBuffer(
        'Hoy el reloj te ha monitoreado $monitored. Tuviste temblor durante '
        '${_fmtMinutes(tremor)}, cerca del $pct por ciento del tiempo: $detail.',
      );
      if (s.count('GRAVE') > 0) {
        buffer.write(' Hubo momentos de temblor grave; te sugiero comentarlo con tu médico.');
      }
      buffer.write(' Te abro la sección de temblor para que veas el detalle.');
      return buffer.toString();
    } catch (e) {
      debugPrint('[Emki] No se pudo consultar el temblor de hoy: $e');
      return _noDataConnection;
    }
  }

  /// Tomas de medicamento de hoy (medication_tasks), tomadas y pendientes.
  Future<String> _buildMedicationsTodayReply() async {
    if (!await _hasInternet()) return _noDataConnection;
    try {
      final registered = await _firebaseService.getTodayMedications();
      // Tomas de hoy de los recordatorios que aún no se han marcado (los
      // recordatorios no crean tomas hasta que se toca "Ya la tomé").
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final takenIds = registered.map((t) => t.id).toSet();
      final reminderDoses = <MedicationTask>[];
      try {
        final reminders = await _firebaseService.getReminders().timeout(const Duration(seconds: 6));
        for (final r in reminders) {
          for (final dose in r.dosesBetween(today, 1)) {
            final id = r.doseTaskId(dose);
            if (takenIds.contains(id)) continue;
            reminderDoses.add(MedicationTask(
              id: id,
              name: r.dose != null ? '${r.name} (${r.dose})' : r.name,
              scheduledDateTime: dose,
              userId: '',
              reminderId: r.id,
            ));
          }
        }
      } catch (e) {
        debugPrint('[Emki] No pude leer los recordatorios de hoy: $e');
      }
      final tasks = [...registered, ...reminderDoses]
        ..sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
      if (tasks.isEmpty) {
        return 'No tienes medicamentos programados para hoy. Te abro la sección de medicamentos.';
      }
      String timeOf(DateTime d) => _formatTimeDisplay(TimeOfDay(hour: d.hour, minute: d.minute));
      final pending = tasks.where((t) => !t.isTaken).toList();
      final shown = tasks.take(6).map((t) =>
          '${t.name} a las ${timeOf(t.scheduledDateTime)}${t.isTaken ? ', ya tomada' : ''}');
      final buffer = StringBuffer(
        'Hoy tienes ${tasks.length == 1 ? 'una toma' : '${tasks.length} tomas'}: ${shown.join('; ')}'
        '${tasks.length > 6 ? '; y otras más' : ''}.',
      );
      if (pending.isEmpty) {
        buffer.write(' Ya marcaste todas como tomadas. ¡Muy bien!');
      } else {
        final next = pending.first;
        buffer.write(' Te ${pending.length == 1 ? 'falta una' : 'faltan ${pending.length}'}; '
            'la próxima es ${next.name} a las ${timeOf(next.scheduledDateTime)}.');
      }
      buffer.write(' Te abro la sección de medicamentos.');
      return buffer.toString();
    } catch (e) {
      debugPrint('[Emki] No se pudo consultar los medicamentos de hoy: $e');
      return _noDataConnection;
    }
  }

  // ================= EMERGENCIA Y LLAMADAS =================

  static const List<String> _distressPhrases = [
    'me siento mal', 'me siento muy mal', 'me siento fatal', 'me siento peor',
    'me siento muy debil', 'me cai', 'me he caido', 'me caido', 'me fui al piso',
    'auxilio', 'emergencia', 'no puedo respirar', 'me cuesta respirar',
    'me falta el aire', 'me duele el pecho', 'dolor en el pecho',
    'me voy a desmayar', 'me desmaye', 'estoy mareado', 'estoy mareada',
    'me mareo', 'no me puedo levantar', 'no puedo levantarme',
    'necesito ayuda urgente', 'ayuda urgente',
  ];

  /// ¿La persona dice que se siente mal o está en peligro?
  /// "ayuda" sola solo cuenta en frases cortas ("¡ayuda!"), no en
  /// "ayúdame a registrar mi comida".
  @visibleForTesting
  static bool isDistress(String prompt) {
    final n = normalizeText(prompt);
    if (hasAnyWord(n, _distressPhrases)) return true;
    final shortAsk = n.split(' ').length <= 3;
    return shortAsk && hasAnyWord(n, const ['ayuda', 'ayudame', 'socorro']);
  }

  /// "llama a mi hija" -> "mi hija"; null si no es un pedido de llamada.
  @visibleForTesting
  static String? callTargetPhrase(String prompt) {
    final n = normalizeText(prompt);
    final m = RegExp(r'^(?:oye |emki |por favor )*(?:llama|llamame|llamale|llamar|marca|marcale|marcar|'
            r'comunicame con|contacta|contactar|puedes llamar|quiero llamar|necesito llamar)(?: a| al)? (.+)$')
        .firstMatch(n);
    return m?.group(1)?.trim();
  }

  static const Set<String> _relationWords = {
    'hija', 'hijo', 'esposa', 'esposo', 'mama', 'papa', 'madre', 'padre',
    'hermana', 'hermano', 'nieta', 'nieto', 'sobrina', 'sobrino', 'cuidador',
    'cuidadora', 'enfermera', 'enfermero', 'vecina', 'vecino', 'amiga', 'amigo',
    'novia', 'novio', 'pareja', 'doctor', 'doctora', 'tia', 'tio',
  };

  /// Contacto que coincide con lo pedido ("mi hija", "María", "contacto de
  /// emergencia"). "123", "ambulancia" o "emergencias" -> línea 123.
  @visibleForTesting
  static EmergencyContact? matchContact(String target, List<EmergencyContact> contacts) {
    final t = normalizeText(target);
    if (hasAnyWord(t, const ['123', 'ambulancia', 'emergencias', 'linea de emergencia', 'policia', 'bomberos'])) {
      return const EmergencyContact(name: 'Línea de emergencias', phone: CallService.emergencyNumber);
    }
    if (contacts.isEmpty) return null;
    // 1. Por nombre (palabra completa)
    for (final c in contacts) {
      final first = normalizeText(c.name).split(' ').first;
      if (first.isNotEmpty && hasWord(t, first)) return c;
    }
    // 2. Por parentesco ("mi hija")
    for (final c in contacts) {
      final rel = normalizeText(c.relation);
      if (rel.isNotEmpty && (hasWord(t, rel) || rel.split(' ').any((w) => _relationWords.contains(w) && hasWord(t, w)))) {
        return c;
      }
    }
    // 3. "mi contacto de emergencia" / "alguien" -> el primero
    if (hasAnyWord(t, const ['contacto', 'contacto de emergencia', 'emergencia', 'alguien', 'familia', 'familiar'])) {
      return contacts.first;
    }
    return null;
  }

  Future<List<EmergencyContact>> _loadEmergencyContacts() async {
    try {
      return await _firebaseService.getEmergencyContacts().timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[Emergencia] No pude leer los contactos: $e');
      return const [];
    }
  }

  /// Emergencia o pedido de llamada (resuelto localmente, sin Gemini).
  Future<VoiceAssistantResponse?> _handleEmergencyOrCall(String prompt) async {
    final target = callTargetPhrase(prompt);
    final distress = isDistress(prompt);
    if (target == null && !distress) return null;

    final contacts = await _loadEmergencyContacts();
    if (target != null) {
      final c = matchContact(target, contacts);
      if (c != null) {
        return VoiceAssistantResponse(
          textResponse: 'Te comunico con ${c.label}. Toca el botón verde para llamar.',
          action: AppVoiceAction.callContact,
          phoneToCall: c.phone,
          targetName: c.label,
        );
      }
      // No se reconoció a quién: se muestran todos.
      return VoiceAssistantResponse(
        textResponse: contacts.isEmpty
            ? 'No tienes contactos de emergencia guardados. Puedes agregarlos en tu perfil. '
                'Si es urgente, toca el botón para llamar al 123.'
            : 'No estoy segura de a quién llamar. Toca el nombre de la persona que quieres llamar.',
        action: AppVoiceAction.emergency,
        emergencyContacts: contacts,
      );
    }

    // Se siente mal: empatía + ofrecer llamar (no se llama solo).
    final names = contacts.take(3).map((c) => c.label).toList();
    final text = contacts.isEmpty
        ? 'Lo siento mucho. No tienes contactos de emergencia guardados; puedes agregarlos en tu perfil. '
            'Si es urgente, toca el botón para llamar al 123.'
        : 'Lo siento mucho, aquí estoy. ¿Quieres que llame a alguien? Toca el nombre para llamar a '
            '${names.length > 1 ? '${names.sublist(0, names.length - 1).join(', ')} o ${names.last}' : names.first}, '
            'o al 123 si es urgente.';
    return VoiceAssistantResponse(
      textResponse: text,
      action: AppVoiceAction.emergency,
      emergencyContacts: contacts,
    );
  }

  // ================= PERFIL POR VOZ =================

  /// Etiqueta legible de cada campo del perfil (users/{uid}).
  static const Map<String, String> profileFieldLabels = {
    'name': 'nombre',
    'lastName': 'apellidos',
    'fixedPhone': 'teléfono fijo',
    'cellPhone': 'celular',
    'diagnosisYear': 'año de diagnóstico',
    'experience': 'tu experiencia',
    'specialistName': 'doctor',
    'specialistType': 'especialidad',
    'hospital': 'hospital',
    'consultationTime': 'horario de consulta',
    'supportGroup': 'grupo de apoyo',
  };

  /// Claves que puede usar Gemini en [UPDATE_PROFILE|clave=valor] -> campo.
  static const Map<String, String> _profileTagKeys = {
    'nombre': 'name', 'apellido': 'lastName', 'apellidos': 'lastName',
    'telefono_fijo': 'fixedPhone', 'fijo': 'fixedPhone',
    'celular': 'cellPhone', 'telefono': 'cellPhone', 'telefono_celular': 'cellPhone',
    'anio_diagnostico': 'diagnosisYear', 'ano_diagnostico': 'diagnosisYear', 'diagnostico': 'diagnosisYear',
    'experiencia': 'experience',
    'doctor': 'specialistName', 'medico': 'specialistName', 'especialista': 'specialistName',
    'especialidad': 'specialistType',
    'hospital': 'hospital', 'clinica': 'hospital', 'institucion': 'hospital',
    'horario': 'consultationTime', 'horario_consulta': 'consultationTime', 'consulta': 'consultationTime',
    'grupo': 'supportGroup', 'grupo_apoyo': 'supportGroup',
  };

  /// Especialidad a uno de los valores de la lista del perfil.
  static String normalizeSpecialty(String raw) {
    final n = normalizeText(raw);
    if (n.contains('neuropsicolog')) return 'Neuropsicología';
    if (n.contains('neurolog')) return 'Neurología';
    if (n.contains('interna') || n.contains('internista')) return 'Medicina interna';
    if (n.contains('fisioterap')) return 'Fisioterapia';
    return 'Otro';
  }

  static String _titleCase(String s) => s
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => const {'de', 'del', 'la', 'las', 'los', 'y'}.contains(w.toLowerCase())
          ? w.toLowerCase()
          : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// Valida y normaliza un valor; devuelve null si no sirve.
  static Object? _cleanProfileValue(String field, String raw) {
    final v = raw.trim().replaceAll(RegExp(r'[.;,]+$'), '').trim();
    if (v.isEmpty) return null;
    switch (field) {
      case 'diagnosisYear':
        final year = int.tryParse(RegExp(r'(19|20)\d{2}').firstMatch(v)?.group(0) ?? '');
        if (year == null || year < 1950 || year > DateTime.now().year) return null;
        return year;
      case 'cellPhone':
      case 'fixedPhone':
        final digits = v.replaceAll(RegExp(r'[^\d+]'), '');
        return digits.replaceAll('+', '').length >= 7 ? digits : null;
      case 'specialistType':
        return normalizeSpecialty(v);
      case 'name':
      case 'lastName':
      case 'specialistName':
      case 'hospital':
      case 'supportGroup':
        return _titleCase(v);
      default:
        return v[0].toUpperCase() + v.substring(1);
    }
  }

  /// Cuerpo de [UPDATE_PROFILE|doctor=Juan Pérez|hospital=San Ignacio].
  @visibleForTesting
  static Map<String, Object> parseProfileTag(String body) {
    final result = <String, Object>{};
    for (final part in body.split('|')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final key = normalizeText(part.substring(0, i)).replaceAll(' ', '_');
      final field = _profileTagKeys[key];
      if (field == null) continue;
      final value = _cleanProfileValue(field, part.substring(i + 1));
      if (value != null) result[field] = value;
    }
    // "mi neurólogo es ..." -> especialidad Neurología si no vino.
    return result;
  }

  /// Respaldo local (sin Gemini) para frases comunes del perfil.
  @visibleForTesting
  static Map<String, Object> extractProfileUpdates(String prompt) {
    final text = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lower = text.toLowerCase();
    final result = <String, Object>{};
    void put(String field, String? raw) {
      if (raw == null) return;
      final v = _cleanProfileValue(field, raw);
      if (v != null) result[field] = v;
    }

    // Texto ORIGINAL (con mayúsculas y tildes) del grupo [g] de [m] en [lower].
    String orig(RegExpMatch m, int g) {
      final s = lower.indexOf(m.group(g)!, m.start);
      return text.substring(s, s + m.group(g)!.length);
    }

    const stop = r'(?=\s+(?:y|en|del|de la|que|me|por|a las|los|las|el|la|con|para)\b|[.,;]|$)';
    const word = r"[a-záéíóúüñ][a-záéíóúüñ'\.]*";

    // Doctor: "mi doctor se llama Juan Pérez", "mi neuróloga es la doctora Ana Ruiz"
    final doc = RegExp(
      '(?:mi |el |la )?(doctor|doctora|m[eé]dico|m[eé]dica|neur[oó]log[oa]|especialista)'
      '(?: tratante)?(?: se llama| es| es el| es la)? (?:el |la )?(?:doctor |doctora |dr\\.? |dra\\.? )?'
      '($word(?: $word){0,3}?)$stop',
    ).firstMatch(lower);
    if (doc != null && RegExp(r'\b(se llama|es)\b').hasMatch(lower)) {
      put('specialistName', orig(doc, 2));
      if (doc.group(1)!.contains('neur')) result['specialistType'] = 'Neurología';
    }

    // Especialidad dicha aparte: "mi especialista es neurólogo"
    final spec = RegExp(r'(?:especialidad|especialista) (?:es )?(?:en )?(neurolog\w*|neuropsicolog\w*|fisioterap\w*|medicina interna|internista)')
        .firstMatch(lower);
    if (spec != null) result['specialistType'] = normalizeSpecialty(spec.group(1)!);

    // Hospital: "me atienden en el hospital San Ignacio", "mi clínica es la Fundación Santa Fe"
    final hosp = RegExp('(hospital|cl[ií]nica|fundaci[oó]n|centro m[eé]dico) ($word(?: $word){0,4}?)$stop')
        .firstMatch(lower);
    if (hosp != null && RegExp(r'(atiend|consulta|voy|mi (hospital|cl[ií]nica)|es (el|la))').hasMatch(lower)) {
      put('hospital', '${orig(hosp, 1)} ${orig(hosp, 2)}');
    }

    // Teléfonos
    final fixed = RegExp(r'(?:tel[eé]fono fijo|fijo)(?: es)?:? ([\d\s\-+]{7,})').firstMatch(lower);
    if (fixed != null) put('fixedPhone', fixed.group(1));
    final cell = RegExp(r'(?:celular|mi n[uú]mero|tel[eé]fono celular|mi tel[eé]fono)(?: es)?:? ([\d\s\-+]{7,})').firstMatch(lower);
    if (cell != null) put('cellPhone', cell.group(1));

    // Año de diagnóstico: "me diagnosticaron en 2019"
    final diag = RegExp(r'diagn[oó]stic\w*[^0-9]{0,30}((?:19|20)\d{2})').firstMatch(lower);
    if (diag != null) put('diagnosisYear', diag.group(1));

    // Horario de consulta: "mi consulta es los martes a las 3 de la tarde"
    final cons = RegExp(r'(?:mi |la )?(?:consulta|cita)(?: m[eé]dica)? (?:es|son|la tengo|queda)? ?((?:los|el|cada|todos) .{3,60})$')
        .firstMatch(lower);
    if (cons != null) {
      put('consultationTime', orig(cons, 1));
    }

    // Nombre: "me llamo Ana María Gómez"
    final me = RegExp('me llamo ($word(?: $word){0,4})').firstMatch(lower);
    if (me != null) {
      final parts = orig(me, 1).split(' ');
      put('name', parts.first);
      if (parts.length > 1) put('lastName', parts.sublist(1).join(' '));
    }
    return result;
  }

  /// "Listo, actualicé tu perfil: doctor, Juan Pérez; hospital, Hospital San Ignacio."
  static String profileUpdateReply(Map<String, Object> updates) {
    final parts = updates.entries
        .map((e) => '${profileFieldLabels[e.key] ?? e.key}: ${e.value}')
        .join('; ');
    return 'Listo, actualicé tu perfil con $parts. Te abro tu perfil para que lo revises.';
  }

  String? _profileMissingCache;

  /// "hospital, horario de consulta" (campos vacíos del perfil) para que
  /// Gemini sepa qué preguntar al "completar el perfil". Se cachea.
  Future<String> _profileMissingSummary() async {
    if (_profileMissingCache != null) return _profileMissingCache!;
    try {
      final p = await _firebaseService.getUserProfile().timeout(const Duration(seconds: 3));
      if (p == null) return 'desconocido';
      final missing = <String>[
        if (p.name.isEmpty) 'nombre',
        if (p.lastName.isEmpty) 'apellidos',
        if (p.cellPhone.isEmpty) 'celular',
        if (p.fixedPhone.isEmpty) 'teléfono fijo',
        if (p.diagnosisYear == null) 'año de diagnóstico',
        if (p.experience.isEmpty) 'experiencia',
        if (p.specialistName.isEmpty) 'doctor',
        if (p.hospital.isEmpty) 'hospital',
        if (p.consultationTime.isEmpty) 'horario de consulta',
        if (p.supportGroup.isEmpty) 'grupo de apoyo',
      ];
      _profileMissingCache = missing.isEmpty ? 'ninguno (perfil completo)' : missing.join(', ');
      return _profileMissingCache!;
    } catch (_) {
      return 'desconocido';
    }
  }

  // ================= NORMALIZACIÓN Y PALABRAS COMPLETAS =================

  /// Minúsculas, sin tildes (excepto ñ), sin puntuación y con espacios simples.
  /// No usa `\b` de Dart, que trata la ñ como separador de palabra.
  static String normalizeText(String input) {
    const from = 'áàäâéèëêíìïîóòöôúùüû';
    const to = 'aaaaeeeeiiiioooouuuu';
    final buffer = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      if (i >= 0) {
        buffer.write(to[i]);
      } else if (RegExp(r'[a-z0-9ñ]').hasMatch(ch)) {
        buffer.write(ch);
      } else {
        buffer.write(' ');
      }
    }
    return buffer.toString().replaceAll(RegExp(r' +'), ' ').trim();
  }

  /// true si [phrase] (una o varias palabras) aparece como palabras completas
  /// dentro de [norm] (texto ya normalizado). 'ana' NO coincide en 'mañana'.
  static bool hasWord(String norm, String phrase) {
    final p = normalizeText(phrase);
    if (p.isEmpty) return false;
    return ' $norm '.contains(' $p ');
  }

  static bool hasAnyWord(String norm, Iterable<String> phrases) =>
      phrases.any((p) => hasWord(norm, p));

  /// Acceso para pruebas unitarias (sin Firebase): detección local del respaldo.
  @visibleForTesting
  static AppVoiceAction detectActionForTest(String prompt) => _detectActionFromPrompt(prompt);

  @visibleForTesting
  static String? extractCompanionNameForTest(String prompt) => _extractCompanionName(prompt);

  static const List<String> _homeWords = [
    'inicio', 'menu principal', 'pantalla principal', 'regresa', 'regresar',
    'vuelve', 'volver', 'atras',
  ];
  static const List<String> _medicationWords = [
    'medicamento', 'medicamentos', 'medicina', 'medicinas', 'pastilla',
    'pastillas', 'remedio', 'remedios', 'dosis', 'farmaco', 'farmacos',
    'tome', 'me tome', 'ya tome', 'levodopa',
  ];
  static const List<String> _foodWords = [
    'comida', 'comidas', 'alimento', 'alimentos', 'alimentacion', 'dieta',
    'comi', 'me comi', 'desayune', 'desayuno', 'almorce', 'almuerzo', 'cene',
    'cena', 'merende', 'merienda', 'onces',
  ];
  static const List<String> _activityWords = [
    'actividad', 'actividad fisica', 'ejercicio', 'ejercicios', 'caminata',
    'estiramiento', 'estiramientos', 'hice ejercicio', 'camine', 'trote',
    'nade', 'yoga', 'bicicleta',
  ];
  /// Verbos/expresiones de registro: se evalúan ANTES que los nombres de compañeros.
  static const List<String> _registrationIntentWords = [
    'tome', 'me tome', 'comi', 'me comi', 'desayune', 'almorce', 'cene',
    'merende', 'camine', 'trote', 'nade', 'hice ejercicio', 'registrar',
    'registra', 'registrame', 'registre', 'anota', 'anotar', 'apunta',
  ];
  /// Un compañero solo se abre si además aparece una de estas palabras.
  static const List<String> _companionContextWords = [
    'perfil', 'companero', 'companera', 'compañero', 'compañera', 'abre',
    'abrir', 'abreme', 'ver a', 'muestrame a', 'conoce a',
  ];
  static const List<String> _privatePhrases = [
    'perfil privado', 'perfil privada', 'haz privado', 'hazlo privado',
    'activa privacidad', 'activar privacidad', 'activa la privacidad',
  ];
  static const List<String> _publicPhrases = [
    'perfil publico', 'perfil publica', 'haz publico', 'hazlo publico',
    'activa publico', 'activar publico',
  ];

  static AppVoiceAction _detectActionFromPrompt(String prompt) {
    final norm = normalizeText(prompt);

    // --- Consultas del día (antes que navegación: "¿cómo va mi temblor hoy?"
    // no debe solo abrir la sección) ---
    final query = detectDayQuery(prompt);
    if (query != AppVoiceAction.none) return query;

    // --- Recordatorios (antes que el registro: "recordatorio para tomar la
    // amoxicilina" no es una toma ya hecha) ---
    if (isReminderRequest(prompt)) return AppVoiceAction.openReminders;

    // --- Privacy toggle ---
    if (hasAnyWord(norm, _privatePhrases)) return AppVoiceAction.togglePrivacyPrivate;
    if (hasAnyWord(norm, _publicPhrases)) return AppVoiceAction.togglePrivacyPublic;

    // --- Intención de registro (antes que compañeros: "caminé... en la mañana") ---
    if (hasAnyWord(norm, _registrationIntentWords)) {
      if (hasAnyWord(norm, const ['tome', 'me tome', 'ya tome', 'medicamento', 'medicina', 'pastilla', 'remedio', 'levodopa'])) {
        return AppVoiceAction.openMedication;
      }
      if (hasAnyWord(norm, const ['camine', 'trote', 'nade', 'hice ejercicio', 'ejercicio', 'actividad', 'caminata', 'estiramientos', 'estiramiento'])) {
        return AppVoiceAction.openHabitsActivity;
      }
      if (hasAnyWord(norm, _foodWords)) return AppVoiceAction.openHabitsFood;
    }

    // --- Compañero específico (exige palabra de contexto) ---
    if (_extractCompanionName(prompt) != null) {
      return AppVoiceAction.openCompanionProfile;
    }

    // --- Grupo / lección específicos ---
    if (_matchKnownName(norm, knownGroupNames) != null) return AppVoiceAction.openCommunityGroup;
    if (_matchKnownName(norm, knownLessonTitles) != null) return AppVoiceAction.openCommunityLesson;

    if (hasAnyWord(norm, _medicationWords)) return AppVoiceAction.openMedication;
    if (hasAnyWord(norm, const ['temblor', 'temblores', 'grafica', 'monitoreo', 'sensor', 'medir', 'reloj'])) {
      return AppVoiceAction.openTremor;
    }
    if (hasAnyWord(norm, _activityWords)) return AppVoiceAction.openHabitsActivity;
    if (hasAnyWord(norm, const ['habito', 'habitos', ..._foodWords])) {
      return AppVoiceAction.openHabitsFood;
    }

    // --- Community subsections ---
    if (hasAnyWord(norm, const ['leccion', 'lecciones'])) return AppVoiceAction.openCommunityLessons;
    if (hasAnyWord(norm, const ['grupo', 'grupos'])) return AppVoiceAction.openCommunityGroups;
    if (hasAnyWord(norm, const ['compañero', 'compañeros', 'compañera', 'compañeras', 'companero', 'companeros'])) {
      return AppVoiceAction.openCommunityCompanions;
    }
    if (hasWord(norm, 'comunidad')) return AppVoiceAction.openCommunity;

    if (hasAnyWord(norm, const ['perfil', 'medico', 'especialista', 'mi cuenta'])) {
      return AppVoiceAction.openProfile;
    }

    // --- Volver al inicio (al final: "regresa a medicamentos" abre medicamentos,
    // "me vuelve el temblor" abre temblor) ---
    if (hasAnyWord(norm, _homeWords)) return AppVoiceAction.openHome;

    return AppVoiceAction.none;
  }

  /// Nombre de compañero SOLO si hay palabra de contexto (perfil, compañero/a,
  /// abre, ver a) y no es una frase de registro. Comparación por palabras completas.
  static String? _extractCompanionName(String prompt) {
    final norm = normalizeText(prompt);
    if (hasAnyWord(norm, _registrationIntentWords)) return null;
    if (!hasAnyWord(norm, _companionContextWords)) return null;

    for (final name in knownCompanionFirstNames) {
      if (hasWord(norm, name)) {
        return name[0].toUpperCase() + name.substring(1);
      }
    }

    // Nombre no listado: la palabra que sigue a "perfil de" / "ver a".
    final match = RegExp(r'(?:perfil de|ver a) (?:mi |la |el |a )?(?:compañera |compañero |companera |companero )?([a-zñ]+)')
        .firstMatch(norm);
    if (match != null) {
      final candidate = match.group(1)!;
      const stop = {'mi', 'tu', 'su', 'el', 'la', 'un', 'una', 'ellos', 'ella'};
      if (candidate.length > 2 && !stop.contains(candidate)) {
        return candidate[0].toUpperCase() + candidate.substring(1);
      }
    }
    return null;
  }

  /// Returns the canonical known name found in [norm] (texto normalizado), or null.
  static String? _matchKnownName(String norm, List<String> knownNames) {
    for (final name in knownNames) {
      if (hasWord(norm, name)) return name;
    }
    return null;
  }

  /// Extracts the community target name from the user prompt based on
  /// the detected action.  Returns the cleaned name or null.
  static String? _extractCommunityTargetName(String prompt, AppVoiceAction action) {
    final norm = normalizeText(prompt);
    if (action == AppVoiceAction.openCompanionProfile ||
        action == AppVoiceAction.openCommunityCompanions) {
      return _extractCompanionName(prompt);
    }
    if (action == AppVoiceAction.openCommunityGroup ||
        action == AppVoiceAction.openCommunityGroups) {
      final matched = _matchKnownName(norm, knownGroupNames);
      if (matched != null) return _cleanEntityName(matched);
    }
    if (action == AppVoiceAction.openCommunityLesson ||
        action == AppVoiceAction.openCommunityLessons) {
      final matched = _matchKnownName(norm, knownLessonTitles);
      if (matched != null) return _cleanEntityName(matched);
    }
    return null;
  }


  String _getFallbackResponse(String prompt, AppVoiceAction action, [String? targetName]) {
    switch (action) {
      case AppVoiceAction.openHome:
        return 'Listo, te llevo al inicio.';
      case AppVoiceAction.queryTremorToday:
      case AppVoiceAction.queryMedicationToday:
        return ''; // la respuesta se arma con datos reales en processPrompt
      case AppVoiceAction.emergency:
        return 'Lo siento mucho. Toca el nombre de la persona que quieres llamar, o el 123 si es urgente.';
      case AppVoiceAction.callContact:
        return 'Te comunico. Toca el botón verde para llamar.';
      case AppVoiceAction.openReminders:
        return targetName != null
            ? 'Te abro los recordatorios para que elijas las horas de $targetName.'
            : 'Te abro los recordatorios para que programes las horas de tus medicamentos.';
      case AppVoiceAction.openMedication:
        return 'Con gusto, abriendo la sección de medicamentos.';
      case AppVoiceAction.openTremor:
        return 'Claro, abriendo la gráfica de monitoreo de temblor.';
      case AppVoiceAction.openHabits:
      case AppVoiceAction.openHabitsFood:
        return 'Entendido, te llevo a la sección de hábitos de alimentación.';
      case AppVoiceAction.openHabitsActivity:
        return 'Entendido, te llevo a la sección de actividad física.';
      case AppVoiceAction.openCommunity:
        return 'Por supuesto, abriendo la sección de comunidad.';
      case AppVoiceAction.openCommunityCompanions:
        return 'Claro, abriendo la pestaña de compañeros en Comunidad Parkinson.';
      case AppVoiceAction.openCommunityGroups:
        return 'Entendido, abriendo la pestaña de grupos en Comunidad Parkinson.';
      case AppVoiceAction.openCommunityLessons:
        return 'Por supuesto, abriendo la pestaña de lecciones en Comunidad Parkinson.';
      case AppVoiceAction.openCompanionProfile:
        return 'Abriendo el perfil de ${targetName ?? 'tu compañero'}.';
      case AppVoiceAction.openCommunityGroup:
        return 'Abriendo el grupo ${targetName ?? 'de la comunidad'}.';
      case AppVoiceAction.openCommunityLesson:
        return 'Abriendo la lección: ${targetName ?? 'de la comunidad'}.';
      case AppVoiceAction.togglePrivacyPrivate:
        return 'Tu perfil ahora es privado.';
      case AppVoiceAction.togglePrivacyPublic:
        return 'Tu perfil ahora es público.';
      case AppVoiceAction.openProfile:
        return 'Abriendo tu perfil personal.';
      case AppVoiceAction.none:
        return 'Entendido tu mensaje. ¿Deseas consultar o registrar medicamentos, comidas o ejercicios?';
    }
  }

  /// Detiene micrófono y voz. NO destruye la instancia compartida.
  Future<void> dispose() async {
    await _speech.stop();
    await _tts.stop();
  }

  /// Reglas fijas del asistente (systemInstruction). Los datos de cada turno
  /// (hora, contexto pendiente y mensaje) se envían en el mensaje del chat.
  static const String _systemInstruction = '''
Eres Emki, el asistente inteligente de voz, cálido y empático de la app Emkiwear Care para personas con enfermedad de Parkinson.
Tu objetivo es comprender los mensajes del paciente (incluso si se expresan con variaciones coloquiales, dudas, frases incompletas, expresiones imprecisas o pequeñas faltas al hablar) y guiarlo a registrar datos de salud o navegar en la app.
Responde siempre en español, en 1 a 3 frases cortas, porque tu respuesta se lee en voz alta.

En cada mensaje recibirás:
- HORA DE REFERENCIA DEL DISPOSITIVO (HH:MM, 24 h): úsala para "ahorita", "recién", "acabo de" y para calcular tiempos relativos.
- ESTADO CONVERSACIONAL PREVIO ACTIVO: lo que ya se sabe del registro en curso.
- Mensaje del usuario.
Recuerdas los turnos anteriores de esta conversación: si ya preguntaste algo, interpreta la respuesta del usuario como respuesta a tu pregunta.

REGLAS Y DINÁMICAS DE INTERACCIÓN FLEXIBLE:

1. REGISTRO DIRECTO O EN 1 SOLO TURNO (Cuando el paciente da el elemento Y la hora o momento):
   Si el mensaje contiene el elemento (comida, medicamento o ejercicio) Y una referencia de tiempo (ej: "a las 8 am", "ahorita", "recién", "hace un rato", "al medio día"):
   Genera INMEDIATAMENTE las etiquetas de registro y navegación en tu respuesta. En time usa SIEMPRE HH:MM en formato 24 h.
   Ejemplos (con HORA DE REFERENCIA 13:10):
   - "Me tomé la levodopa a las 8 de la mañana" -> "Registré la toma de tu Levodopa a las 8:00 a. m. [REGISTER_MEDICATION|name=Levodopa|time=08:00] [ACTION:OPEN_MEDICATION]"
   - "Ya almorcé seco de pollo recién" -> "Registré tu almuerzo: seco de pollo. [REGISTER_FOOD|food=Seco de pollo|mealType=Almuerzo|time=13:10] [ACTION:OPEN_HABITS_FOOD]"
   - "Acabo de caminar 20 minutos" -> "Registré tu caminata de 20 minutos. [REGISTER_ACTIVITY|activityType=Caminata|duration=20|intensity=Media|time=13:10] [ACTION:OPEN_HABITS_ACTIVITY]"
   - "Desayuné huevos con arepa hace media hora" -> "Registré tu desayuno: huevos con arepa. [REGISTER_FOOD|food=Huevos con arepa|mealType=Desayuno|time=12:40] [ACTION:OPEN_HABITS_FOOD]"
   - "Poner que me tomé la levodopa hace dos horas" -> "Registré la toma de tu Levodopa a las 11:10 a. m. [REGISTER_MEDICATION|name=Levodopa|time=11:10] [ACTION:OPEN_MEDICATION]"
   - "Cené sopa hace un rato" (un rato = 20 minutos) -> "Registré tu cena: sopa. [REGISTER_FOOD|food=Sopa|mealType=Cena|time=12:50] [ACTION:OPEN_HABITS_FOOD]"
   - "Troté una hora y media a intensidad alta a las 7 de la mañana" -> "Registré tu trote de 90 minutos. [REGISTER_ACTIVITY|activityType=Trote|duration=90|intensity=Alta|time=07:00] [ACTION:OPEN_HABITS_ACTIVITY]"
   Tiempos relativos: "hace N minutos/horas" = hora de referencia menos ese tiempo; "hace media hora" = 30 min; "hace un rato" = 20 min.
   Nombres: en name/food/activityType pon SOLO el nombre del elemento ("Levodopa", "Huevos con arepa", "Caminata").
   NUNCA copies la frase del usuario ni incluyas verbos o relleno ("me tomé", "poner que", "quiero registrar", "a las 8").
   Tipo de comida: desayuné -> Desayuno, almorcé -> Almuerzo, cené -> Cena, merendé/onces -> Merienda; si no lo dice, dedúcelo por la hora.
   Duración en minutos: "media hora" = 30, "una hora" = 60, "hora y media" = 90. Intensidad: Leve, Media o Alta (Media si no la dice).

2. REGISTRO GUIADO EN PASOS (Cuando falta información):
   - Si el paciente menciona el elemento pero FALTA LA HORA (ej: "Me tomé la levodopa", "Comí una fruta", "Hice mis estiramientos"):
     Responde de forma cálida preguntando la hora del evento y abre la sección correspondiente. NUNCA incluyas etiquetas de registro `[REGISTER_...]` cuando falta la hora.
     Ejemplo: "Entendido, ¿a qué hora te tomaste la Levodopa? [ACTION:OPEN_MEDICATION]"
   - "en la mañana", "en la tarde", "en la noche" o "hoy" SIN una hora NO son una hora: pregunta la hora exacta.
     Una duración ("30 minutos", "una hora") NUNCA es la hora del evento.
     Ejemplo: "Caminé 30 minutos en la mañana" -> "¡Muy bien! ¿A qué hora hiciste tu caminata de 30 minutos? [ACTION:OPEN_HABITS_ACTIVITY]"
   - Si el ESTADO CONVERSACIONAL trae nombreElemento (y duración o tipo de comida) y solo falta la hora,
     cuando el usuario diga la hora registra con esos datos.
   - Si el paciente indica una intención general sin nombrar el elemento (ej: "Quiero registrar un medicamento", "Voy a registrar mi comida"):
     Responde preguntando qué elemento tomó o comió. NUNCA incluyas etiquetas `[REGISTER_...]` en este paso.
   - Cuando el paciente responda tu pregunta en el turno siguiente, completa el registro con lo que dijo antes y lo que dice ahora.

3. RESPUESTAS EMPÁTICAS Y SÍNTOMAS DEL PACIENTE:
   - Si el paciente expresa sensaciones de salud, síntomas o estados de ánimo (ej: "Siento mucho temblor hoy", "Estoy un poco cansado", "Me duele la cabeza", "No me siento muy bien"):
     Responde con empatía y apoyo en 1 o 2 frases breves, sin dar diagnósticos. Si corresponde, incluye la etiqueta de navegación útil (ej: `[ACTION:OPEN_TREMOR]`).
     Ejemplo: "Lamento que te sientas así. Recuerda tomar tus descansos. Puedes monitorear tu temblor aquí. [ACTION:OPEN_TREMOR]"
   - Si el paciente te saluda o pregunta qué puedes hacer:
     Salúdalo amablemente y dale opciones breves (ej: "Hola, puedo ayudarte a registrar tus medicamentos, comidas, ejercicios o revisar tu temblor"). No incluyas etiquetas.

4. CONSULTAS DEL DÍA (los datos los pone la app, no tú):
   - Si pregunta cómo ha estado su temblor hoy ("¿cómo va mi temblor?", "resumen de mi temblor de hoy"):
     responde SOLO "Déjame revisar tus datos de hoy. [ACTION:QUERY_TREMOR_TODAY]". No inventes cifras ni des diagnósticos.
   - Si pregunta qué medicamentos tiene hoy o cuáles le faltan ("¿qué pastillas me tocan hoy?"):
     responde SOLO "Déjame revisar tus medicamentos de hoy. [ACTION:QUERY_MEDS_TODAY]".

3b. EMERGENCIA (lo más importante):
   - Si el paciente expresa un malestar fuerte o peligro (se cayó, se siente muy mal, dolor en el pecho, no puede
     respirar, se va a desmayar, pide auxilio): responde con empatía en UNA frase breve y agrega `[ACTION:EMERGENCY]`.
     La app le mostrará botones para llamar a sus contactos de emergencia o al 123. No des diagnósticos.

4a. RECORDATORIOS DE MEDICAMENTOS (avisos FUTUROS, no una toma ya hecha):
   - Si pide un recordatorio, alarma o aviso para tomar un medicamento ("recuérdame tomar la levodopa",
     "quiero poner un recordatorio de la amoxicilina"): NO uses [REGISTER_MEDICATION].
     Responde "Te abro los recordatorios para que elijas las horas de NOMBRE. [ACTION:OPEN_REMINDERS|name=NOMBRE]".
     Si no dice el medicamento: "Te abro los recordatorios. [ACTION:OPEN_REMINDERS]".

4c. PERFIL DEL PACIENTE (datos para su ficha; la app los guarda):
   - Si el paciente da datos de sí mismo o de su atención médica (su doctor o especialista, la especialidad,
     el hospital o clínica, el horario de su consulta, su celular o teléfono fijo, el año en que lo diagnosticaron,
     su experiencia con la enfermedad, su grupo de apoyo, su nombre o apellidos), responde confirmando y agrega
     UNA etiqueta con SOLO los datos que dijo, exactamente como los dijo (no inventes ni completes):
     `[UPDATE_PROFILE|doctor=NOMBRE|especialidad=ESPECIALIDAD|hospital=NOMBRE|horario=TEXTO|celular=NÚMERO|fijo=NÚMERO|anio_diagnostico=AAAA|experiencia=TEXTO|grupo=NOMBRE|nombre=NOMBRE|apellidos=APELLIDOS]`
     Ejemplo: "Mi doctor es el neurólogo Juan Pérez del Hospital San Ignacio" ->
     "Listo, guardé a tu doctor. [UPDATE_PROFILE|doctor=Juan Pérez|especialidad=Neurología|hospital=Hospital San Ignacio]"
   - Si pide completar o actualizar su perfil sin dar datos, mira CAMPOS VACÍOS DEL PERFIL y pregunta por UNO
     de ellos (ej.: "¿Cómo se llama tu doctor?"). Cuando responda, guárdalo con la etiqueta y pregunta el siguiente.
   - Nunca uses [UPDATE_PROFILE] para datos de otra persona que no sean su propio médico o atención.

4b. VOLVER AL INICIO:
   - Si el paciente pide volver, regresar, ir atrás, al inicio, al menú principal o a la pantalla principal:
     responde algo breve como "Listo, te llevo al inicio." con `[ACTION:OPEN_HOME]`.

5. ETIQUETAS DE ACCIÓN Y REGISTRO OBLIGATORIAS:
   - Inicio / menú principal: `[ACTION:OPEN_HOME]`
   - Consultar temblor de hoy: `[ACTION:QUERY_TREMOR_TODAY]`
   - Consultar medicamentos de hoy: `[ACTION:QUERY_MEDS_TODAY]`
   - Crear recordatorio de medicamento: `[ACTION:OPEN_REMINDERS|name=NOMBRE]` o `[ACTION:OPEN_REMINDERS]`
   - Medicamentos: `[REGISTER_MEDICATION|name=NOMBRE|time=HH:MM]` y `[ACTION:OPEN_MEDICATION]`
   - Alimentación: `[REGISTER_FOOD|food=NOMBRE|mealType=Desayuno/Almuerzo/Cena/Merienda|time=HH:MM]` y `[ACTION:OPEN_HABITS_FOOD]`
   - Actividad Física: `[REGISTER_ACTIVITY|activityType=NOMBRE|duration=MINUTOS|intensity=Leve/Media/Alta|time=HH:MM]` y `[ACTION:OPEN_HABITS_ACTIVITY]`
   - Monitoreo Temblor: `[ACTION:OPEN_TREMOR]`
   - Comunidad → abrir sección general: `[ACTION:OPEN_COMMUNITY]`
   - Comunidad → pestaña Compañeros: `[ACTION:OPEN_COMMUNITY_COMPANIONS]`
   - Comunidad → pestaña Grupos: `[ACTION:OPEN_COMMUNITY_GROUPS]`
   - Comunidad → pestaña Lecciones: `[ACTION:OPEN_COMMUNITY_LESSONS]`
   - Abrir perfil de un compañero específico (usa el nombre): `[ACTION:OPEN_COMPANION|name=NOMBRE]`
   - Abrir un grupo específico (usa el nombre del grupo): `[ACTION:OPEN_GROUP|name=NOMBRE_GRUPO]`
   - Abrir una lección específica (usa el título de la lección): `[ACTION:OPEN_LESSON|name=TÍTULO_LECCIÓN]`
   - Perfil privado: `[ACTION:PRIVACY_PRIVATE]` (haz de tu perfil privado)
   - Perfil público: `[ACTION:PRIVACY_PUBLIC]` (haz de tu perfil público)
   - Perfil: `[ACTION:OPEN_PROFILE]`
   Usa SOLO estas etiquetas, escritas exactamente así, y como máximo una etiqueta [ACTION:...] por respuesta.
''';
}

class _SpeechLifecycleObserver extends WidgetsBindingObserver {
  _SpeechLifecycleObserver(this.onBackground);
  final VoidCallback onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      onBackground();
    }
  }
}

class _RegistrationResult {
  final bool executed;
  /// Hubo etiqueta de registro pero se rechazó (sin hora concreta): cleanReply es la pregunta.
  final bool rejected;
  final String cleanReply;
  const _RegistrationResult({
    required this.executed,
    required this.cleanReply,
    this.rejected = false,
  });
}
