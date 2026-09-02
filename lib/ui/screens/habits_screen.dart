import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firebase_service.dart';
import '../../models/food_habit.dart';
import '../../models/activity_habit.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService();
  final DateTime _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Mis Hábitos', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple.shade100,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6A1B9A),
          labelColor: const Color(0xFF6A1B9A),
          unselectedLabelColor: Colors.black54,
          tabs: const [
            Tab(icon: Icon(Icons.apple), text: 'Alimentación'),
            Tab(icon: Icon(Icons.directions_run), text: 'Actividad Física'),
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
            _FoodCategory(firebaseService: _firebaseService, date: _today),
            _ActivityCategory(firebaseService: _firebaseService, date: _today),
          ],
        ),
      ),
    );
  }
}

class _FoodCategory extends StatelessWidget {
  final FirebaseService firebaseService;
  final DateTime date;

  const _FoodCategory({required this.firebaseService, required this.date});

  void _showAddFoodDialog(BuildContext context) {
    final foodController = TextEditingController();
    String selectedType = 'Desayuno';
    final types = ['Desayuno', 'Almuerzo', 'Cena', 'Merienda'];
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Registrar Comida', style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) => setDialogState(() => selectedType = val!),
                decoration: const InputDecoration(labelText: 'Tipo de comida'),
              ),
              TextField(
                controller: foodController,
                decoration: const InputDecoration(labelText: '¿Qué comiste?'),
              ),
              ListTile(
                title: const Text('Hora'),
                trailing: Text(selectedTime.format(context)),
                onTap: () async {
                  final time = await showTimePicker(context: context, initialTime: selectedTime);
                  if (time != null) setDialogState(() => selectedTime = time);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), 
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
              onPressed: () async {
                if (foodController.text.isEmpty) return;
                await firebaseService.logFoodHabit(foodController.text, selectedType, DateTime.now(), selectedTime);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // Tamaño reducido
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, FoodHabit habit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar registro?'),
        content: Text('¿Deseas eliminar "${habit.food}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await firebaseService.deleteFoodHabit(habit.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddFoodDialog(context),
          icon: const Icon(Icons.restaurant),
          label: const Text('REGISTRAR COMIDA'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A1B9A), 
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        const SizedBox(height: 25),
        Text('Comidas de hoy', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
        const SizedBox(height: 10),
        StreamBuilder<List<FoodHabit>>(
          stream: firebaseService.getFoodHabits(date),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final habits = snapshot.data ?? [];
            if (habits.isEmpty) return const Text('No has registrado comidas hoy.');
            return Column(
              children: habits.map((h) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: const Icon(Icons.restaurant, color: Colors.orange),
                  title: Text(h.mealType, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(h.food),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('hh:mm a').format(h.timestamp)),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _confirmDelete(context, h)),
                    ],
                  ),
                ),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 30),
        _buildInfoSection(context),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.lightGreen.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.lightGreen.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: Colors.orange),
              SizedBox(width: 10),
              Text('¿Por qué es importante?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Mantener una alimentación equilibrada ayuda a mejorar la absorción de los medicamentos y a mantener los niveles de energía.',
            style: TextStyle(fontSize: 15, color: Colors.black87),
          ),
        ],
      ),
    );
  }
}

class _ActivityCategory extends StatelessWidget {
  final FirebaseService firebaseService;
  final DateTime date;

  const _ActivityCategory({required this.firebaseService, required this.date});

  void _showAddActivityDialog(BuildContext context) {
    final activities = ['Caminar', 'Estiramiento', 'Bicicleta', 'Natación', 'Baile', 'Yoga', 'Ejercicios de fuerza', 'Otro'];
    String selectedActivity = 'Caminar';
    final durationController = TextEditingController(text: '30');
    String selectedIntensity = 'Media';
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Registrar Actividad', style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedActivity,
                  items: activities.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                  onChanged: (val) => setDialogState(() => selectedActivity = val!),
                  decoration: const InputDecoration(labelText: 'Actividad'),
                ),
                TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Duración (minutos)'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: selectedIntensity,
                  items: ['Leve', 'Media', 'Alta'].map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
                  onChanged: (val) => setDialogState(() => selectedIntensity = val!),
                  decoration: const InputDecoration(labelText: 'Intensidad'),
                ),
                ListTile(
                  title: const Text('Hora'),
                  trailing: Text(selectedTime.format(context)),
                  onTap: () async {
                    final time = await showTimePicker(context: context, initialTime: selectedTime);
                    if (time != null) setDialogState(() => selectedTime = time);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext), 
              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
            ),
            ElevatedButton(
              onPressed: () async {
                final duration = int.tryParse(durationController.text) ?? 0;
                await firebaseService.logActivityHabit(selectedActivity, duration, selectedIntensity, DateTime.now(), selectedTime);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A1B9A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), // Tamaño reducido
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ActivityHabit habit) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar registro?'),
        content: Text('¿Deseas eliminar "${habit.activityType}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await firebaseService.deleteActivityHabit(habit.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddActivityDialog(context),
          icon: const Icon(Icons.directions_run),
          label: const Text('REGISTRAR ACTIVIDAD'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A1B9A), 
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 60),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          ),
        ),
        const SizedBox(height: 25),
        _buildSummary(context),
        const SizedBox(height: 25),
        Text('Actividades de hoy', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
        const SizedBox(height: 10),
        StreamBuilder<List<ActivityHabit>>(
          stream: firebaseService.getActivityHabits(date),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final habits = snapshot.data ?? [];
            if (habits.isEmpty) return const Text('No has registrado ejercicio hoy.');
            return Column(
              children: habits.map((h) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: const Icon(Icons.directions_run, color: Colors.blue),
                  title: Text(h.activityType, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${h.duration} min - Intensidad ${h.intensity}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('hh:mm a').format(h.timestamp)),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _confirmDelete(context, h)),
                    ],
                  ),
                ),
              )).toList(),
            );
          },
        ),
        const SizedBox(height: 30),
        _buildRecommendations(context),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    return StreamBuilder<List<ActivityHabit>>(
      stream: firebaseService.getActivityHabitsForMonth(DateTime.now()),
      builder: (context, snapshot) {
        final habits = snapshot.data ?? [];
        final totalMin = habits.fold<int>(0, (sum, item) => sum + item.duration);
        final sessions = habits.length;

        final Map<String, int> activityCounts = {};
        for (var h in habits) {
          activityCounts[h.activityType] = (activityCounts[h.activityType] ?? 0) + 1;
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
          ),
          child: Column(
            children: [
              Text(DateFormat('MMMM yyyy', 'es').format(DateTime.now()).toUpperCase(), 
                   style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [const Text('Sesiones'), Text('$sessions', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]),
                  Column(children: [const Text('Total Minutos'), Text('$totalMin', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.purple))]),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: activityCounts.entries.map((e) => Chip(
                  label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.purple.shade50,
                )).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRecDetail(BuildContext context, String title, String benefits, String security) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Beneficios:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(benefits),
              const SizedBox(height: 15),
              const Text('Recomendaciones de seguridad:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(security),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actividad recomendada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _RecommendationCard(
                title: 'Estiramientos', 
                icon: Icons.accessibility_new, 
                color: Colors.blue.shade100,
                onTap: () => _showRecDetail(context, 'Estiramientos', 
                  'Ayuda a mantener la flexibilidad y reducir la rigidez muscular.', 
                  'Realiza movimientos suaves y lentos. No fuerces ninguna articulación.')
              ),
              _RecommendationCard(
                title: 'Caminatas', 
                icon: Icons.nordic_walking, 
                color: Colors.green.shade100,
                onTap: () => _showRecDetail(context, 'Caminatas', 
                  'Mejora la salud cardiovascular y la movilidad de las piernas.', 
                  'Usa calzado cómodo y camina en superficies planas y seguras.')
              ),
              _RecommendationCard(
                title: 'Yoga suave', 
                icon: Icons.self_improvement, 
                color: Colors.purple.shade100,
                onTap: () => _showRecDetail(context, 'Yoga suave', 
                  'Fomenta el equilibrio, la relajación y el control postural.', 
                  'Puedes usar una silla como apoyo si sientes inestabilidad.')
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RecommendationCard({required this.title, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 15),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.black87),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
