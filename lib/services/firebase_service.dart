import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:developer' as developer;
import '../models/tremor_data.dart';
import '../models/medication_task.dart';
import '../models/food_habit.dart';
import '../models/activity_habit.dart';
import '../models/user_profile.dart';
import '../models/tremor_summary.dart';

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
