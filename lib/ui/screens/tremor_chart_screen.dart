import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/tremor_provider.dart';
import '../../services/csv_capture_service.dart';

class TremorChartScreen extends StatelessWidget {
  const TremorChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tremorProvider = Provider.of<TremorProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Temblor'),
        backgroundColor: Colors.purple.shade100,
        actions: [
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
          _buildConnectionBadge(tremorProvider.connectionState),
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
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              _buildRealTimeCard(tremorProvider),
              const SizedBox(height: 20),
              _buildStatsGrid(tremorProvider),
              const SizedBox(height: 20),
              _buildCsvCaptureCard(tremorProvider),
              const SizedBox(height: 30),
              _buildWeeklyDemoSection(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => tremorProvider.retryConnection(),
        child: const Icon(Icons.refresh),
        backgroundColor: Colors.purple,
      ),
    );
  }

  Widget _buildConnectionBadge(BluetoothConnectionState state) {
    Color color;
    String text;
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

    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRealTimeCard(TremorProvider provider) {
    final data = provider.history;
    
    // Cálculo dinámico de escala
    double maxVal = 5.0;
    for (var s in data) {
      if (s.tremorAmp > maxVal) maxVal = s.tremorAmp;
    }
    maxVal = (maxVal * 1.2).ceilToDouble(); // Margen del 20%

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Velocidad de Rotación',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                ),
                if (provider.lastStatus?.tremorPresent ?? false)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
                    child: const Text('TEMBLOR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                  ),
              ],
            ),
            const SizedBox(height: 15),
            _buildClassificationBox(provider),
            const SizedBox(height: 15),
            SizedBox(
              height: 200,
              child: data.isEmpty
                  ? Center(
                      child: Text(
                        provider.connectionState == BluetoothConnectionState.connected
                            ? (provider.isStreaming ? "Esperando datos..." : "Transmisión pausada")
                            : "Reloj desconectado",
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: maxVal,
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(fontSize: 10)),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: true, border: Border.all(color: Colors.black12)),
                        lineBarsData: [
                          LineChartBarData(
                            spots: data.asMap().entries.map((e) {
                              return FlSpot(e.key.toDouble(), e.value.tremorAmp);
                            }).toList(),
                            isCurved: true,
                            color: Colors.redAccent,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.1)),
                          ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              provider.lastSample != null 
                ? "Última muestra: ${provider.lastSample!.tremorAmp.toStringAsFixed(2)} dps"
                : "Sin datos",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              'A mayor altura en la gráfica, más rápido y brusco es el temblor detectado.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassificationBox(TremorProvider provider) {
    final dps = provider.lastSample?.tremorAmp ?? 0.0;
    final classification = provider.getClassification(dps, provider.lastStatus);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: classification.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: classification.color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Icon(classification.icon, color: classification.color, size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classification.severity,
                  style: TextStyle(
                    color: classification.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  classification.type,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            "${dps.toStringAsFixed(1)} dps",
            style: TextStyle(
              color: classification.color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(TremorProvider provider) {
    final status = provider.lastStatus;
    final isConnected = provider.connectionState == BluetoothConnectionState.connected;
    final isCalibrating = isConnected && status == null && provider.lastSample != null;

    if (isCalibrating) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: const Column(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 15),
            Text(
              "Calibrando...",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            Text(
              "mantén el reloj quieto",
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
        ),
      );
    }

    String freqText = "--";
    if (status != null) {
      freqText = status.domFreq == 0 ? "—" : "${status.domFreq.toStringAsFixed(1)} Hz";
    }
    
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _buildStatItem("Frecuencia", freqText, Icons.waves, Colors.blue),
        _buildStatItem("Amplitud", "${status?.tremorAmp.toStringAsFixed(1) ?? '--'} dps", Icons.height, Colors.orange),
        _buildStatItem("Movimiento", "${status?.movement.toStringAsFixed(1) ?? '--'} dps", Icons.directions_run, Colors.green),
        _buildStatItem(
          "Episodio", 
          "${status?.episode ?? '--'} s", 
          Icons.timer, 
          Colors.red,
          tooltip: "Duración del temblor detectado en segundos",
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color, {String? tooltip}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Tooltip(
        message: tooltip ?? "",
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 5),
                  Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCsvCaptureCard(TremorProvider provider) {
    final status = provider.captureStatus;
    final isCapturing = status?.isCapturing ?? false;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.description, color: isCapturing ? Colors.red : Colors.blue),
                const SizedBox(width: 10),
                const Text(
                  'Captura RAWFIFO (MATLAB)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 15),
            if (isCapturing) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMiniStat("Recibidas", "${status?.received}"),
                  _buildMiniStat("Perdidas", "${status?.lost}", color: Colors.red),
                ],
              ),
              const SizedBox(height: 15),
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
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 15),
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
              const SizedBox(height: 15),
              const Divider(),
              const Text(
                "Última sesión guardada:",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
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
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyDemoSection() {
    // Mantengo esta sección como referencia histórica/demo solicitada en el original
    final List<double> demoData = [3.2, 4.5, 3.8, 7.2, 5.1, 4.2, 2.5];
    final List<String> days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Evolución del temblor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
            ),
            const Text('Últimos 7 días', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 30),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 10,
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < days.length) {
                            return Text(days[value.toInt()], style: const TextStyle(fontSize: 10));
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: demoData.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value,
                          color: e.value > 6 ? Colors.red.shade400 : Colors.lightGreen.shade400,
                          width: 12,
                          borderRadius: BorderRadius.circular(4),
                        )
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
