import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/medication_reminder.dart';
import '../../services/firebase_service.dart';
import '../../services/reminder_service.dart';

String _fmtTime(TimeOfDay t) {
  final h12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h12:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'a. m.' : 'p. m.'}';
}

int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Lista de recordatorios de medicamentos (horas del día, días de la semana
/// opcionales y fecha de fin opcional). Cada toma genera una notificación con
/// el botón "Ya la tomé" y un reaviso a los 15 minutos.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final FirebaseService _firebase = FirebaseService();
  bool? _notificationsEnabled;

  @override
  void initState() {
    super.initState();
    _checkNotifications();
  }

  Future<void> _checkNotifications() async {
    final enabled = await ReminderService.instance.notificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _enableNotifications() async {
    await ReminderService.instance.requestPermissions();
    await _checkNotifications();
  }

  Future<void> _openEditor([MedicationReminder? reminder]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReminderEditorScreen(reminder: reminder)),
    );
    _checkNotifications();
  }

  Future<void> _toggleActive(MedicationReminder r, bool active) async {
    await _firebase.setReminderActive(r.id, active);
    if (!active) await _firebase.deleteFutureDoseTasks(r.id);
  }

  Future<void> _confirmDelete(MedicationReminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar recordatorio?'),
        content: Text('Se eliminarán los avisos futuros de "${r.name}". Las tomas ya registradas se conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await _firebase.deleteReminder(r.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Recordatorios',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade900,
              ),
        ),
        backgroundColor: Colors.purple.shade100,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Nuevo recordatorio'),
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
            if (_notificationsEnabled == false)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_off, color: Colors.amber.shade900),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Las notificaciones están desactivadas: no te llegarán los avisos.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: _enableNotifications, child: const Text('Activar')),
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<List<MedicationReminder>>(
                stream: _firebase.streamReminders(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final reminders = snapshot.data!;
                  if (reminders.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.alarm_add, size: 80, color: Colors.purple.withValues(alpha: 0.25)),
                            const SizedBox(height: 12),
                            const Text(
                              'Aún no tienes recordatorios.\nToca "Nuevo recordatorio" para programar a qué horas '
                              'debes tomar cada medicamento.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: reminders.length,
                    itemBuilder: (context, i) => _ReminderCard(
                      reminder: reminders[i],
                      onTap: () => _openEditor(reminders[i]),
                      onToggle: (v) => _toggleActive(reminders[i], v),
                      onDelete: () => _confirmDelete(reminders[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final MedicationReminder reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _ReminderCard({
    required this.reminder,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final ended = r.endDate != null &&
        DateTime(r.endDate!.year, r.endDate!.month, r.endDate!.day).isBefore(
          DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
        );
    final until = r.endDate == null
        ? 'Sin fecha de fin'
        : (ended ? 'Terminó el ' : 'Hasta el ') + DateFormat("d 'de' MMMM", 'es').format(r.endDate!);

    return Opacity(
      opacity: r.active && !ended ? 1 : 0.55,
      child: Card(
        elevation: 3,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(Icons.medication, color: Colors.purple.shade400, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.dose != null ? '${r.name} · ${r.dose}' : r.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: r.times
                            .map((t) => Chip(
                                  label: Text(_fmtTime(t), style: const TextStyle(fontSize: 13)),
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: Colors.purple.shade50,
                                  side: BorderSide(color: Colors.purple.shade100),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      Text('${r.weekdaysLabel} · $until',
                          style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Switch(value: r.active, activeThumbColor: Colors.purple, onChanged: onToggle),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Crear o editar un recordatorio.
class ReminderEditorScreen extends StatefulWidget {
  final MedicationReminder? reminder;

  /// Nombre del medicamento ya escrito (p. ej. cuando lo pide Emki por voz).
  final String? initialName;

  /// Recordatorio NUEVO prellenado (horas, días, fecha de fin) dictado a Emki.
  final MedicationReminder? draft;
  const ReminderEditorScreen({super.key, this.reminder, this.initialName, this.draft});

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  final FirebaseService _firebase = FirebaseService();
  late final TextEditingController _name;
  late final TextEditingController _dose;
  late List<TimeOfDay> _times;
  late Set<int> _weekdays; // vacío = todos los días
  late bool _specificDays;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    // Editar uno existente, o crear uno nuevo (vacío o prellenado por voz).
    final r = widget.reminder ?? widget.draft;
    _name = TextEditingController(
      text: (r?.name.isNotEmpty ?? false) ? r!.name : (widget.initialName ?? ''),
    );
    _dose = TextEditingController(text: r?.dose ?? '');
    _times = [...?r?.times];
    _weekdays = {...?r?.weekdays};
    _specificDays = _weekdays.isNotEmpty && _weekdays.length < 7;
    final today = DateTime.now();
    _startDate = r?.startDate ?? DateTime(today.year, today.month, today.day);
    _endDate = r?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times.isEmpty ? const TimeOfDay(hour: 8, minute: 0) : _times.last,
      helpText: 'Hora de la toma',
    );
    if (picked == null) return;
    if (_times.any((t) => _minutes(t) == _minutes(picked))) return;
    setState(() => _times = [..._times, picked]..sort((a, b) => _minutes(a).compareTo(_minutes(b))));
  }

  Future<DateTime?> _pickDate(DateTime initial, {DateTime? first}) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first ?? DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 730)),
        helpText: 'Elige la fecha',
      );

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack('Escribe el nombre del medicamento.');
    if (_times.isEmpty) return _snack('Agrega al menos una hora de toma.');
    if (_specificDays && _weekdays.isEmpty) return _snack('Elige al menos un día de la semana.');
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      return _snack('La fecha de fin no puede ser anterior a la de inicio.');
    }

    setState(() => _saving = true);
    try {
      final granted = await ReminderService.instance.requestPermissions();
      final existing = widget.reminder;
      if (existing != null) {
        // Cambiaron horas o días: se borran las tomas futuras viejas y el
        // servicio crea las nuevas al reprogramar.
        await _firebase.deleteFutureDoseTasks(existing.id);
      }
      await _firebase.saveReminder(MedicationReminder(
        id: existing?.id ?? '',
        name: name,
        dose: _dose.text.trim().isEmpty ? null : _dose.text.trim(),
        times: _times,
        weekdays: _specificDays ? (_weekdays.toList()..sort()) : const [],
        startDate: _startDate,
        endDate: _endDate,
        active: existing?.active ?? true,
      ));
      if (!mounted) return;
      _snack(granted
          ? 'Recordatorio guardado. Te avisaré a cada hora.'
          : 'Recordatorio guardado, pero las notificaciones están desactivadas.');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat("d 'de' MMMM 'de' y", 'es');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reminder == null ? 'Nuevo recordatorio' : 'Editar recordatorio'),
        backgroundColor: Colors.purple.shade100,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Medicamento',
              hintText: 'Ej.: Levodopa',
              prefixIcon: Icon(Icons.medication),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dose,
            decoration: const InputDecoration(
              labelText: 'Dosis (opcional)',
              hintText: 'Ej.: 1 tableta, 250 mg',
              prefixIcon: Icon(Icons.scale),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // Horas
          const Text('Horas de las tomas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._times.map((t) => InputChip(
                    label: Text(_fmtTime(t), style: const TextStyle(fontSize: 15)),
                    backgroundColor: Colors.purple.shade50,
                    onDeleted: () => setState(() => _times = _times.where((x) => x != t).toList()),
                    onPressed: () async {
                      final picked = await showTimePicker(context: context, initialTime: t);
                      if (picked == null) return;
                      setState(() {
                        _times = _times.map((x) => x == t ? picked : x).toSet().toList()
                          ..sort((a, b) => _minutes(a).compareTo(_minutes(b)));
                      });
                    },
                  )),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Agregar hora'),
                onPressed: _addTime,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Días
          const Text('¿Qué días?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // Chips en un Wrap: si no caben en una línea bajan a la siguiente
          // (el SegmentedButton se desbordaba en pantallas angostas).
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.calendar_month, size: 18),
                label: const Text('Todos los días'),
                selected: !_specificDays,
                selectedColor: Colors.purple.shade100,
                onSelected: (_) => setState(() => _specificDays = false),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.event_repeat, size: 18),
                label: const Text('Días específicos'),
                selected: _specificDays,
                selectedColor: Colors.purple.shade100,
                onSelected: (_) => setState(() => _specificDays = true),
              ),
            ],
          ),
          if (_specificDays) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final day = i + 1;
                return FilterChip(
                  label: Text(_dayLabels[i]),
                  selected: _weekdays.contains(day),
                  selectedColor: Colors.purple.shade100,
                  onSelected: (sel) => setState(() => sel ? _weekdays.add(day) : _weekdays.remove(day)),
                );
              }),
            ),
          ],
          const SizedBox(height: 20),

          // Fechas
          const Text('Duración del tratamiento', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_arrow, color: Colors.purple),
            title: const Text('Desde'),
            subtitle: Text(dateFmt.format(_startDate)),
            onTap: () async {
              final d = await _pickDate(_startDate);
              if (d != null) setState(() => _startDate = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.flag, color: Colors.purple),
            title: const Text('Tiene fecha de fin'),
            subtitle: Text(_endDate == null ? 'Sin fecha de fin (tratamiento continuo)' : 'Hasta el ${dateFmt.format(_endDate!)}'),
            value: _endDate != null,
            activeThumbColor: Colors.purple,
            onChanged: (v) async {
              if (!v) return setState(() => _endDate = null);
              final d = await _pickDate(_startDate.add(const Duration(days: 7)), first: _startDate);
              if (d != null) setState(() => _endDate = d);
            },
          ),
          if (_endDate != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Cambiar fecha de fin'),
                onPressed: () async {
                  final d = await _pickDate(_endDate!, first: _startDate);
                  if (d != null) setState(() => _endDate = d);
                },
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'A cada hora te llegará una notificación con el botón "Ya la tomé". '
              'Si no la marcas, te recordaré cada 5 minutos (hasta 3 veces).',
              style: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.purple,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: const Text('GUARDAR RECORDATORIO'),
          ),
        ],
      ),
    );
  }
}
