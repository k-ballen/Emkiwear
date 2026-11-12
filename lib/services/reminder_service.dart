import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication_reminder.dart';
import 'firebase_service.dart';

const String _takenActionId = 'TAKEN';
const String _pendingTakenKey = 'pending_taken_doses';

/// Id de notificación determinístico a partir del id de la toma (FNV-1a).
/// [followUp] = número de reaviso (0 = aviso principal, 1..N = reavisos).
@visibleForTesting
int notificationIdFor(String taskId, {int followUp = 0}) {
  var h = 0x811c9dc5;
  for (final c in '$taskId${followUp > 0 ? '#r$followUp' : ''}'.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// Se ejecuta en un isolate aparte cuando se toca "Ya la tomé" con la app cerrada.
@pragma('vm:entry-point')
Future<void> onReminderNotificationBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await ReminderService.handleResponse(response, background: true);
}

/// Recordatorios de medicamentos con notificaciones locales.
///
/// - Programa cada toma de los próximos [horizonDays] días (notificación a la
///   hora exacta + reaviso a los 15 min si no se marca). Se reprograma al
///   abrir la app y cada vez que cambian los recordatorios; tras reiniciar el
///   teléfono, el plugin restaura las notificaciones programadas.
/// - Botón "Ya la tomé": marca la toma en medication_tasks (aunque la app esté
///   cerrada) y cancela el reaviso. Si no hay internet, queda en cola y se
///   sincroniza al abrir la app.
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  // Reavisos cada 5 min (máximo 3: a los 5, 10 y 15 min) hasta que se toque
  // "Ya la tomé". Con 4 notificaciones por toma se programan 7 días.
  static const int horizonDays = 7;
  static const Duration followUpEvery = Duration(minutes: 5);
  static const int followUpCount = 3;
  static const String channelId = 'medication_reminders';
  static const String channelName = 'Recordatorios de medicamentos';
  static const int maxScheduled = 400; // Android permite ~500 alarmas por app

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final FirebaseService _firebase = FirebaseService();
  bool _initialized = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<MedicationReminder>>? _remindersSub;
  Timer? _debounce;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('[Recordatorios] Zona horaria no disponible ($e); uso America/Bogota.');
      tz.setLocalLocation(tz.getLocation('America/Bogota'));
    }
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => handleResponse(r),
      onDidReceiveBackgroundNotificationResponse: onReminderNotificationBackground,
    );
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Avisos a la hora de tomar cada medicamento',
      importance: Importance.max,
    ));
    _initialized = true;

    // Si la app estaba CERRADA y se abrió con "Ya la tomé", la respuesta
    // llega aquí (no por onDidReceiveNotificationResponse).
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        debugPrint('[Recordatorios] App abierta desde la notificación (acción: ${response.actionId}).');
        unawaited(handleResponse(response));
      }
    } catch (e) {
      debugPrint('[Recordatorios] No pude leer cómo se abrió la app: $e');
    }
  }

  /// Escucha la sesión y los recordatorios del usuario y reprograma al cambiar.
  void startSync() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _remindersSub?.cancel();
      _remindersSub = null;
      if (user == null) {
        await _plugin.cancelAll();
        return;
      }
      unawaited(flushPendingTaken());
      _remindersSub = _firebase.streamReminders().listen((list) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 1), () => rescheduleAll(list));
      }, onError: (e) => debugPrint('[Recordatorios] Error leyendo recordatorios: $e'));
    });
  }

  /// Pide permiso de notificaciones (Android 13+) y de alarmas exactas.
  /// Devuelve false si el usuario negó las notificaciones.
  Future<bool> requestPermissions() async {
    await init();
    final android = _android;
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission() ?? true;
    final exact = await android.canScheduleExactNotifications() ?? true;
    if (!exact) await android.requestExactAlarmsPermission();
    return granted;
  }

  Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'Avisos a la hora de tomar cada medicamento',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          actions: [
            // showsUserInterface: true -> la acción se procesa en la app
            // principal. Sin la app al frente, flutter_local_notifications 17
            // intentaba un motor en segundo plano que fallaba ("Engine is
            // already initialised") y la toma no se registraba.
            AndroidNotificationAction(
              _takenActionId,
              'Ya la tomé',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      );

  static String _fmt(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  /// Cancela y vuelve a programar todas las notificaciones.
  Future<void> rescheduleAll(List<MedicationReminder> reminders) async {
    await init();
    final canExact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = canExact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    await _plugin.cancelAll();

    final now = DateTime.now();
    Set<String> taken = {};
    try {
      taken = await _firebase.getTakenTaskIdsFrom(DateTime(now.year, now.month, now.day))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[Recordatorios] No pude leer tomas marcadas ($e); programo todas.');
    }

    // Los recordatorios ya NO crean tomas pendientes en "Medicamentos de hoy":
    // la toma se registra solo al tocar "Ya la tomé". Se limpian las que
    // versiones anteriores dejaron creadas por adelantado.
    try {
      await _firebase.deleteUntakenReminderTasks().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[Recordatorios] No pude limpiar tomas pendientes antiguas ($e).');
    }

    // Todas las tomas de todos los recordatorios, ordenadas por hora: si se
    // llega al límite de alarmas, se quedan las más próximas de TODOS.
    final pending = <({MedicationReminder r, DateTime dose})>[
      for (final r in reminders.where((r) => r.active))
        for (final dose in r.dosesBetween(now, horizonDays))
          if (!taken.contains(r.doseTaskId(dose))) (r: r, dose: dose),
    ]..sort((a, b) => a.dose.compareTo(b.dose));

    var count = 0;
    for (final item in pending) {
      final r = item.r;
      final dose = item.dose;
      final label = r.dose != null ? '${r.name} (${r.dose})' : r.name;
      final taskId = r.doseTaskId(dose);
      // Todo lo necesario para registrar la toma desde la notificación.
      final payload = jsonEncode({
        'taskId': taskId,
        'reminderId': r.id,
        'name': label,
        'doseMs': dose.millisecondsSinceEpoch,
        'time': _fmt(dose),
      });
      for (var k = 0; k <= followUpCount; k++) {
        final at = dose.add(followUpEvery * k);
        if (!at.isAfter(now)) continue;
        if (count >= maxScheduled) break;
        await _plugin.zonedSchedule(
          notificationIdFor(taskId, followUp: k),
          k == 0 ? 'Hora de tu medicamento' : '¿Ya tomaste tu medicamento?',
          k == 0
              ? '$label · ${_fmt(dose)}'
              : 'Aún no has marcado $label de las ${_fmt(dose)}. Toca "Ya la tomé".',
          tz.TZDateTime.from(at, tz.local),
          _details(),
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: mode,
          payload: payload,
        );
        count++;
      }
      if (count >= maxScheduled) break;
    }
    debugPrint('[Recordatorios] $count notificaciones programadas '
        '(${reminders.where((r) => r.active).length} recordatorios activos, '
        '${canExact ? 'hora exacta' : 'hora aproximada: falta permiso de alarmas exactas'}).');
  }

  /// La toma se marcó desde la app: cancela su aviso y su reaviso.
  Future<void> cancelDose(String taskId) async {
    await init();
    for (var k = 0; k <= followUpCount; k++) {
      await _plugin.cancel(notificationIdFor(taskId, followUp: k));
    }
  }

  /// Respuesta a una notificación (app abierta o en segundo plano).
  static Future<void> handleResponse(NotificationResponse response, {bool background = false}) async {
    debugPrint('[Recordatorios] Respuesta a notificación: acción=${response.actionId} '
        '(segundo plano: $background)');
    final payload = response.payload;
    if (payload == null || response.actionId != _takenActionId) return;
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final taskId = data['taskId'] as String?;
    if (taskId == null) return;

    // Cancela el aviso y TODOS sus reavisos pendientes.
    final plugin = FlutterLocalNotificationsPlugin();
    for (var k = 0; k <= followUpCount; k++) {
      await plugin.cancel(notificationIdFor(taskId, followUp: k));
    }

    // Primero a la cola local (no se pierde aunque falle la red) y luego se
    // intenta subir. Se guarda todo para CREAR la toma como tomada.
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final queue = prefs.getStringList(_pendingTakenKey) ?? <String>[];
    queue.add(jsonEncode({...data, 'takenMs': DateTime.now().millisecondsSinceEpoch}));
    await prefs.setStringList(_pendingTakenKey, queue);
    debugPrint('[Recordatorios] "Ya la tomé": $taskId (segundo plano: $background)');

    if (background) {
      try {
        if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      } catch (e) {
        debugPrint('[Recordatorios] Firebase no disponible en segundo plano: $e');
        return; // se sincroniza al abrir la app
      }
    }
    await instance.flushPendingTaken();
  }

  /// Sube a Firestore las tomas marcadas desde la notificación.
  Future<void> flushPendingTaken() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final queue = prefs.getStringList(_pendingTakenKey) ?? <String>[];
    if (queue.isEmpty) return;
    final remaining = <String>[];
    for (final entry in queue) {
      Map<String, dynamic> d;
      try {
        d = jsonDecode(entry) as Map<String, dynamic>;
      } catch (_) {
        continue; // formato viejo ("id|ms"): sin datos para crear la toma
      }
      final taskId = d['taskId'] as String?;
      final doseMs = (d['doseMs'] as num?)?.toInt();
      if (taskId == null || doseMs == null) continue;
      try {
        await FirebaseService()
            .recordReminderDoseTaken(
              taskId: taskId,
              reminderId: (d['reminderId'] as String?) ?? '',
              name: (d['name'] as String?) ?? 'Medicamento',
              scheduled: DateTime.fromMillisecondsSinceEpoch(doseMs),
              takenAt: DateTime.fromMillisecondsSinceEpoch(
                  (d['takenMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
            )
            .timeout(const Duration(seconds: 8));
        debugPrint('[Recordatorios] Toma registrada en Medicamentos: $taskId');
      } on TimeoutException {
        // Sin confirmación del servidor: ya está en la cola local de Firestore.
        debugPrint('[Recordatorios] Toma $taskId en cola local de Firestore.');
      } catch (e) {
        remaining.add(entry);
        debugPrint('[Recordatorios] No pude registrar $taskId: $e');
      }
    }
    await prefs.setStringList(_pendingTakenKey, remaining);
  }
}
