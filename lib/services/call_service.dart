import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_contact.dart';

/// Abre el marcador del teléfono con el número listo para llamar (un toque).
/// No llama directamente: así no se necesita el permiso CALL_PHONE y se evita
/// marcar por error.
class CallService {
  /// Línea única de emergencias en Colombia.
  static const String emergencyNumber = '123';

  static Future<bool> dial(String phone) async {
    final number = EmergencyContact.cleanPhone(phone);
    if (number.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final ok = await launchUrl(uri);
      debugPrint('[Emergencia] Marcador abierto para $number: $ok');
      return ok;
    } catch (e) {
      debugPrint('[Emergencia] No se pudo abrir el marcador: $e');
      return false;
    }
  }
}
