import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/app_check_info.dart';
import '../../services/firebase_service.dart';
import '../../services/offline_speech_service.dart';
import '../../services/voice_assistant_service.dart';
import '../widgets/assistant_button.dart';
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
      floatingActionButton: const AssistantFloatingButton(),
    );
  }
}

void showAssistantModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const AssistantModal(),
  );
}

class AssistantModal extends StatefulWidget {
  const AssistantModal({super.key});

  @override
  State<AssistantModal> createState() => _AssistantModalState();
}

class _AssistantModalState extends State<AssistantModal> {
  // Instancia única compartida: conserva el chat con Gemini entre aperturas del modal.
  final VoiceAssistantService _voiceService = VoiceAssistantService.instance;

  bool _isListening = false;
  bool _isProcessing = false;
  String _userText = '';
  String _assistantText = '';
  String _statusMessage = 'Inicializando micrófono...';

  // Voz en español sin conexión (modelo de reconocimiento en el dispositivo).
  bool _offlineVoiceMissing = false;
  bool _downloadingVoice = false;

  @override
  void initState() {
    super.initState();
    _initAndListen();
    _checkOfflineVoice();
  }

  Future<void> _checkOfflineVoice() async {
    final st = await OfflineSpeechService.status();
    if (!mounted) return;
    setState(() => _offlineVoiceMissing = st.supported && !st.hasSpanishInstalled);
  }

  Future<void> _downloadOfflineVoice() async {
    await _voiceService.stopListening();
    if (!mounted) return;
    setState(() {
      _downloadingVoice = true;
      _isListening = false;
      _statusMessage = 'Descargando la voz en español sin conexión... (necesita internet)';
    });
    final r = await OfflineSpeechService.downloadSpanish();
    if (!mounted) return;
    final installed = r == 'success' || r == 'already_installed';
    setState(() {
      _downloadingVoice = false;
      _offlineVoiceMissing = !installed;
      if (installed) {
        _statusMessage = 'Listo: ya puedo escucharte sin internet. Toca HABLAR DE NUEVO.';
      } else if (r == 'scheduled' || r == 'requested') {
        _statusMessage = 'La descarga quedó en curso. Déjala terminar con internet '
            '(puede pedir Wi-Fi) y vuelve a intentarlo en unos minutos.';
      } else if (r == 'unsupported') {
        _statusMessage = 'Este teléfono no permite descargar la voz sin conexión desde la app '
            '(requiere Android 13 o superior).';
      } else {
        _statusMessage = 'No se pudo descargar la voz ($r). Revisa tu conexión a internet '
            'e inténtalo de nuevo.';
      }
    });
    if (r == 'scheduled' || r == 'requested') {
      // Vuelve a revisar en un rato por si ya terminó.
      Future.delayed(const Duration(seconds: 30), _checkOfflineVoice);
    }
  }

  Future<void> _initAndListen() async {
    setState(() {
      _isListening = false;
      _isProcessing = false;
      _userText = '';
      _assistantText = '';
      _statusMessage = 'Inicializando servicio de voz...';
    });

    final bool success = await _voiceService.initialize(
      onError: (msg) {
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusMessage = _sttErrorMessage(msg);
            if (const {
              'error_language_unavailable',
              'error_language_not_supported',
              'error_network',
              'error_network_timeout',
            }.contains(msg)) {
              _offlineVoiceMissing = true;
            }
          });
        }
      },
    );

    if (!success) {
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusMessage = 'No se pudo iniciar el servicio de voz.';
        });
      }
      return;
    }

    _startListeningSession();
  }

  Future<void> _startListeningSession() async {
    if (!mounted) return;
    setState(() {
      _isListening = true;
      _isProcessing = false;
      _userText = '';
      _assistantText = '';
      _statusMessage = 'Te escucho... Habla ahora.';
    });

    await _voiceService.listen(
      duration: const Duration(seconds: 15),
      onResult: (recognizedWords, isFinal) {
        if (!mounted) return;
        setState(() {
          _userText = recognizedWords;
        });

        if (isFinal && recognizedWords.trim().isNotEmpty) {
          _handleFinalRecognizedSpeech(recognizedWords);
        }
      },
    );
  }

  Future<void> _handleFinalRecognizedSpeech(String text) async {
    await _voiceService.stopListening();
    if (!mounted) return;

    setState(() {
      _isListening = false;
      _isProcessing = true;
      _statusMessage = 'Procesando respuesta con Emki IA...';
    });

    final response = await _voiceService.processPrompt(text);

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _assistantText = response.textResponse;
      _statusMessage = response.action != AppVoiceAction.none
          ? 'Sección abierta. Asistente activo.'
          : 'Respuesta generada.';
    });

    if (response.action != AppVoiceAction.none) {
      _navigateToTargetSection(response.action, response.targetName);
    }
  }

  void _navigateToTargetSection(AppVoiceAction action, [String? targetName]) {
    if (!mounted) return;

    Widget targetScreen;
    switch (action) {
      case AppVoiceAction.openHome:
        // Cierra todo lo que haya encima (secciones y este modal) hasta el menú
        // principal. La voz sigue: dispose() del modal ya no corta el TTS.
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      case AppVoiceAction.openTremor:
        targetScreen = const TremorChartScreen();
        break;
      case AppVoiceAction.openMedication:
        targetScreen = const MedicationScreen();
        break;
      case AppVoiceAction.openHabits:
      case AppVoiceAction.openHabitsFood:
        targetScreen = const HabitsScreen(initialTabIndex: 0);
        break;
      case AppVoiceAction.openHabitsActivity:
        targetScreen = const HabitsScreen(initialTabIndex: 1);
        break;
      case AppVoiceAction.openCommunity:
        targetScreen = const CommunityScreen();
        break;
      case AppVoiceAction.openCommunityCompanions:
        targetScreen = const CommunityScreen(initialTabIndex: 0);
        break;
      case AppVoiceAction.openCommunityGroups:
        targetScreen = const CommunityScreen(initialTabIndex: 1);
        break;
      case AppVoiceAction.openCommunityLessons:
        targetScreen = const CommunityScreen(initialTabIndex: 2);
        break;
      case AppVoiceAction.openCompanionProfile:
        targetScreen = CommunityScreen(
          initialTabIndex: 0,
          companionName: targetName,
        );
        break;
      case AppVoiceAction.openCommunityGroup:
        targetScreen = CommunityScreen(
          initialTabIndex: 1,
          groupName: targetName,
        );
        break;
      case AppVoiceAction.openCommunityLesson:
        targetScreen = CommunityScreen(
          initialTabIndex: 2,
          lessonTitle: targetName,
        );
        break;
      case AppVoiceAction.togglePrivacyPrivate:
      case AppVoiceAction.togglePrivacyPublic:
        // Privacy toggle is executed inside processPrompt; no navigation needed
        return;
      case AppVoiceAction.openProfile:
        targetScreen = const ProfileScreen();
        break;
      case AppVoiceAction.none:
        return;
    }

    // Push the target screen without popping the assistant modal.
    // This allows the user to see the section underneath while the assistant
    // continues speaking and displaying its reply on top without cutting off.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => targetScreen),
    );
  }

  /// Mensaje claro según el error del reconocimiento de voz.
  String _sttErrorMessage(String code) {
    switch (code) {
      case 'error_permission':
      case 'error_insufficient_permissions':
        return 'Permiso de micrófono denegado. Actívalo en los ajustes del teléfono.';
      case 'error_server_disconnected':
        return 'El reconocimiento de voz del teléfono quedó ocupado. Cierra la app por '
            'completo y vuelve a abrirla; si sigue igual, reinicia el teléfono.';
      case 'error_language_unavailable':
      case 'error_language_not_supported':
      case 'error_network':
      case 'error_network_timeout':
        return 'Sin internet no puedo escucharte: falta la voz en español sin conexión. '
            'Conéctate a internet y toca DESCARGAR VOZ SIN CONEXIÓN.';
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'No alcancé a escucharte. Toca HABLAR DE NUEVO.';
      default:
        return 'Error de micrófono ($code). Toca HABLAR DE NUEVO.';
    }
  }

  /// Diagnóstico visible solo en compilaciones de depuración.
  Widget _buildDebugDiagnostics() {
    final String? error = _voiceService.lastGeminiError;
    final String origen = _assistantText.isEmpty
        ? '—'
        : (_voiceService.lastReplyFromGemini ? 'Gemini' : 'respaldo local');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Text(
            '${AppCheckInfo.summary}\n'
            'Modelo: ${_voiceService.modelName} · Vertex AI (global) · Respuesta: $origen',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.black45),
          ),
          if (error != null)
            Text(
              'Gemini error: $error',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Solo apaga el micrófono. La voz no se corta aquí para que termine la
    // frase al navegar (p. ej. "Listo, te llevo al inicio"); los botones
    // CERRAR y X ya llaman a stopSpeaking(). La instancia compartida sigue viva.
    _voiceService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: mediaQuery.size.height * 0.6,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF6A1B9A), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Asistente Emki Care',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6A1B9A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () {
                      _voiceService.stopListening();
                      _voiceService.stopSpeaking();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.purple, fontWeight: FontWeight.w500),
              ),
              if (kDebugMode) _buildDebugDiagnostics(),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_userText.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.person, size: 20, color: Colors.purple),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _userText,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_isProcessing)
                        const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(color: Color(0xFF6A1B9A)),
                        ),
                      if (_assistantText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.lightGreen.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.lightGreen.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.support_agent_rounded, size: 24, color: Colors.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _assistantText,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_isListening) _ListeningIndicator(isListening: _isListening),
              if (_downloadingVoice)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(color: Color(0xFF6A1B9A)),
                )
              else if (_offlineVoiceMissing && !_isListening && !_isProcessing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: _downloadOfflineVoice,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('DESCARGAR VOZ SIN CONEXIÓN'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF6A1B9A)),
                  ),
                ),
              const SizedBox(height: 12),
              // Botones compactos: el tema global usa letra 22 y padding grande
              // en ElevatedButton; aquí se reduce para que el texto quepa.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _voiceService.stopListening();
                        _voiceService.stopSpeaking();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('CERRAR', maxLines: 1),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 46),
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (!_isListening && !_isProcessing) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _startListeningSession,
                        icon: const Icon(Icons.mic, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('HABLAR DE NUEVO', maxLines: 1),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A1B9A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          minimumSize: const Size(0, 46),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
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
