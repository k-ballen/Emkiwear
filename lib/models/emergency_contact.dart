/// Contacto de emergencia (se guarda en users/{uid}.emergencyContacts).
class EmergencyContact {
  final String name;
  final String phone;

  /// Parentesco o relación: "hija", "esposo", "vecina", "cuidador"...
  final String relation;

  const EmergencyContact({required this.name, required this.phone, this.relation = ''});

  /// "María (hija)" o "María".
  String get label => relation.isEmpty ? name : '$name ($relation)';

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'relation': relation};

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact(
        name: (m['name'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
        relation: (m['relation'] ?? '').toString(),
      );

  /// Número solo con dígitos y "+", para marcar.
  static String cleanPhone(String raw) => raw.replaceAll(RegExp(r'[^\d+]'), '');
}
