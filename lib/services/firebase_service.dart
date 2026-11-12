import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'package:intl/intl.dart';
import '../models/tremor_data.dart';
import '../models/medication_task.dart';
import '../models/medication_reminder.dart';
import '../models/emergency_contact.dart';
import '../models/food_habit.dart';
import '../models/activity_habit.dart';
import '../models/user_profile.dart';
import '../models/tremor_summary.dart';

/// Resumen de temblor de HOY (suma de los bloques de 5 min de tremor_summaries).
/// Cada muestra STATUS equivale a 0,5 s.
class TodayTremorSummary {
  final int windows;
  final int totalSamples;
  final Map<String, int> severityCounts;
  final double maxIntensity;
  final double maxAngleDeg;

  const TodayTremorSummary({
    required this.windows,
    required this.totalSamples,
    required this.severityCounts,
    required this.maxIntensity,
    required this.maxAngleDeg,
  });

  static double _minutes(int samples) => samples * 0.5 / 60.0;

  double get monitoredMinutes => _minutes(totalSamples);
  int count(String key) => severityCounts[key] ?? 0;
  double minutesOf(String key) => _minutes(count(key));
  double get tremorMinutes => minutesOf('LEVE') + minutesOf('MODERADO') + minutesOf('GRAVE');
}

class FirebaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Autenticación
  Future<User?> signInWithGoogle() async {
    try {
      await _googleSignIn.signOut();
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result =
          await _auth.signInWithCredential(credential);
      return result.user;
    } on PlatformException catch (e) {
      if (e.code == 'network_error') {
        throw 'Error de red. Por favor, verifica tu conexión.';
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw 'Ocurrió un error inesperado al iniciar sesión.';
    }
  }

  Future<User?> signUp(String email, String password, String name) async {
    UserCredential? result;
    
    try {
      result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw 'Ocurrió un error inesperado al registrar la cuenta.';
    }

    if (result.user != null) {
      try {
        await result.user!.updateDisplayName(name);
        await _db.collection('users').doc(result.user!.uid).set({
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'isPublic': false,
        });
      } catch (e) {
        developer.log('Perfil de usuario no pudo ser guardado en Firestore: $e');
      }
    }
    
    return result.user;
  }

  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthError(e);
    } catch (e) {
      throw 'No se pudo enviar el correo de recuperación.';
    }
  }

  String _handleAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No existe una cuenta con este correo electrónico.';
      case 'wrong-password':
        return 'La contraseña es incorrecta.';
      case 'email-already-in-use':
        return 'Este correo electrónico ya está registrado.';
      case 'invalid-email':
        return 'El formato del correo electrónico no es válido.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada.';
      case 'network-request-failed':
        return 'Error de conexión. Revisa tu internet.';
      default:
        return 'Error de autenticación: ${e.message}';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Perfil de Usuario
  Future<UserProfile?> getUserProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(uid, doc.data()!);
  }

  Future<void> updateUserProfile(UserProfile profile) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(profile.toFirestore(), SetOptions(merge: true));
  }

  // ===== Contactos de emergencia (users/{uid}.emergencyContacts) =====

  Future<List<EmergencyContact>> getEmergencyContacts() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final doc = await _db.collection('users').doc(uid).get();
    final list = (doc.data()?['emergencyContacts'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => EmergencyContact.fromMap(Map<String, dynamic>.from(m)))
        .where((c) => c.phone.isNotEmpty)
        .toList();
  }

  Stream<List<EmergencyContact>> streamEmergencyContacts() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const []);
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      final list = (doc.data()?['emergencyContacts'] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((m) => EmergencyContact.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    });
  }

  Future<void> saveEmergencyContacts(List<EmergencyContact> contacts) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'emergencyContacts': contacts.map((c) => c.toMap()).toList()},
      SetOptions(merge: true),
    );
  }

  /// Actualiza SOLO los campos dados del perfil (lo usa el asistente de voz).
  Future<void> updateProfileFields(Map<String, dynamic> fields) async {
    final uid = currentUserId;
    if (uid == null || fields.isEmpty) return;
    await _db.collection('users').doc(uid).set(fields, SetOptions(merge: true));
  }

  Future<String> uploadProfilePhoto(File image) async {
    final uid = currentUserId;
    if (uid == null) return '';
    final ref = _storage.ref().child('user_photos').child('$uid.jpg');
    await ref.putFile(image);
    return await ref.getDownloadURL();
  }

  // Medicamentos
  Future<void> addMedicationTask(String name, DateTime scheduledDate, TimeOfDay time, bool isRecurring) async {
    final uid = currentUserId;
    if (uid == null) throw 'No hay un usuario autenticado';

    final DateTime scheduledDateTime = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
      time.hour,
      time.minute,
    );

    try {
      if (isRecurring) {
        final batch = _db.batch();
        for (int i = 0; i < 30; i++) {
          final date = scheduledDateTime.add(Duration(days: i));
          final docRef = _db.collection('medication_tasks').doc();
          batch.set(docRef, {
            'name': name,
            'scheduledDateTime': Timestamp.fromDate(date),
            'isTaken': false,
            'userId': uid,
          });
        }
        await batch.commit();
      } else {
        await _db.collection('medication_tasks').add({
          'name': name,
          'scheduledDateTime': Timestamp.fromDate(scheduledDateTime),
          'isTaken': false,
          'userId': uid,
        });
      }
    } catch (e) {
      developer.log('Error al guardar medicamento: $e');
      rethrow;
    }
  }

  Stream<List<MedicationTask>> getTasksForDate(DateTime date) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    return _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledDateTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MedicationTask.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime)));
  }

  // ===== Consultas del día para el asistente (se leen del SERVIDOR) =====
  // Si no hay conexión, lanzan excepción: el asistente dice "No pude consultar
  // tus datos" en vez de responder con datos viejos de la caché.

  /// Suma los bloques de 5 min de tremor_summaries de HOY (campo 'date').
  /// Devuelve null si no hay bloques hoy.
  Future<TodayTremorSummary?> getTodayTremorSummary({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uid = currentUserId;
    if (uid == null) throw 'No hay un usuario autenticado';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final snap = await _db
        .collection('tremor_summaries')
        .where('userId', isEqualTo: uid)
        .where('date', isEqualTo: today)
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    if (snap.docs.isEmpty) return null;

    final counts = <String, int>{};
    var totalSamples = 0;
    var maxIntensity = 0.0;
    var maxAngle = 0.0;
    for (final doc in snap.docs) {
      final d = doc.data();
      totalSamples += (d['totalSamples'] as num?)?.toInt() ?? 0;
      maxIntensity = math.max(maxIntensity, (d['maxIntensity'] as num?)?.toDouble() ?? 0);
      maxAngle = math.max(maxAngle, (d['maxAngleDeg'] as num?)?.toDouble() ?? 0);
      final sc = (d['severityCounts'] as Map?) ?? const {};
      sc.forEach((k, v) => counts[k.toString()] = (counts[k.toString()] ?? 0) + ((v as num?)?.toInt() ?? 0));
    }
    return TodayTremorSummary(
      windows: snap.docs.length,
      totalSamples: totalSamples,
      severityCounts: counts,
      maxIntensity: maxIntensity,
      maxAngleDeg: maxAngle,
    );
  }

  /// Tomas de medicamento programadas para HOY, ordenadas por hora.
  Future<List<MedicationTask>> getTodayMedications({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uid = currentUserId;
    if (uid == null) throw 'No hay un usuario autenticado';
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final snap = await _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledDateTime', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get(const GetOptions(source: Source.server))
        .timeout(timeout);
    return snap.docs.map((d) => MedicationTask.fromFirestore(d.id, d.data())).toList()
      ..sort((a, b) => a.scheduledDateTime.compareTo(b.scheduledDateTime));
  }

  // ===== Recordatorios de medicamentos (medication_reminders) =====

  Stream<List<MedicationReminder>> streamReminders() {
    final uid = currentUserId;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection('medication_reminders')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs.map((d) => MedicationReminder.fromFirestore(d.id, d.data())).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  }

  /// Crea (id null) o actualiza un recordatorio. Devuelve el id.
  Future<String> saveReminder(MedicationReminder r) async {
    final uid = currentUserId;
    if (uid == null) throw 'No hay un usuario autenticado';
    final col = _db.collection('medication_reminders');
    final ref = r.id.isEmpty ? col.doc() : col.doc(r.id);
    await ref.set(r.toFirestore(uid), SetOptions(merge: true));
    return ref.id;
  }

  Future<void> setReminderActive(String reminderId, bool active) async {
    await _db.collection('medication_reminders').doc(reminderId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Borra el recordatorio y sus tomas FUTURAS no tomadas (el historial queda).
  Future<void> deleteReminder(String reminderId) async {
    await deleteFutureDoseTasks(reminderId);
    await _db.collection('medication_reminders').doc(reminderId).delete();
  }

  /// Registra en medication_tasks una toma de recordatorio como TOMADA (solo
  /// cuando el usuario toca "Ya la tomé"). Id determinístico: no se duplica.
  Future<void> recordReminderDoseTaken({
    required String taskId,
    required String reminderId,
    required String name,
    required DateTime scheduled,
    required DateTime takenAt,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('medication_tasks').doc(taskId).set({
      'name': name,
      'scheduledDateTime': Timestamp.fromDate(scheduled),
      'userId': uid,
      'reminderId': reminderId,
      'isTaken': true,
      'takenDateTime': Timestamp.fromDate(takenAt),
    }, SetOptions(merge: true));
  }

  /// Borra las tomas de recordatorio NO tomadas (versiones anteriores las
  /// creaban por adelantado y aparecían en "Medicamentos de hoy").
  Future<void> deleteUntakenReminderTasks() async {
    final uid = currentUserId;
    if (uid == null) return;
    // Las tomas viejas se crearon SIN el campo isTaken (no sirve filtrar por
    // él): se buscan por fecha (los recordatorios creaban 14 días hacia
    // adelante) y se filtran aquí.
    final from = DateTime.now().subtract(const Duration(days: 2));
    final snap = await _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .get();
    final batch = _db.batch();
    var n = 0;
    for (final d in snap.docs) {
      final data = d.data();
      if ((data['reminderId'] as String?)?.isNotEmpty == true && data['isTaken'] != true) {
        batch.delete(d.reference);
        n++;
      }
    }
    if (n > 0) {
      await batch.commit();
      developer.log('Borradas $n tomas pendientes creadas por recordatorios');
    }
  }

  /// Recordatorios del usuario (una sola lectura).
  Future<List<MedicationReminder>> getReminders() async => streamReminders().first;

  /// Ids de las tomas ya marcadas como tomadas desde [from] (para no volver a
  /// programar notificaciones de pastillas ya tomadas).
  Future<Set<String>> getTakenTaskIdsFrom(DateTime from) async {
    final uid = currentUserId;
    if (uid == null) return {};
    final snap = await _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .where('scheduledDateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .get();
    return snap.docs.where((d) => d.data()['isTaken'] == true).map((d) => d.id).toSet();
  }

  /// Borra las tomas futuras NO tomadas de un recordatorio (al borrarlo,
  /// desactivarlo o cambiar sus horas).
  Future<void> deleteFutureDoseTasks(String reminderId) async {
    final uid = currentUserId;
    if (uid == null) return;
    final snap = await _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .where('reminderId', isEqualTo: reminderId)
        .get();
    final now = DateTime.now();
    final batch = _db.batch();
    var n = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final when = (data['scheduledDateTime'] as Timestamp?)?.toDate();
      if (when != null && when.isAfter(now) && data['isTaken'] != true) {
        batch.delete(d.reference);
        n++;
      }
    }
    if (n > 0) await batch.commit();
  }

  Future<void> updateTaskStatus(String taskId, bool isTaken) async {
    await _db.collection('medication_tasks').doc(taskId).update({
      'isTaken': isTaken,
      'takenDateTime': isTaken ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> deleteMedicationTask(String taskId) async {
    await _db.collection('medication_tasks').doc(taskId).delete();
  }

  Stream<Set<DateTime>> getDatesWithTasks() {
    final uid = currentUserId;
    if (uid == null) return Stream.value({});
    return _db
        .collection('medication_tasks')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final Set<DateTime> dates = {};
      for (var doc in snapshot.docs) {
        final dt = (doc.data()['scheduledDateTime'] as Timestamp).toDate();
        dates.add(DateTime(dt.year, dt.month, dt.day));
      }
      return dates;
    });
  }

  // Hábitos Alimenticios
  Future<void> logFoodHabit(String food, String mealType, DateTime date, TimeOfDay time) async {
    final uid = currentUserId;
    if (uid == null) return;
    final timestamp = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _db.collection('food_habits').add({
      'food': food,
      'mealType': mealType,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': uid,
    });
  }

  Future<void> deleteFoodHabit(String habitId) async {
    await _db.collection('food_habits').doc(habitId).delete();
  }

  Stream<List<FoodHabit>> getFoodHabits(DateTime date) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    final start = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return _db
        .collection('food_habits')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => FoodHabit.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  }

  // Actividad Física
  Future<void> logActivityHabit(String activityType, int duration, String intensity, DateTime date, TimeOfDay time) async {
    final uid = currentUserId;
    if (uid == null) return;
    final timestamp = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _db.collection('activity_habits').add({
      'activityType': activityType,
      'duration': duration,
      'intensity': intensity,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': uid,
    });
  }

  Future<void> deleteActivityHabit(String habitId) async {
    await _db.collection('activity_habits').doc(habitId).delete();
  }

  Stream<List<ActivityHabit>> getActivityHabits(DateTime date) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    final start = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return _db
        .collection('activity_habits')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ActivityHabit.fromFirestore(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  }

  Stream<List<ActivityHabit>> getActivityHabitsForMonth(DateTime month) {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    return _db
        .collection('activity_habits')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ActivityHabit.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  // Comunidad
  Stream<List<UserProfile>> getCommunityProfiles() {
    return _db
        .collection('users')
        .where('isPublic', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => UserProfile.fromFirestore(doc.id, doc.data()))
            .toList());
  }

  Future<void> updatePrivacy(bool isPublic) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({'isPublic': isPublic});
  }

  // Temblor (Desde ESP32)
  Future<void> addTremorData(TremorData data) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await _db.collection('tremor_readings').add({
        ...data.toFirestore(),
        'userId': uid,
      });
    } catch (e) {
      developer.log('Error al guardar datos de temblor: $e');
    }
  }

  Future<void> addTremorSummary(TremorSummary summary) async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      // Usamos el ID determinístico para evitar duplicados y permitir mezclar datos
      await _db.collection('tremor_summaries').doc(summary.id).set(
        {
          ...summary.toFirestore(),
          'userId': uid,
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      developer.log('Error al guardar resumen de temblor: $e');
    }
  }

  Stream<List<TremorData>> getTremorStream() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('tremor_readings')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TremorData.fromFirestore(doc.data()))
            .toList());
  }
}
