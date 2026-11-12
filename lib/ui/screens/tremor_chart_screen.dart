import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/tremor_provider.dart';
import '../../services/ble_service.dart' show WatchCandidate;
import '../../models/ble_device_data.dart';
import '../widgets/assistant_button.dart';
import 'debug_screen.dart';

class TremorChartScreen extends StatefulWidget {
  const TremorChartScreen({super.key});

  @override
  State<TremorChartScreen> createState() => _TremorChartScreenState();
}

class _TremorChartScreenState extends State<TremorChartScreen> {
  bool _showGyro = true; // true = Giroscopio (°/s), false = Acelerómetro (g)
  bool _showFiltered = true; // true = Filtrado 2.5-8 Hz, false = Crudo

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<TremorProvider>(context, listen: false);
      provider.setRawCardVisibility(true);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tremorProvider = Provider.of<TremorProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Temblor'),
        backgroundColor: Colors.purple.shade100,
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.purple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebugScreen()),
              );
            },
            tooltip: "Depuración (MATLAB)",
          ),
          IconButton(
            icon: Icon(
              tremorProvider.isRawUploadEnabled ? Icons.analytics : Icons.analytics_outlined,
              color: tremorProvider.isRawUploadEnabled ? Colors.green : Colors.grey,
            ),
            onPressed: () => tremorProvider.toggleRawUpload(),
            tooltip: tremorProvider.isRawUploadEnabled ? "Desactivar Datos Crudos" : "Activar Datos Crudos",
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload, color: Colors.purple),
            onPressed: () async {
              await tremorProvider.uploadSummary();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sincronización con la nube completada')),
                );
              }
            },
            tooltip: "Sincronizar con Firebase",
          ),
          IconButton(
            icon: Icon(
              tremorProvider.isStreaming ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: tremorProvider.connectionState == BluetoothConnectionState.connected 
                  ? Colors.purple 
                  : Colors.grey,
            ),
            onPressed: tremorProvider.connectionState == BluetoothConnectionState.connected
                ? () => tremorProvider.toggleStreaming()
                : null,
            tooltip: tremorProvider.isStreaming ? "Pausar Transmisión" : "Reanudar Transmisión",
          ),
          _buildConnectionBadge(tremorProvider.connectionState, chargeMode: tremorProvider.chargeMode),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (tremorProvider.isFirmwareOutdated) ...[
                _buildFirmwareWarningBanner(),
                const SizedBox(height: 16),
              ],
              if (tremorProvider.chargeMode) ...[
                _buildChargeModeBanner(tremorProvider),
                const SizedBox(height: 16),
              ] else ...[
                _buildWatchSelectorRow(tremorProvider),
                const SizedBox(height: 8),
                _buildDeviceStatusRow(tremorProvider),
                const SizedBox(height: 12),
              ],
              _buildMainCurrentStateCard(tremorProvider),
              const SizedBox(height: 12),
              _buildWhyCard(tremorProvider),
              const SizedBox(height: 16),
              _buildRawSignalCard(tremorProvider),
              const SizedBox(height: 16),
              _buildTimelineCard(tremorProvider),
              const SizedBox(height: 16),
              _buildSessionCountersSection(tremorProvider),
              const SizedBox(height: 16),
              _buildCsvCaptureCard(tremorProvider),
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const AssistantFloatingButton(),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'refresh_ble_btn',
            onPressed: tremorProvider.chargeMode ? null : () => tremorProvider.retryConnection(),
            backgroundColor: tremorProvider.chargeMode ? Colors.grey : Colors.purple,
            child: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade800),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Actualiza el firmware del reloj (versión < 2.0.0 detectada).",
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ESTADO DEL DISPOSITIVO: batería + botón "Modo carga"
  Widget _buildDeviceStatusRow(TremorProvider provider) {
    final isConnected = provider.connectionState == BluetoothConnectionState.connected;
    // Solo cuando la conexión terminó de armarse (si no, 0xC0 no se envía).
    final canEnter = isConnected && provider.watchReady && !provider.enteringChargeMode;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              provider.batteryPercent == null ? Icons.battery_unknown : Icons.battery_std,
              color: Colors.purple,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                provider.batteryDisplay,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton.icon(
              onPressed: canEnter ? () => _confirmChargeMode(provider) : null,
              icon: provider.enteringChargeMode
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.battery_charging_full),
              label: const Text('Modo carga'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.purple),
            ),
          ],
        ),
      ),
    );
  }

  // SELECTOR DE RELOJ: muestra a qué reloj está conectada la app y permite cambiarlo.
  Widget _buildWatchSelectorRow(TremorProvider provider) {
    final watchId = provider.connectedWatchId ?? provider.preferredWatchId;
    final String label;
    if (watchId == null) {
      label = 'Reloj: automático (el primero que encuentre)';
    } else {
      final short = watchId.length >= 5 ? watchId.substring(watchId.length - 5) : watchId;
      label = 'Reloj: …$short${provider.connectedWatchId == null ? ' (desconectado)' : ''}';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.watch, color: Colors.purple, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => _showWatchPicker(provider),
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Cambiar'),
              style: TextButton.styleFrom(foregroundColor: Colors.purple),
            ),
          ],
        ),
      ),
    );
  }

  /// Hoja inferior con los relojes cercanos para elegir a cuál conectarse.
  Future<void> _showWatchPicker(TremorProvider provider) async {
    List<WatchCandidate>? watches;
    bool scanning = false;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> scan() async {
            setSheetState(() => scanning = true);
            final result = await provider.scanWatches();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              watches = result;
              scanning = false;
            });
          }

          if (watches == null && !scanning) {
            Future.microtask(scan);
          }

          String signal(int rssi) {
            if (rssi == 0) return 'conectado';
            if (rssi >= -60) return 'señal fuerte ($rssi dBm)';
            if (rssi >= -80) return 'señal media ($rssi dBm)';
            return 'señal débil ($rssi dBm)';
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Elegir reloj',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Mantén encendidos los relojes y acércalos al teléfono. El elegido queda guardado.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  if (scanning)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: Colors.purple)),
                    )
                  else if (watches != null && watches!.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No encontré relojes. Verifica que estén encendidos y con Bluetooth activo.'),
                    )
                  else if (watches != null)
                    ...watches!.map((w) {
                      final isPreferred = w.id == provider.preferredWatchId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          w.isConnected ? Icons.bluetooth_connected : Icons.watch,
                          color: w.isConnected ? Colors.green : Colors.purple,
                        ),
                        title: Text('${w.name}  ·  …${w.shortId}'),
                        subtitle: Text(signal(w.rssi)),
                        trailing: isPreferred || w.isConnected
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          if (!w.isConnected) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Conectando al reloj …${w.shortId}')),
                            );
                          }
                          // Si ya está conectado, solo queda guardado como el elegido.
                          await provider.selectWatch(w.id);
                        },
                      );
                    }),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: scanning ? null : scan,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Buscar de nuevo'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmChargeMode(TremorProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.battery_charging_full, color: Colors.purple),
        title: const Text('Modo carga'),
        content: const Text(
          'El reloj dejará de enviar datos y se apagará para cargar más rápido. '
          'Para encenderlo, mantén presionado su botón 2 segundos '
          '(o se encenderá solo en 3 horas).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final error = await provider.enterChargeMode();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Widget _buildChargeModeBanner(TremorProvider provider) {
    final elapsed = provider.chargeModeElapsed;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final elapsedStr = h > 0 ? '$h:$m:$s' : '$m:$s';

    return Card(
      elevation: 4,
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.amber.shade700),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.battery_charging_full, color: Colors.amber.shade800, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reloj en modo carga',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                      Text(
                        'Tiempo transcurrido: $elapsedStr',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Buscando el reloj cada minuto. Al encenderse se reconectará solo.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await provider.finishCharging();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mantén presionado el botón del reloj 2 segundos para encenderlo'),
                      duration: Duration(seconds: 6),
                    ),
                  );
                },
                icon: const Icon(Icons.check),
                label: const Text('Terminé de cargar'),
                style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionBadge(BluetoothConnectionState state, {bool chargeMode = false}) {
    Color color;
    String text;
    if (chargeMode) {
      color = Colors.amber.shade800;
      text = "Modo carga";
      return _badgeContainer(color, text);
    }
    switch (state) {
      case BluetoothConnectionState.connected:
        color = Colors.green;
        text = "Conectado";
        break;
      case BluetoothConnectionState.connecting:
        color = Colors.orange;
        text = "Conectando...";
        break;
      default:
        color = Colors.red;
        text = "Desconectado";
    }

    return _badgeContainer(color, text);
  }

  Widget _badgeContainer(Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // 1. TARJETA PRINCIPAL DE ESTADO ACTUAL
  Widget _buildMainCurrentStateCard(TremorProvider provider) {
    // 1. Antes del PRIMER resultado desde que se abrió la app:
    if (provider.ultimaClase == null && provider.lastStatus == null) {
      final progress = provider.analyzingProgress;
      return Card(
        key: const ValueKey('analizando_inicial'),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF9E9E9E),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.query_stats, color: Colors.white, size: 28),
                  SizedBox(width: 10),
                  Text(
                    "Analizando…",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Mantén el reloj quieto",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: progress == -1.0
                    ? const LinearProgressIndicator(
                        minHeight: 8,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      )
                    : LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Muestra SIEMPRE la última clase válida recibida
    final clase = provider.ultimaClase ?? (provider.lastStatus?.tremorClass ?? TremorClass.sinTemblor);
    final estado = clase.toEstadoTemblor();
    final isConfirmed = provider.ultimoConfirmado ?? (provider.lastStatus?.tremorPresent ?? false);
    final isDisconnected = provider.connectionState != BluetoothConnectionState.connected;

    final elapsedSeconds = provider.ultimaActualizacion == null
        ? 0
        : DateTime.now().difference(provider.ultimaActualizacion!).inSeconds;

    final isStale = isDisconnected;
    final isUpdating = !isDisconnected && elapsedSeconds > 5;

    Widget cardChild;

    switch (estado) {
      case EstadoTemblor.analizando:
        cardChild = const SizedBox.shrink();
        break;

      case EstadoTemblor.sinTemblor:
        cardChild = _buildStatusCardContainer(
          key: const ValueKey('sinTemblor'),
          bgColor: const Color(0xFFE0E0E0),
          textColor: Colors.black87,
          title: "SIN TEMBLOR",
          subtitle: "Reposo o movimiento habitual sin patrones parkinsonianos",
          badge: (provider.lastStatus?.detected ?? false) ? "Detectando…" : "Normal",
          badgeColor: (provider.lastStatus?.detected ?? false) ? Colors.amber.shade800 : Colors.black12,
          details: [
            _buildMetricItem(
              label: "Movimiento",
              value: "${(provider.lastStatus?.movement ?? 0.0).toStringAsFixed(1)} °/s",
              icon: Icons.directions_walk,
              color: Colors.black87,
            )
          ],
        );
        break;

      case EstadoTemblor.voluntario:
        cardChild = _buildStatusCardContainer(
          key: const ValueKey('voluntario'),
          bgColor: const Color(0xFF1E5AC8),
          textColor: Colors.white,
          title: "MOVIMIENTO VOLUNTARIO",
          subtitle: "Movimiento rápido o voluntario del usuario",
          badge: (provider.lastStatus?.detected ?? false) ? "Detectando…" : "Voluntario",
          badgeColor: Colors.white24,
          details: [
            _buildMetricItem(
              label: "Velocidad",
              value: "${(provider.lastStatus?.movement ?? 0.0).toStringAsFixed(1)} °/s",
              icon: Icons.directions_run,
              color: Colors.white,
            )
          ],
        );
        break;

      case EstadoTemblor.leve:
      case EstadoTemblor.moderado:
      case EstadoTemblor.grave:
        final baseColor = _getEstadoColor(estado);
        final cardBgColor = isConfirmed ? baseColor : baseColor.withOpacity(0.5);

        cardChild = Card(
          key: ValueKey('temblor_${estado.nameEs}_$isConfirmed'),
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'TEMBLOR PARKINSONIANO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (!isConfirmed && !isStale)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'detectando…',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Banner Severidad
                Text(
                  estado.nameEs,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  estado.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 16),

                // Métricas
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceAround,
                  children: [
                    _buildMetricItem(
                      label: "Ángulo (Principal)",
                      value: provider.validAngDegDisplay,
                      icon: Icons.rotate_right,
                      color: Colors.white,
                      isPrimary: true,
                    ),
                    _buildMetricItem(
                      label: "Desplazamiento",
                      value: provider.validDesplazDisplay,
                      icon: Icons.straighten,
                      color: Colors.white,
                    ),
                    _buildMetricItem(
                      label: "Frecuencia",
                      value: provider.validDomFreqDisplay,
                      icon: Icons.waves,
                      color: Colors.white,
                    ),
                    _buildMetricItem(
                      label: "Velocidad",
                      value: "${(provider.lastStatus?.tremorAmp ?? 0.0).toStringAsFixed(1)} °/s",
                      icon: Icons.speed,
                      color: Colors.white,
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  iconColor: Colors.white,
                  collapsedIconColor: Colors.white,
                  title: const Text(
                    "¿Cómo se clasifica?",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("• LEVE: < 1.5° (≈ < 0.8 cm)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                          Text("• MODERADO: 1.5° - 4.5° (≈ 0.8 - 2.4 cm)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                          Text("• GRAVE: >= 4.5° (≈ >= 2.4 cm)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                          SizedBox(height: 4),
                          Text(
                            "Escala calibrada con el banco robótico y con temblor imitado. Los centímetros son una estimación del movimiento de los dedos (15 cm desde la muñeca).",
                            style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        break;
    }

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: AnimatedOpacity(
            key: ValueKey('opacity_${isStale}_${clase.name}'),
            duration: const Duration(milliseconds: 250),
            opacity: isStale ? 0.60 : 1.0,
            child: cardChild,
          ),
        ),
        if (isStale && provider.chargeMode) ...[
          const SizedBox(height: 6),
          const Text(
            "Último dato antes del modo carga",
            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ] else if (isStale) ...[
          const SizedBox(height: 6),
          Text(
            "Reconectando… · último dato hace $elapsedSeconds s",
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ] else if (isUpdating) ...[
          const SizedBox(height: 6),
          const Text(
            "Actualizando…",
            style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }

  Color _getEstadoColor(EstadoTemblor estado) {
    switch (estado) {
      case EstadoTemblor.analizando:
        return const Color(0xFF9E9E9E);
      case EstadoTemblor.sinTemblor:
        return const Color(0xFF2E7D32);
      case EstadoTemblor.voluntario:
        return const Color(0xFF1E5AC8);
      case EstadoTemblor.leve:
        return const Color(0xFF2E7D32);
      case EstadoTemblor.moderado:
        return const Color(0xFFD27800);
      case EstadoTemblor.grave:
        return const Color(0xFFC81414);
    }
  }

  // PANEL ¿POR QUÉ? (PASO 5)
  Widget _buildWhyCard(TremorProvider provider) {
    final diag = provider.lastDiag;
    if (diag == null) {
      return const SizedBox.shrink(); // Ocultar automáticamente si DIAG no está disponible
    }

    String explanationText = "";
    if (diag.ruta == 1) {
      explanationText =
          "Detectado por REGULARIDAD: pico estrecho (σ = ${diag.sigmaMin.toStringAsFixed(2)} Hz < 0.40) en ${diag.ejesActivos} ejes.";
    } else if (diag.ruta == 2) {
      explanationText =
          "Detectado por GIRO EN UN SOLO EJE: linealidad ${(diag.lin * 100).toStringAsFixed(1)} % ≥ 95 %, energía en banda ${diag.prel3Pct} % ≥ 65 %, amplitud ${diag.rmsPc.toStringAsFixed(1)} °/s ≥ 45.";
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        title: const Text(
          "¿Por qué?",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
        childrenPadding: const EdgeInsets.all(16.0),
        children: [
          if (diag.ruta == 1 || diag.ruta == 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                explanationText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
            )
          else ...[
            const Text(
              "Checklist de Criterios de Detección:",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildChecklistItem(
              label: "Ruta 1 - Regularidad (σ < 0.40 Hz):",
              passed: diag.sigmaMin < 0.40,
              detail: "σ = ${diag.sigmaMin.toStringAsFixed(2)} Hz",
            ),
            _buildChecklistItem(
              label: "Ruta 2 - Linealidad (≥ 95 %):",
              passed: diag.lin >= 0.95,
              detail: "${(diag.lin * 100).toStringAsFixed(1)} %",
            ),
            _buildChecklistItem(
              label: "Ruta 2 - Energía en banda (≥ 65 %):",
              passed: diag.prel3Pct >= 65,
              detail: "${diag.prel3Pct} %",
            ),
            _buildChecklistItem(
              label: "Ruta 2 - Amplitud (≥ 45 °/s):",
              passed: diag.rmsPc >= 45.0,
              detail: "${diag.rmsPc.toStringAsFixed(1)} °/s",
            ),
            _buildChecklistItem(
              label: "Compuerta - Energía voluntaria (< 30 %):",
              passed: diag.vol110Pct < 30,
              detail: "${diag.vol110Pct} %",
            ),
            _buildChecklistItem(
              label: "Rotación de muñeca:",
              passed: diag.rotacional,
              detail: diag.rotacional ? "sí" : "no",
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Energía Voluntaria (1–2.5 Hz)",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${diag.vol110Pct} % (Límite < 30 %)",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: diag.vol110Pct >= 30 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (diag.vol110Pct / 100.0).clamp(0.0, 1.0),
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        diag.vol110Pct >= 30 ? Colors.red : Colors.green,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final markPosition = constraints.maxWidth * 0.30;
                        return Stack(
                          children: [
                            Positioned(
                              left: markPosition,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 3,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("0 %", style: TextStyle(fontSize: 9, color: Colors.grey)),
                  Text("Límite 30 %", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87)),
                  Text("100 %", style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItem({
    required String label,
    required bool passed,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                size: 15,
                color: passed ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ],
          ),
          Text(
            detail,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: passed ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCardContainer({
    required Key key,
    required Color bgColor,
    required Color textColor,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required List<Widget> details,
  }) {
    return Card(
      key: key,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.left,
              style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.9)),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: details,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isPrimary = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isPrimary ? 15 : 13, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: isPrimary ? 11 : 10, color: Colors.white70)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isPrimary ? 17 : 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      key: key,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(icon, size: 44, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // 2. NUEVA TARJETA "SEÑAL POR EJE"
  Widget _buildRawSignalCard(TremorProvider provider) {
    final status = provider.lastStatus;
    Color borderColor = Colors.grey.shade300;
    if (status != null) {
      if (status.isAnalyzing) {
        borderColor = const Color(0xFF9E9E9E);
      } else {
        switch (status.tremorClass) {
          case TremorClass.leve:
            borderColor = const Color(0xFF2E7D32);
            break;
          case TremorClass.moderado:
            borderColor = const Color(0xFFD27800);
            break;
          case TremorClass.grave:
            borderColor = const Color(0xFFC81414);
            break;
          default:
            borderColor = Colors.grey.shade300;
        }
      }
    }

    final rawBuffer = provider.rawAxisBuffer;
    final filteredG = provider.filteredGyroBuffer;
    final filteredA = provider.filteredAccelBuffer;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Señal por eje (10 s)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
                if (status?.isAnalyzing ?? false)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Analizando…', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  )
                else
                  const Text(
                    '50 Hz',
                    style: TextStyle(fontSize: 11, color: Colors.black45),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: true, label: Text('Giro (°/s)', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: false, label: Text('Accel (g)', style: TextStyle(fontSize: 10))),
                  ],
                  selected: {_showGyro},
                  onSelectionChanged: (set) => setState(() => _showGyro = set.first),
                ),
                SegmentedButton<bool>(
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Crudo', style: TextStyle(fontSize: 10))),
                    ButtonSegment(value: true, label: Text('Filtrado', style: TextStyle(fontSize: 10))),
                  ],
                  selected: {_showFiltered},
                  onSelectionChanged: (set) => setState(() => _showFiltered = set.first),
                ),
              ],
            ),

            const SizedBox(height: 15),

            SizedBox(
              height: 180,
              child: rawBuffer.isEmpty
                  ? const Center(
                      child: Text('Esperando datos RAW...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: const FlTitlesData(
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35)),
                        ),
                        borderData: FlBorderData(show: true, border: Border.all(color: Colors.black12)),
                        lineBarsData: [
                          LineChartBarData(
                            spots: rawBuffer.asMap().entries.map((e) {
                              final idx = e.key;
                              double val;
                              if (_showGyro) {
                                val = _showFiltered ? filteredG[idx].x : e.value.gxDps;
                              } else {
                                val = _showFiltered ? filteredA[idx].x : e.value.axG;
                              }
                              return FlSpot(idx.toDouble(), val);
                            }).toList(),
                            isCurved: false,
                            color: Colors.red,
                            barWidth: 1.5,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: rawBuffer.asMap().entries.map((e) {
                              final idx = e.key;
                              double val;
                              if (_showGyro) {
                                val = _showFiltered ? filteredG[idx].y : e.value.gyDps;
                              } else {
                                val = _showFiltered ? filteredA[idx].y : e.value.ayG;
                              }
                              return FlSpot(idx.toDouble(), val);
                            }).toList(),
                            isCurved: false,
                            color: Colors.green,
                            barWidth: 1.5,
                            dotData: const FlDotData(show: false),
                          ),
                          LineChartBarData(
                            spots: rawBuffer.asMap().entries.map((e) {
                              final idx = e.key;
                              double val;
                              if (_showGyro) {
                                val = _showFiltered ? filteredG[idx].z : e.value.gzDps;
                              } else {
                                val = _showFiltered ? filteredA[idx].z : e.value.azG;
                              }
                              return FlSpot(idx.toDouble(), val);
                            }).toList(),
                            isCurved: false,
                            color: Colors.blue,
                            barWidth: 1.5,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAxisLegend('Eje X', Colors.red),
                const SizedBox(width: 16),
                _buildAxisLegend('Eje Y', Colors.green),
                const SizedBox(width: 16),
                _buildAxisLegend('Eje Z', Colors.blue),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
      ],
    );
  }

  // 3. LÍNEA DE TIEMPO (CON SOPORTE PARA ANALIZANDO)
  Widget _buildTimelineCard(TremorProvider provider) {
    final timeline = provider.timeline;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Línea de Tiempo (2 minutos)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
                Text(
                  '${(timeline.length * 0.5).toStringAsFixed(0)} s / 120 s',
                  style: const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (timeline.isEmpty)
              const SizedBox(
                height: 50,
                child: Center(
                  child: Text('Sin historial acumulado', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              )
            else
              SizedBox(
                height: 55,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: timeline.map((st) {
                    final color = st.isAnalyzing ? const Color(0xFF9E9E9E) : _getTremorClassColor(st.tremorClass);
                    final isConfirmed = st.tremorPresent && !st.isAnalyzing;

                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        child: Column(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: isConfirmed ? Colors.red : Colors.transparent,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                _buildTimelineLegendItem('ANALIZANDO', const Color(0xFF9E9E9E)),
                _buildTimelineLegendItem('SIN TEMBLOR', const Color(0xFFE0E0E0)),
                _buildTimelineLegendItem('LEVE', const Color(0xFF2E7D32)),
                _buildTimelineLegendItem('MODERADO', const Color(0xFFD27800)),
                _buildTimelineLegendItem('GRAVE', const Color(0xFFC81414)),
                _buildTimelineLegendItem('VOLUNTARIO', const Color(0xFF1E5AC8)),
                _buildTimelineLegendItem('CONFIRMADO', Colors.red, isTopBar: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineLegendItem(String label, Color color, {bool isTopBar = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: isTopBar ? 4 : 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black54),
        ),
      ],
    );
  }

  // 4. ESTADÍSTICAS DE LA SESIÓN (DONA EXCLUSIVA PARA TEMBLOR LEVE/MODERADO/GRAVE)
  Widget _buildSessionCountersSection(TremorProvider provider) {
    final sinTemblorSec = provider.sessionSinTemblorCount * 0.5;
    final leveSec = provider.sessionLeveCount * 0.5;
    final modSec = provider.sessionModeradoCount * 0.5;
    final graveSec = provider.sessionGraveCount * 0.5;
    final volSec = provider.sessionVoluntarioCount * 0.5;

    final tremorTotalSec = leveSec + modSec + graveSec;
    final totalSessionSec = sinTemblorSec + tremorTotalSec + volSec;

    final tremorPct = totalSessionSec > 0 ? (tremorTotalSec / totalSessionSec * 100) : 0.0;

    final status = provider.lastStatus;
    final dutyPct = status?.duty ?? 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estadísticas de la Sesión',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.purple),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: tremorTotalSec == 0
                      ? Container(
                          decoration: const BoxDecoration(
                            color: Colors.black12,
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'Sin temblor en la sesión',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 9, color: Colors.black54, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                      : PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 24,
                            sections: [
                              if (leveSec > 0)
                                PieChartSectionData(
                                  color: const Color(0xFF2E7D32),
                                  value: leveSec,
                                  title: '',
                                  radius: 18,
                                ),
                              if (modSec > 0)
                                PieChartSectionData(
                                  color: const Color(0xFFD27800),
                                  value: modSec,
                                  title: '',
                                  radius: 18,
                                ),
                              if (graveSec > 0)
                                PieChartSectionData(
                                  color: const Color(0xFFC81414),
                                  value: graveSec,
                                  title: '',
                                  radius: 18,
                                ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    children: [
                      _buildSessionCounterRow('LEVE', _formatSeconds(leveSec), const Color(0xFF2E7D32)),
                      _buildSessionCounterRow('MODERADO', _formatSeconds(modSec), const Color(0xFFD27800)),
                      _buildSessionCounterRow('GRAVE', _formatSeconds(graveSec), const Color(0xFFC81414)),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(height: 20),

            Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _buildSimpleSummaryTag('Sin temblor:', _formatSeconds(sinTemblorSec), const Color(0xFFE0E0E0)),
                _buildSimpleSummaryTag('Voluntario:', _formatSeconds(volSec), const Color(0xFF1E5AC8)),
              ],
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Tiempo con temblor: ${tremorPct.toStringAsFixed(1)}% de la sesión',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryBadge('Duty Cycle', '$dutyPct%', Icons.pie_chart_outline, Colors.teal),
                _buildSummaryBadge('Episodios', '${provider.episodeCount}', Icons.countertops, Colors.redAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleSummaryTag(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildSessionCounterRow(String label, String timeStr, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
          Text(timeStr, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Colors.black54)),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatSeconds(double seconds) {
    final totalSec = seconds.toInt();
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }

  Widget _buildCsvCaptureCard(TremorProvider provider) {
    final status = provider.captureStatus;
    final isCapturing = status?.isCapturing ?? false;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: isCapturing ? Colors.red : Colors.blue),
                const SizedBox(width: 10),
                const Text(
                  'Captura RAWFIFO (MATLAB)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isCapturing) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniStat("Recibidas", "${status?.received}"),
                  _buildMiniStat("Perdidas", "${status?.lost}", color: Colors.red),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => provider.stopCsvCapture(),
                  icon: const Icon(Icons.stop),
                  label: const Text("DETENER CAPTURA Y EXPORTAR"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ] else ...[
              const Text(
                "Inicia una sesión para generar archivos CSV compatibles con MATLAB.",
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: provider.connectionState == BluetoothConnectionState.connected
                      ? () => provider.startCsvCapture()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("INICIAR NUEVA CAPTURA"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            if (status != null && !isCapturing && status.csvPath != null) ...[
              const SizedBox(height: 10),
              const Divider(),
              const Text(
                "Última sesión guardada:",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status.csvPath!.split('/').last,
                      style: const TextStyle(fontSize: 11, color: Colors.black45),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.share, size: 20, color: Colors.purple),
                    onPressed: () {
                      final files = [XFile(status.csvPath!)];
                      if (status.gapPath != null) files.add(XFile(status.gapPath!));
                      Share.shareXFiles(files, text: 'Datos IMU ParkinsonWatch');
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Color _getTremorClassColor(TremorClass tremorClass) {
    switch (tremorClass) {
      case TremorClass.sinTemblor:
        return const Color(0xFFE0E0E0); // Gris claro
      case TremorClass.leve:
        return const Color(0xFF2E7D32); // Verde
      case TremorClass.moderado:
        return const Color(0xFFD27800); // Naranja
      case TremorClass.grave:
        return const Color(0xFFC81414); // Rojo
      case TremorClass.voluntario:
        return const Color(0xFF1E5AC8); // Azul
    }
  }
}
