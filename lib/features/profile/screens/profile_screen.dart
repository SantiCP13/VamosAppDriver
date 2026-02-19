import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart'; // NECESARIO

import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
// Eliminamos import directo del servicio: import '../../auth/services/driver_auth_service.dart';
import '../../auth/providers/auth_provider.dart'; // Usamos el Provider

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  bool _isNameEditable = false;
  bool _isPhoneEditable = false;
  bool _isEmailEditable = false;

  File? _imageFile;
  bool _isLoading = false;

  bool get _isEditing =>
      _isNameEditable ||
      _isPhoneEditable ||
      _isEmailEditable ||
      _imageFile != null;

  @override
  void initState() {
    super.initState();
    // Cargamos los datos iniciales desde el Provider
    // Usamos listen: false porque initState no puede escuchar cambios
    final user = context.read<AuthProvider>().user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // --- LÓGICA DE NEGOCIO ACTUALIZADA ---

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();

      // 1. Subir Foto (Si cambió)

      if (_imageFile != null) {
        // Asumiendo que agregas este método en tu AuthProvider o lo expones del servicio
        // Por ahora accedemos al servicio a través del provider si es público o agregamos el método en el provider
        // Opción Rápida: Exponer el servicio desde el provider o crear método en provider
        // Aquí asumiré que agregaste updateProfile al AuthProvider (ver punto 3 abajo)
        await authProvider.updateProfileData(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          imageFile: _imageFile,
        );
      } else {
        await authProvider.updateProfileData(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Perfil actualizado correctamente")),
        );
        setState(() {
          _isNameEditable = false;
          _isPhoneEditable = false;
          _isEmailEditable = false;
          _imageFile = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ... (El resto de _showImagePickerOptions y _pickImage queda igual) ...
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text("Tomar foto", style: GoogleFonts.poppins()),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text("Galería", style: GoogleFonts.poppins()),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source, maxWidth: 800);
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usamos Consumer para escuchar cambios en el usuario en tiempo real
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;

        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text("Sesión no válida")),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: const BackButton(color: Colors.black),
            title: Text(
              "Mi Perfil",
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [
              if (_isEditing)
                TextButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          "Guardar",
                          style: GoogleFonts.poppins(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildAvatarSection(user), // Pasamos el usuario
                  const SizedBox(height: 30),
                  // Campos...
                  _buildEditableField(
                    _nameController,
                    _nameFocus,
                    "Nombre",
                    Icons.person_outline,
                    _isNameEditable,
                    () {
                      setState(() {
                        _isNameEditable = true;
                        _nameFocus.requestFocus();
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  _buildEditableField(
                    _phoneController,
                    _phoneFocus,
                    "Celular",
                    Icons.phone_android,
                    _isPhoneEditable,
                    () {
                      setState(() {
                        _isPhoneEditable = true;
                        _phoneFocus.requestFocus();
                      });
                    },
                    TextInputType.phone,
                  ),
                  const SizedBox(height: 15),
                  _buildEditableField(
                    _emailController,
                    _emailFocus,
                    "Correo",
                    Icons.email_outlined,
                    _isEmailEditable,
                    () {
                      setState(() {
                        _isEmailEditable = true;
                        _emailFocus.requestFocus();
                      });
                    },
                    TextInputType.emailAddress,
                  ),

                  // ... Resto de widgets (Estado de cuenta, etc) ...
                  const SizedBox(height: 30),
                  _buildStatusCard(user), // Extraído a método
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(User user) {
    ImageProvider? imageProvider;
    if (_imageFile != null) {
      imageProvider = FileImage(_imageFile!);
    } else if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(user.photoUrl!);
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(
                  user.name.isNotEmpty ? user.name[0] : "U",
                  style: const TextStyle(fontSize: 40),
                )
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _showImagePickerOptions,
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryGreen,
              child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  // Helper simple para la tarjeta de estado
  Widget _buildStatusCard(User user) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.verified_user,
            color: user.verificationStatus == UserVerificationStatus.VERIFIED
                ? Colors.green
                : Colors.orange,
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Estado de Cuenta",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                user.verificationStatus == UserVerificationStatus.VERIFIED
                    ? "Verificado"
                    : "En Revisión",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ... (Tu método _buildEditableField original sigue igual)
  Widget _buildEditableField(
    TextEditingController ctrl,
    FocusNode node,
    String label,
    IconData icon,
    bool isEditable,
    VoidCallback onEdit, [
    TextInputType type = TextInputType.text,
  ]) {
    return TextFormField(
      controller: ctrl,
      focusNode: node,
      readOnly: !isEditable,
      keyboardType: type,
      style: GoogleFonts.poppins(color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.grey),
        prefixIcon: Icon(
          icon,
          color: isEditable ? AppColors.primaryGreen : Colors.grey,
        ),
        suffixIcon: !isEditable
            ? IconButton(
                icon: const Icon(Icons.edit, size: 20, color: Colors.grey),
                onPressed: onEdit,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        filled: true,
        fillColor: isEditable ? Colors.white : Colors.grey.shade50,
      ),
      validator: (v) => v!.isEmpty ? "Requerido" : null,
    );
  }
}
