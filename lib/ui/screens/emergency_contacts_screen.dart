import 'package:flutter/material.dart';
import '../../models/emergency_contact.dart';
import '../../services/call_service.dart';
import '../../services/firebase_service.dart';

/// Contactos de emergencia: el asistente ofrece llamarlos cuando la persona
/// dice que se siente mal.
class EmergencyContactsScreen extends StatelessWidget {
  const EmergencyContactsScreen({super.key});

  Future<void> _edit(BuildContext context, List<EmergencyContact> all, [int? index]) async {
    final existing = index != null ? all[index] : null;
    final result = await showDialog<EmergencyContact>(
      context: context,
      builder: (_) => _ContactDialog(contact: existing),
    );
    if (result == null) return;
    final updated = [...all];
    if (index != null) {
      updated[index] = result;
    } else {
      updated.add(result);
    }
    await FirebaseService().saveEmergencyContacts(updated);
  }

  Future<void> _delete(BuildContext context, List<EmergencyContact> all, int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar contacto?'),
        content: Text('Se eliminará a ${all[index].label} de tus contactos de emergencia.'),
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
    if (ok != true) return;
    await FirebaseService().saveEmergencyContacts([...all]..removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EmergencyContact>>(
      stream: FirebaseService().streamEmergencyContacts(),
      builder: (context, snapshot) {
        final contacts = snapshot.data ?? const <EmergencyContact>[];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Contactos de emergencia'),
            backgroundColor: Colors.purple.shade100,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context, contacts),
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.person_add),
            label: const Text('Agregar contacto'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Si le dices a Emki que te sientes mal, te ofrecerá llamar a estas personas. '
                  'También puedes decir "llama a mi hija" o "llama a mi contacto de emergencia".',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Aún no tienes contactos de emergencia.\nToca "Agregar contacto".',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              else
                ...List.generate(contacts.length, (i) {
                  final c = contacts[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.purple.shade100,
                        child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
                      ),
                      title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(c.phone),
                      onTap: () => _edit(context, contacts, i),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Llamar',
                            icon: const Icon(Icons.call, color: Colors.green),
                            onPressed: () => CallService.dial(c.phone),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _delete(context, contacts, i),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => CallService.dial(CallService.emergencyNumber),
                icon: const Icon(Icons.local_hospital, color: Colors.red),
                label: const Text('Línea de emergencias 123'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Colors.red.shade200),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContactDialog extends StatefulWidget {
  final EmergencyContact? contact;
  const _ContactDialog({this.contact});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.contact?.name ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.contact?.phone ?? '');
  late final TextEditingController _relation = TextEditingController(text: widget.contact?.relation ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _relation.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final phone = EmergencyContact.cleanPhone(_phone.text);
    if (name.isEmpty) return setState(() => _error = 'Escribe el nombre.');
    if (phone.replaceAll('+', '').length < 7) return setState(() => _error = 'Escribe un número válido.');
    Navigator.of(context).pop(EmergencyContact(name: name, phone: phone, relation: _relation.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.contact == null ? 'Nuevo contacto' : 'Editar contacto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person)),
            ),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono', prefixIcon: Icon(Icons.phone)),
            ),
            TextField(
              controller: _relation,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Parentesco (opcional)',
                hintText: 'Ej.: hija, esposo, cuidador',
                prefixIcon: Icon(Icons.family_restroom),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}
