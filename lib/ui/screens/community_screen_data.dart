import 'package:flutter/material.dart';
import '../../models/user_profile.dart';


/// ---------------------------------------------------------------------------
/// Data model for community groups (used by both Grupos tab and voice lookup)
/// ---------------------------------------------------------------------------
class CommunityGroup {
  final String title;
  final String subtitle;
  final IconData icon;
  final String description;
  final String contact;

  CommunityGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.description,
    required this.contact,
  });
}

/// ---------------------------------------------------------------------------
/// Top-level demo data - shared between the UI tabs and the voice assistant
/// lookup so that voice commands can resolve names/titles consistently.
/// ---------------------------------------------------------------------------

/// ---------------------------------------------------------------------------
/// Data model for community lessons (used by both Lecciones tab and voice lookup)
/// ---------------------------------------------------------------------------
class CommunityLesson {
  final String title;
  final String summary;
  final String content;

  CommunityLesson({
    required this.title,
    required this.summary,
    required this.content,
  });
}

/// Demo companion profiles visible to other users.
final List<UserProfile> demoCompanionProfiles = [
  UserProfile(
    uid: 'demo1',
    name: 'María',
    lastName: 'García',
    fixedPhone: '',
    cellPhone: '3001234567',
    photoUrl: '',
    diagnosisYear: 2020,
    experience: 'Llevo 4 años manejando el Parkinson con valentía y optimismo.',
    specialistName: 'Dra. Patricia López',
    specialistType: 'Neurología',
    hospital: 'Hospital Pablo Tobón Uribe',
    consultationTime: 'Cada 3 meses',
    supportGroup: 'Club Parkinson Bogotá',
    isPublic: true,
  ),
  UserProfile(
    uid: 'demo2',
    name: 'Juan',
    lastName: 'Pérez',
    fixedPhone: '6012345',
    cellPhone: '3109876543',
    photoUrl: '',
    diagnosisYear: 2018,
    experience: 'Diagnosticado joven, me adapto cada día. Comparto tips de ejercicio.',
    specialistName: 'Dr. Carlos Ruiz',
    specialistType: 'Neurología',
    hospital: 'Clínica León',
    consultationTime: 'Cada 2 meses',
    supportGroup: 'Grupo de Caminatas',
    isPublic: true,
  ),
  UserProfile(
    uid: 'demo3',
    name: 'Daniela',
    lastName: 'Rodríguez',
    fixedPhone: '',
    cellPhone: '3205556789',
    photoUrl: '',
    diagnosisYear: 2022,
    experience: 'Soy cuidadora y compañera en la comunidad. Siempre dispuesta a ayudar.',
    specialistName: 'Dra. Laura Méndez',
    specialistType: 'Neurología',
    hospital: 'Hospital San Vicente',
    consultationTime: 'Cada mes',
    supportGroup: 'Asociación de Pacientes',
    isPublic: true,
  ),
];

/// Top-level group data - shared between the Grupos tab and voice lookup.
final List<CommunityGroup> demoGroups = [
  CommunityGroup(
    title: 'Club Parkinson Bogotá',
    subtitle: '📍 Bogotá • 25 miembros',
    icon: Icons.groups,
    description: 'Un espacio de encuentro semanal para compartir experiencias y realizar actividades conjuntas.',
    contact: 'Coordinador: María García',
  ),
  CommunityGroup(
    title: 'Grupo de Caminatas',
    subtitle: '🏃 Actividad física • 12 miembros',
    icon: Icons.directions_walk,
    description: 'Salidas programadas los sábados por la mañana en el Parque Simón Bolívar.',
    contact: 'Coordinador: Juan Pérez',
  ),
  CommunityGroup(
    title: 'Asociación de Pacientes',
    subtitle: '🤝 Apoyo mutuo • 50 miembros',
    icon: Icons.volunteer_activism,
    description: 'Red nacional de apoyo para pacientes y cuidadores con charlas mensuales.',
    contact: 'Coordinadora: Daniela Rodríguez',
  ),
];

/// Top-level lesson data - shared between the Lecciones tab and voice lookup.
final List<CommunityLesson> demoLessons = [
  CommunityLesson(
    title: '¿Qué es el Parkinson?',
    summary: 'Conceptos básicos y síntomas iniciales.',
    content: 'El Parkinson es una condición neurodegenerativa que afecta el movimiento. Se produce por la disminución de dopamina en el cerebro.',
  ),
  CommunityLesson(
    title: 'Importancia de la actividad física',
    summary: 'Cómo el movimiento ayuda a tu cerebro.',
    content: 'El ejercicio regular mejora la plasticidad cerebral y ayuda a controlar síntomas como la rigidez.',
  ),
  CommunityLesson(
    title: 'Alimentación y bienestar',
    summary: 'Tips para una dieta saludable.',
    content: 'Una dieta rica en fibra y agua es esencial para el manejo digestivo en el Parkinson.',
  ),
  CommunityLesson(
    title: 'Mitos y realidades',
    summary: 'Desmintiendo falsas creencias.',
    content: 'Mito: Solo afecta a personas muy mayores. Realidad: El diagnóstico temprano es posible a cualquier edad.',
  ),
];



/// Shows a detailed profile bottom-sheet for a companion.
void showCompanionDetails(BuildContext context, UserProfile p) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.purple.shade100,
                  shape: BoxShape.circle,
                ),
                child: p.photoUrl.isNotEmpty
                    ? CircleAvatar(backgroundImage: NetworkImage(p.photoUrl), radius: 40)
                    : const Icon(Icons.person, size: 40, color: Color(0xFF6A1B9A)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                p.supportGroup.isNotEmpty ? p.supportGroup : 'Sin grupo',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 20),
            buildCompanionDetailItem('Desde:', p.diagnosisYear != null ? p.diagnosisYear.toString() : 'N/A'),
            buildCompanionDetailItem('Experiencia:', p.experience),
            buildCompanionDetailItem('Especialista:', p.specialistName),
            buildCompanionDetailItem('Especialidad:', p.specialistType),
            buildCompanionDetailItem('Hospital:', p.hospital),
            buildCompanionDetailItem('Grupo:', p.supportGroup),
            if (p.cellPhone.isNotEmpty) buildCompanionDetailItem('Teléfono:', p.cellPhone),
            if (p.fixedPhone.isNotEmpty) buildCompanionDetailItem('Teléfono fijo:', p.fixedPhone),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text('Cerrar', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Builds a labeled detail row for the companion profile sheet.
Widget buildCompanionDetailItem(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isNotEmpty ? value : '—',
            style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
          ),
        ),
      ],
    ),
  );
}
