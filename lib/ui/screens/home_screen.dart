import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firebase_service.dart';
import 'tremor_chart_screen.dart';
import 'medication_screen.dart';
import 'habits_screen.dart';
import 'community_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firebaseService = FirebaseService();
    final user = FirebaseAuth.instance.currentUser;
    final String displayName = user?.displayName ?? user?.email?.split('@')[0] ?? 'Usuario';

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.shade100,
              Colors.lightGreen.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header Personalizado
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bienvenido,',
                            style: TextStyle(fontSize: 20, color: Colors.black54, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 28, color: Colors.black87),
                        onPressed: () => firebaseService.signOut(),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 10),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _MenuButton(
                      title: 'Mi Temblor',
                      subtitle: 'Monitoreo en tiempo real',
                      icon: Icons.auto_graph_rounded,
                      color: const Color(0xFFCE93D8), // Púrpura 1
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TremorChartScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Medicamentos',
                      subtitle: 'Registro y recordatorios',
                      icon: Icons.medication_liquid_rounded,
                      color: const Color(0xFFAED581), // Verde 1
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MedicationScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Hábitos',
                      subtitle: 'Alimentación y ejercicio',
                      icon: Icons.favorite_rounded,
                      color: const Color(0xFFCE93D8), // Púrpura 2
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const HabitsScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Comunidad',
                      subtitle: 'Conecta con otros',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFFAED581), // Verde 2
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CommunityScreen()),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MenuButton(
                      title: 'Mi Perfil',
                      subtitle: 'Gestiona tu información',
                      icon: Icons.person_rounded,
                      color: const Color(0xFFCE93D8), // Púrpura 3 (Final)
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: const _AssistantButton(),
    );
  }
}

class _AssistantButton extends StatelessWidget {
  const _AssistantButton();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: const Text(
            '¿Necesitas ayuda?',
            style: TextStyle(
              color: Color(0xFF6A1B9A),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        FloatingActionButton(
          onPressed: () => _showAssistantModal(context),
          backgroundColor: const Color(0xFF6A1B9A),
          elevation: 6,
          child: const Icon(Icons.mic_rounded, size: 32, color: Colors.white),
        ),
      ],
    );
  }

  void _showAssistantModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AssistantModal(),
    );
  }
}

class _AssistantModal extends StatefulWidget {
  const _AssistantModal();

  @override
  State<_AssistantModal> createState() => _AssistantModalState();
}

class _AssistantModalState extends State<_AssistantModal> {
  bool _isListening = true;
  final String _text = 'Escuchando...';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.4,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Asistente de Voz',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: Text(
                _text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _ListeningIndicator(isListening: _isListening),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ),
              if (!_isListening)
                ElevatedButton(
                  onPressed: () => setState(() => _isListening = true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A1B9A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('REINTENTAR'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListeningIndicator extends StatelessWidget {
  final bool isListening;

  const _ListeningIndicator({required this.isListening});

  @override
  Widget build(BuildContext context) {
    if (!isListening) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (index) => Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            color: Color(0xFF6A1B9A),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 40, color: Colors.black87),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 20, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
