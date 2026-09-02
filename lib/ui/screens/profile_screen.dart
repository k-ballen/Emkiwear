import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../services/firebase_service.dart';
import '../../models/user_profile.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final _formKey = GlobalKey<FormState>();
  
  bool _isEditing = false;
  bool _isLoading = true;
  
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _fixedPhoneController = TextEditingController();
  final _cellPhoneController = TextEditingController();
  final _diagnosisYearController = TextEditingController();
  final _experienceController = TextEditingController();
  final _specialistNameController = TextEditingController();
  final _hospitalController = TextEditingController();
  final _consultationTimeController = TextEditingController();
  final _supportGroupOtherController = TextEditingController();

  String _selectedSpecialty = 'Neurología';
  String _selectedSupportGroup = 'Club Parkinson Bogotá';
  bool _isPublic = false;
  String _photoUrl = '';
  File? _imageFile;

  final List<String> _specialties = ['Neurología', 'Medicina interna', 'Fisioterapia', 'Neuropsicología', 'Otro'];
  final List<String> _supportGroups = [
    'Club Parkinson Bogotá', 
    'Grupo de apoyo Parkinson', 
    'Asociación de pacientes', 
    'Comunidad de actividad física', 
    'Otro'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() async {
    try {
      final profile = await _firebaseService.getUserProfile();
      if (profile != null && mounted) {
        setState(() {
          _nameController.text = profile.name;
          _lastNameController.text = profile.lastName;
          _fixedPhoneController.text = profile.fixedPhone;
          _cellPhoneController.text = profile.cellPhone;
          _diagnosisYearController.text = profile.diagnosisYear?.toString() ?? '';
          _experienceController.text = profile.experience;
          _specialistNameController.text = profile.specialistName;
          _hospitalController.text = profile.hospital;
          _consultationTimeController.text = profile.consultationTime;
          _isPublic = profile.isPublic;
          _photoUrl = profile.photoUrl;
          
          if (_specialties.contains(profile.specialistType)) {
            _selectedSpecialty = profile.specialistType;
          } else {
            _selectedSpecialty = 'Otro';
          }

          if (_supportGroups.contains(profile.supportGroup)) {
            _selectedSupportGroup = profile.supportGroup;
          } else {
            _selectedSupportGroup = 'Otro';
            _supportGroupOtherController.text = profile.supportGroup;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar perfil: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  void _saveProfile() async {
    setState(() => _isLoading = true);
    
    try {
      if (_imageFile != null) {
        // Solo intentamos subir si el usuario seleccionó una imagen nueva
        _photoUrl = await _firebaseService.uploadProfilePhoto(_imageFile!);
      }

      final profile = UserProfile(
        uid: _firebaseService.currentUserId!,
        name: _nameController.text,
        lastName: _lastNameController.text,
        fixedPhone: _fixedPhoneController.text,
        cellPhone: _cellPhoneController.text,
        photoUrl: _photoUrl,
        diagnosisYear: int.tryParse(_diagnosisYearController.text),
        experience: _experienceController.text,
        specialistName: _specialistNameController.text,
        specialistType: _selectedSpecialty,
        hospital: _hospitalController.text,
        consultationTime: _consultationTimeController.text,
        supportGroup: _selectedSupportGroup == 'Otro' ? _supportGroupOtherController.text : _selectedSupportGroup,
        isPublic: _isPublic,
      );

      await _firebaseService.updateUserProfile(profile);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil actualizado')));
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        // Manejo específico para el error de objeto no encontrado o cualquier error de Storage/Firestore
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar cambios: $e'), 
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.purple.shade100,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () => setState(() => _isEditing = !_isEditing),
          )
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
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildPhotoSection(),
                const SizedBox(height: 25),
                _buildSectionTitle('Información Personal'),
                _buildTextField('Nombre', _nameController),
                _buildTextField('Apellidos', _lastNameController),
                _buildTextField('Teléfono Fijo', _fixedPhoneController, keyboardType: TextInputType.phone),
                _buildTextField('Teléfono Celular', _cellPhoneController, keyboardType: TextInputType.phone),
                
                const SizedBox(height: 25),
                _buildSectionTitle('Parkinson'),
                _buildTextField('Año de diagnóstico', _diagnosisYearController, keyboardType: TextInputType.number),
                _buildTextField('Mi experiencia', _experienceController, maxLines: 3),
                
                const SizedBox(height: 25),
                _buildSectionTitle('Mi Especialista'),
                _buildTextField('Nombre del Doctor', _specialistNameController),
                _buildDropdown('Especialidad', _selectedSpecialty, _specialties, (val) => setState(() => _selectedSpecialty = val!)),
                _buildTextField('Hospital / Institución', _hospitalController),
                _buildTextField('Horario de consulta', _consultationTimeController),
                
                const SizedBox(height: 25),
                _buildSectionTitle('Grupo de Apoyo'),
                _buildDropdown('Pertenencia', _selectedSupportGroup, _supportGroups, (val) => setState(() => _selectedSupportGroup = val!)),
                if (_selectedSupportGroup == 'Otro')
                  _buildTextField('Nombre del grupo', _supportGroupOtherController),
                
                const SizedBox(height: 25),
                _buildPrivacyToggle(),
                
                if (_isEditing) ...[
                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A), 
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.purple.shade200,
              backgroundImage: _imageFile != null 
                  ? FileImage(_imageFile!) 
                  : (_photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null) as ImageProvider?,
              child: _imageFile == null && _photoUrl.isEmpty 
                  ? const Icon(Icons.person, size: 60, color: Colors.white) 
                  : null,
            ),
            if (_isEditing)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.purple),
                    onPressed: _pickImage,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType keyboardType = TextInputType.text, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        controller: controller,
        enabled: _isEditing,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
        onChanged: _isEditing ? onChanged : null,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        ),
      ),
    );
  }

  Widget _buildPrivacyToggle() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _isPublic ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _isPublic ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: SwitchListTile(
        title: const Text('Hacer mi perfil público', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Permitir que otros compañeros vean tu experiencia.'),
        value: _isPublic,
        onChanged: _isEditing ? (val) => setState(() => _isPublic = val) : null,
        activeThumbColor: Colors.green,
      ),
    );
  }
}
