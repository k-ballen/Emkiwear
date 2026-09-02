import 'package:cloud_firestore/cloud_firestore.dart';

class FoodHabit {
  final String id;
  final String food;
  final String mealType; // Desayuno, Almuerzo, Cena, Merienda
  final DateTime timestamp;
  final String userId;

  FoodHabit({
    required this.id,
    required this.food,
    required this.mealType,
    required this.timestamp,
    required this.userId,
  });

  factory FoodHabit.fromFirestore(String id, Map<String, dynamic> data) {
    return FoodHabit(
      id: id,
      food: data['food'] ?? '',
      mealType: data['mealType'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      userId: data['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'food': food,
      'mealType': mealType,
      'timestamp': Timestamp.fromDate(timestamp),
      'userId': userId,
    };
  }
}
