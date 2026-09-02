import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../services/firebase_service.dart';
import '../../models/medication_task.dart';

class MedicationScreen extends StatefulWidget {
  const MedicationScreen({super.key});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week; // Iniciamos compacto (semana)

  final List<String> _predefinedMeds = ['Levo', 'Otros medicamentos'];
  String _selectedMed = 'Levo';
  final _nameController = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isRecurring = false;

  void _showAddMedDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Programar Medicamento',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.purple.shade900,
                  fontWeight: FontWeight.bold,
                ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedMed,
                  decoration: const InputDecoration(
                    labelText: 'Medicamento',
                    border: OutlineInputBorder(),
                  ),
                  items: _predefinedMeds.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setDialogState(() => _selectedMed = val!),
                ),
                if (_selectedMed == 'Otros medicamentos') ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del medicamento',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hora de la toma', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _selectedTime.format(context),
                      style: TextStyle(color: Colors.purple.shade700, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  onTap: () async {
                    final time = await showTimePicker(context: context, initialTime: _selectedTime);
                    if (time != null) setDialogState(() => _selectedTime = time);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('¿Se repite diariamente?'),
                  value: _isRecurring,
                  activeThumbColor: Colors.purple,
                  onChanged: (val) => setDialogState(() => _isRecurring = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 16)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = _selectedMed == 'Levo' ? 'Levo' : _nameController.text.trim();
                if (name.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor, ingresa el nombre del medicamento')),
                    );
                  }
                  return;
                }
                
                try {
                  await _firebaseService.addMedicationTask(name, _selectedDay, _selectedTime, _isRecurring);
                  if (!mounted) return;
                  
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Medicamento guardado con éxito'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A), // MORADO
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Guardar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(MedicationTask task) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar medicamento?'),
        content: Text('¿Estás seguro de que deseas eliminar "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _firebaseService.deleteMedicationTask(task.id);
                if (!mounted) return;
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (e) {
                if (!mounted) return;
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al eliminar: $e')),
                  );
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = isSameDay(_selectedDay, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Medicamentos',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade900,
              ),
        ),
        backgroundColor: Colors.purple.shade100,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        child: Column(
          children: [
            // Botón Agregar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: _showAddMedDialog,
                icon: const Icon(Icons.add_circle_outline, size: 28),
                label: const Text('AGREGAR MEDICAMENTO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightGreen.shade400,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 65),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
            ),

            // Título Hoy / Historial
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isToday ? 'Medicamentos de hoy' : 'Medicamentos del ${DateFormat('dd MMMM', 'es').format(_selectedDay)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800, 
                    color: Colors.purple.shade900,
                  ),
                ),
              ),
            ),

            // Lista de medicamentos
            Expanded(
              child: StreamBuilder<List<MedicationTask>>(
                stream: _firebaseService.getTasksForDate(_selectedDay),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tasks = snapshot.data ?? [];
                  if (tasks.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.medication_outlined, size: 80, color: Colors.purple.withValues(alpha: 0.2)),
                          const SizedBox(height: 10),
                          Text(
                            'No hay medicamentos programados',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black45),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _MedTaskTile(
                        task: task,
                        onToggle: (val) {
                          if (val != null) _firebaseService.updateTaskStatus(task.id, val);
                        },
                        onDelete: () => _confirmDelete(task),
                      );
                    },
                  );
                },
              ),
            ),

            // Calendario Expandible
            _buildExpandableCalendar(),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableCalendar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador de expansión
          GestureDetector(
            onTap: () {
              setState(() {
                _calendarFormat = _calendarFormat == CalendarFormat.week 
                    ? CalendarFormat.month 
                    : CalendarFormat.week;
              });
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.transparent,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(5)),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _calendarFormat == CalendarFormat.week ? 'VER CALENDARIO COMPLETO' : 'CONTRAER',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade300),
                  ),
                ],
              ),
            ),
          ),
          StreamBuilder<Set<DateTime>>(
            stream: _firebaseService.getDatesWithTasks(),
            builder: (context, snapshot) {
              final datesWithTasks = snapshot.data ?? {};
              return TableCalendar(
                locale: 'es_ES',
                firstDay: DateTime.utc(2024, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                rowHeight: 45,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() => _calendarFormat = format);
                },
                eventLoader: (day) {
                  final normalizedDay = DateTime(day.year, day.month, day.day);
                  return datesWithTasks.any((d) => isSameDay(d, normalizedDay)) ? [true] : [];
                },
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(color: Colors.purple.shade200, shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(color: const Color(0xFF6A1B9A), shape: BoxShape.circle),
                  markerDecoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                  markersMaxCount: 1,
                  defaultTextStyle: const TextStyle(fontWeight: FontWeight.w500),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false, // Ocultamos el botón por defecto para usar el nuestro
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _MedTaskTile extends StatelessWidget {
  final MedicationTask task;
  final ValueChanged<bool?> onToggle;
  final VoidCallback onDelete;

  const _MedTaskTile({required this.task, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm a').format(task.scheduledDateTime);
    final takenTimeStr = task.takenDateTime != null 
        ? DateFormat('hh:mm a').format(task.takenDateTime!) 
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(15, 5, 5, 5),
        leading: Checkbox(
          value: task.isTaken,
          onChanged: onToggle,
          activeColor: const Color(0xFF6A1B9A),
        ),
        title: Text(
          task.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: task.isTaken ? Colors.black38 : Colors.black87,
            decoration: task.isTaken ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Programado: $timeStr', style: Theme.of(context).textTheme.bodySmall),
            if (task.isTaken)
              Text('Tomado: $takenTimeStr', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
