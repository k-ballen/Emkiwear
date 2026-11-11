/// Estado de App Check para diagnóstico en el modal del asistente (solo kDebugMode).
/// NUNCA guarda el token: solo si fue inyectado por --dart-define.
class AppCheckInfo {
  static String status = 'No verificado';
  static String provider = 'Desconocido';
  static bool hasDebugToken = false;

  static String get summary =>
      'AppCheck: $status [$provider, tokenInyectado: ${hasDebugToken ? 'SÍ' : 'NO'}]';
}
