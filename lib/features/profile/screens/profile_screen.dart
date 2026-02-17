import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

// CORRECCIÓN 1: Imports correctos para la App de Conductor
import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../../auth/services/driver_auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // Instancia del servicio
  final _authService = DriverAuthService();

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

  // CORRECCIÓN 2: Acceso al usuario a través de la instancia
  User? get user => _authService.currentUser;

  bool get _isEditing =>
      _isNameEditable ||
      _isPhoneEditable ||
      _isEmailEditable ||
      _imageFile != null;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
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

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  "Cambiar foto de perfil",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (pickedFile != null) {
        setState(() => _imageFile = File(pickedFile.path));
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    String? newPhotoUrl;
    // CORRECCIÓN 3: Llamadas a los métodos del DriverAuthService
    if (_imageFile != null) {
      newPhotoUrl = await _authService.uploadProfileImage(_imageFile!.path);
    }

    final success = await _authService.updateUserProfile(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      photoUrl: newPhotoUrl,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Perfil actualizado")));
      setState(() {
        _isNameEditable = false;
        _isPhoneEditable = false;
        _isEmailEditable = false;
        _imageFile = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text("No hay usuario logueado. Inicia sesión de nuevo."),
        ),
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
                  ? const CircularProgressIndicator(strokeWidth: 2)
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
              _buildAvatarSection(),
              const SizedBox(height: 30),
              _buildEditableField(
                _nameController,
                _nameFocus,
                "Nombre",
                Icons.person_outline,
                _isNameEditable,
                () => setState(() {
                  _isNameEditable = true;
                  _nameFocus.requestFocus();
                }),
              ),
              const SizedBox(height: 15),
              _buildEditableField(
                _phoneController,
                _phoneFocus,
                "Celular",
                Icons.phone_android,
                _isPhoneEditable,
                () => setState(() {
                  _isPhoneEditable = true;
                  _phoneFocus.requestFocus();
                }),
                TextInputType.phone,
              ),
              const SizedBox(height: 15),
              _buildEditableField(
                _emailController,
                _emailFocus,
                "Correo",
                Icons.email_outlined,
                _isEmailEditable,
                () => setState(() {
                  _isEmailEditable = true;
                  _emailFocus.requestFocus();
                }),
                TextInputType.emailAddress,
              ),

              const SizedBox(height: 30),
              // Estado de verificación
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user,
                      color: _getStatusColor(user!.verificationStatus),
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
                          _getStatusText(user!.verificationStatus),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    ImageProvider? imageProvider;
    if (_imageFile != null) {
      imageProvider = FileImage(_imageFile!);
    } else if (user?.photoUrl != null && user!.photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(user!.photoUrl!);
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Text(user?.name[0] ?? "U", style: const TextStyle(fontSize: 40))
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
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: isEditable ? AppColors.primaryGreen : Colors.grey,
        ),
        suffixIcon: !isEditable
            ? IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onEdit,
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: isEditable ? Colors.white : Colors.grey.shade50,
      ),
      validator: (v) => v!.isEmpty ? "Requerido" : null,
    );
  }

  String _getStatusText(UserVerificationStatus status) {
    return status == UserVerificationStatus.VERIFIED
        ? "Verificado"
        : "En Revisión / Pendiente";
  }

  Color _getStatusColor(UserVerificationStatus status) {
    return status == UserVerificationStatus.VERIFIED
        ? Colors.green
        : Colors.orange;
  }
}
