import 'package:flutter/material.dart';
import '../../services/firebase_service.dart';
import '../../models/user_profile.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService();
  bool _isPublic = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPrivacy();
  }

  void _loadPrivacy() async {
    final profile = await _firebaseService.getUserProfile();
    if (profile != null) {
      setState(() => _isPublic = profile.isPublic);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunidad Parkinson', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple.shade100,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF6A1B9A),
          labelColor: const Color(0xFF6A1B9A),
          tabs: const [
            Tab(text: 'Compañeros'),
            Tab(text: 'Grupos'),
            Tab(text: 'Lecciones'),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            _CompanionsTab(firebaseService: _firebaseService),
            _GroupsTab(),
            _LessonsTab(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          setState(() => _isPublic = !_isPublic);
          _firebaseService.updatePrivacy(_isPublic);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isPublic ? 'Tu perfil ahora es público' : 'Tu perfil ahora es privado')),
          );
        },
        backgroundColor: _isPublic ? Colors.green : Colors.grey,
        icon: Icon(_isPublic ? Icons.visibility : Icons.visibility_off),
        label: Text(_isPublic ? 'Público' : 'Privado'),
      ),
    );
  }
}

class _CompanionsTab extends StatelessWidget {
  final FirebaseService firebaseService;
  const _CompanionsTab({required this.firebaseService});

  @override
  Widget build(BuildContext context) {
    // Datos DEMO diferenciados
    final List<UserProfile> demoProfiles = [
      UserProfile(
        uid: 'demo1', name: 'María', lastName: 'García', fixedPhone: '', cellPhone: '3001234567', 
        photoUrl: '', diagnosisYear: 2020, experience: 'Me gusta caminar y bailar para mantenerme activa.', 
        specialistName: 'Dr. Santos', specialistType: 'Neurología', hospital: 'Hospital San José', 
        consultationTime: 'Lunes 10am', supportGroup: 'Club Parkinson Bogotá', isPublic: true
      ),
      UserProfile(
        uid: 'demo2', name: 'Juan', lastName: 'Pérez', fixedPhone: '', cellPhone: '', 
        photoUrl: '', diagnosisYear: 2018, experience: 'El apoyo del grupo ha sido fundamental.', 
        specialistName: 'Dra. López', specialistType: 'Fisioterapia', hospital: 'Clínica Salud', 
        consultationTime: 'Miércoles 3pm', supportGroup: 'Asociación de pacientes', isPublic: true
      ),
    ];

    return StreamBuilder<List<UserProfile>>(
      stream: firebaseService.getCommunityProfiles(),
      builder: (context, snapshot) {
        final realProfiles = snapshot.data ?? [];
        final allProfiles = [...demoProfiles, ...realProfiles];

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: allProfiles.length,
          itemBuilder: (context, index) {
            final p = allProfiles[index];
            if (p.uid == firebaseService.currentUserId) return const SizedBox.shrink();
            
            final isDemo = p.uid.startsWith('demo');

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              margin: const EdgeInsets.only(bottom: 15),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isDemo ? Colors.orange.shade200 : Colors.purple.shade200,
                        backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                        child: p.photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                      title: Text('${p.name} ${isDemo ? "(DEMO)" : ""}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      subtitle: Text('Diagnóstico: ${p.diagnosisYear ?? "N/A"}'),
                    ),
                    Text(p.experience, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => _showCompanionDetails(context, p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green, // Color Verde
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                          minimumSize: const Size(80, 30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Conocer', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showCompanionDetails(BuildContext context, UserProfile p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.purple.shade100,
                  backgroundImage: p.photoUrl.isNotEmpty ? NetworkImage(p.photoUrl) : null,
                  child: p.photoUrl.isEmpty ? const Icon(Icons.person, size: 50) : null,
                ),
              ),
              const SizedBox(height: 20),
              Center(child: Text(p.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))),
              const Divider(height: 40),
              _buildDetailItem('Desde:', '${p.diagnosisYear ?? "N/A"}'),
              _buildDetailItem('Experiencia:', p.experience),
              _buildDetailItem('Especialista:', p.specialistName),
              _buildDetailItem('Especialidad:', p.specialistType),
              _buildDetailItem('Hospital:', p.hospital),
              _buildDetailItem('Grupo:', p.supportGroup),
              if (p.cellPhone.isNotEmpty) _buildDetailItem('Teléfono:', p.cellPhone),
              const SizedBox(height: 30),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.chat),
                  label: const Text('ENVIAR MENSAJE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(200, 50),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _GroupsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildGroupCard(context, 'Club Parkinson Bogotá', '📍 Bogotá • 25 miembros', Icons.groups, 
          'Un espacio de encuentro semanal para compartir experiencias y realizar actividades conjuntas.'),
        _buildGroupCard(context, 'Grupo de Caminatas', '🏃 Actividad física • 12 miembros', Icons.directions_walk,
          'Salidas programadas los sábados por la mañana en el Parque Simón Bolívar.'),
        _buildGroupCard(context, 'Asociación de Pacientes', '🤝 Apoyo mutuo • 50 miembros', Icons.volunteer_activism,
          'Red nacional de apoyo para pacientes y cuidadores.'),
      ],
    );
  }

  Widget _buildGroupCard(BuildContext context, String title, String subtitle, IconData icon, String desc) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: Icon(icon, color: Colors.purple, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _GroupDetailScreen(title: title, subtitle: subtitle, desc: desc))),
      ),
    );
  }
}

class _GroupDetailScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String desc;

  const _GroupDetailScreen({required this.title, required this.subtitle, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.purple.shade100),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.image, size: 100, color: Colors.purple),
            ),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.purple)),
            Text(subtitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const Divider(height: 40),
            const Text('Descripción:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Text(desc, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            const Text('Información de contacto:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            const Text('Dirección: Calle Falsa 123, Bogotá\nTeléfono: (601) 123 4567\nEmail: contacto@comunidad.co\nHorarios: Sábados 10:00 AM - 12:00 PM'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
              ),
              child: const Text('← VOLVER'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Lecciones de aprendizaje', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple)),
        const SizedBox(height: 15),
        _buildLessonItem(context, '¿Qué es el Parkinson?', 'Conceptos básicos y síntomas iniciales.', 
          'El Parkinson es una condición neurodegenerativa que afecta el movimiento. Se produce por la disminución de dopamina en el cerebro.'),
        _buildLessonItem(context, 'Importancia de la actividad física', 'Cómo el movimiento ayuda a tu cerebro.',
          'El ejercicio regular mejora la plasticidad cerebral y ayuda a controlar síntomas como la rigidez.'),
        _buildLessonItem(context, 'Alimentación y bienestar', 'Tips para una dieta saludable.',
          'Una dieta rica en fibra y agua es esencial para el manejo digestivo en el Parkinson.'),
        const SizedBox(height: 25),
        const Text('Concientización', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
        const SizedBox(height: 15),
        _buildLessonItem(context, 'Mitos y realidades', 'Desmintiendo falsas creencias.',
          'Mito: Solo afecta a personas muy mayores. Realidad: El diagnóstico temprano es posible a cualquier edad.'),
      ],
    );
  }

  Widget _buildLessonItem(BuildContext context, String title, String summary, String content) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        leading: const Icon(Icons.book, color: Colors.orange),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(summary),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _LessonDetailScreen(title: title, content: content))),
      ),
    );
  }
}

class _LessonDetailScreen extends StatelessWidget {
  final String title;
  final String content;

  const _LessonDetailScreen({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lección'), backgroundColor: Colors.purple.shade100),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.purple)),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 20),
                  Text(content, style: const TextStyle(fontSize: 18, height: 1.5)),
                  const SizedBox(height: 40),
                  const Text('Datos relevantes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 10),
                  const Text('• Mantenerse informado es clave para el tratamiento.\n• El apoyo familiar mejora la calidad de vida.'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('← VOLVER', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
