import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Estado del reconocimiento de voz en el dispositivo (sin internet).
class OfflineSpeechStatus {
  final bool supported;
  final String? reason;
  final List<String> installed;
  final List<String> pending;
  final List<String> available;

  const OfflineSpeechStatus({
    required this.supported,
    this.reason,
    this.installed = const [],
    this.pending = const [],
    this.available = const [],
  });

  /// Idiomas de español ya instalados, con formato de speech_to_text (es_US).
  List<String> get installedSpanishLocaleIds => installed
      .where((l) => l.toLowerCase().startsWith('es'))
      .map((l) => l.replaceAll('-', '_'))
      .toList();

  bool get hasSpanishInstalled => installedSpanishLocaleIds.isNotEmpty;

  bool get spanishDownloading =>
      pending.any((l) => l.toLowerCase().startsWith('es'));

  @override
  String toString() =>
      'OfflineSpeechStatus(supported: $supported, reason: $reason, '
      'installed: $installed, pending: $pending, available(es): '
      '${available.where((l) => l.toLowerCase().startsWith('es')).toList()})';
}

/// Consulta y descarga del modelo de voz en el dispositivo (canal nativo en
/// MainActivity.kt). Solo Android 13+; en otras plataformas no hace nada.
class OfflineSpeechService {
  static const MethodChannel _channel = MethodChannel('emkiwear/offline_speech');

  /// Orden de preferencia del idioma a descargar.
  static const List<String> _preferred = ['es-US', 'es-ES', 'es-MX', 'es-CO'];

  /// Último estado consultado (se reutiliza para no crear reconocedores
  /// mientras el micrófono arranca, lo que corta la sesión de escucha).
  static OfflineSpeechStatus? lastStatus;
  static Future<OfflineSpeechStatus>? _inFlight;

  /// Estado en caché si existe; si no, lo consulta.
  static Future<OfflineSpeechStatus> cachedStatus() async =>
      lastStatus ?? await status();

  /// Consulta el estado. Si ya hay una consulta en curso, reutiliza esa.
  static Future<OfflineSpeechStatus> status({String language = 'es-US'}) {
    return _inFlight ??= _queryStatus(language).whenComplete(() => _inFlight = null);
  }

  static Future<OfflineSpeechStatus> _queryStatus(String language) async {
    if (!Platform.isAndroid) {
      return const OfflineSpeechStatus(supported: false, reason: 'solo Android');
    }
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('status', {'language': language})
          .timeout(const Duration(seconds: 5));
      if (raw == null) return const OfflineSpeechStatus(supported: false, reason: 'sin respuesta');
      List<String> list(String k) => (raw[k] as List?)?.cast<String>() ?? const [];
      final s = OfflineSpeechStatus(
        supported: raw['supported'] == true,
        reason: raw['reason'] as String?,
        installed: list('installed'),
        pending: list('pending'),
        available: list('available'),
      );
      debugPrint('[Emki] Voz sin conexión: $s');
      lastStatus = s;
      return s;
    } catch (e) {
      debugPrint('[Emki] No se pudo consultar la voz sin conexión: $e');
      return OfflineSpeechStatus(supported: false, reason: '$e');
    }
  }

  /// Pide descargar el español para reconocer sin internet. Elige es-US,
  /// es-ES, es-MX o es-CO según lo que ofrezca el teléfono.
  /// Devuelve "success", "scheduled", "requested", "error:CÓDIGO",
  /// "unsupported" o "already_installed".
  static Future<String> downloadSpanish() async {
    final st = await status();
    if (!st.supported) return 'unsupported';
    if (st.hasSpanishInstalled) return 'already_installed';

    final available = st.available.map((l) => l.toLowerCase()).toList();
    String language = _preferred.firstWhere(
      (p) => available.contains(p.toLowerCase()),
      orElse: () => st.available.firstWhere(
        (l) => l.toLowerCase().startsWith('es'),
        orElse: () => 'es-US',
      ),
    );

    debugPrint('[Emki] Descargando voz sin conexión: $language');
    try {
      final r = await _channel
          .invokeMethod<String>('download', {'language': language})
          .timeout(const Duration(minutes: 5), onTimeout: () => 'scheduled');
      debugPrint('[Emki] Resultado de la descarga ($language): $r');
      return r ?? 'error:null';
    } catch (e) {
      debugPrint('[Emki] Error al descargar la voz sin conexión: $e');
      return 'error:$e';
    }
  }
}
