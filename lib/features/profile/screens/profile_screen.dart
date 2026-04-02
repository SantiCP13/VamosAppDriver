import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';

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

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.updateProfileData(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        imageFile: _imageFile,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Perfil actualizado correctamente"),
            backgroundColor: AppColors.primaryGreen,
          ),
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: Text("Tomar foto (Cámara)", style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.photo_library, color: Colors.white),
              ),
              title: Text("Galería", style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (pickedFile != null) {
      setState(() => _imageFile = File(pickedFile.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;
        if (user == null) {
          return const Scaffold(body: Center(child: Text("Cargando...")));
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
                      ? const SizedBox(
                          width: 15,
                          height: 15,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  _buildAvatarSection(user),
                  const SizedBox(height: 30),
                  Text(
                    "Información del Conductor",
                    style: GoogleFonts.poppins(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildEditableField(
                    _nameController,
                    _nameFocus,
                    "Nombre Completo",
                    Icons.person_outline,
                    _isNameEditable,
                    () {
                      setState(() => _isNameEditable = true);
                      _nameFocus.requestFocus();
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
                      setState(() => _isPhoneEditable = true);
                      _phoneFocus.requestFocus();
                    },
                    TextInputType.phone,
                  ),
                  const SizedBox(height: 15),
                  _buildEditableField(
                    _emailController,
                    _emailFocus,
                    "Correo Electrónico",
                    Icons.email_outlined,
                    _isEmailEditable,
                    () {
                      setState(() => _isEmailEditable = true);
                      _emailFocus.requestFocus();
                    },
                    TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 30),
                  _buildReadOnlyTile(
                    icon: Icons.verified_user_outlined,
                    title: _getStatusText(user.verificationStatus),
                    subtitle: "Estado de la cuenta",
                    color: _getStatusColor(user.verificationStatus),
                    bgColor: _getStatusColor(
                      user.verificationStatus,
                    ).withValues(alpha: 0.1),
                  ),
                  const SizedBox(height: 40),
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

    return Center(
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
              image: imageProvider != null
                  ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
                  : null,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: imageProvider == null
                ? Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : "C",
                      style: GoogleFonts.poppins(
                        fontSize: 40,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  )
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _showImagePickerOptions,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
    TextEditingController controller,
    FocusNode focusNode,
    String label,
    IconData icon,
    bool isEditable,
    VoidCallback onEditPressed, [
    TextInputType keyboardType = TextInputType.text,
  ]) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: !isEditable,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(
        fontSize: 15,
        color: isEditable ? Colors.black87 : Colors.grey.shade700,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.grey.shade600),
        prefixIcon: Icon(
          icon,
          color: isEditable ? AppColors.primaryGreen : Colors.grey,
          size: 22,
        ),
        suffixIcon: !isEditable
            ? IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primaryGreen,
                  size: 20,
                ),
                onPressed: onEditPressed,
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 20,
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
      validator: (v) => v!.isEmpty ? "Campo requerido" : null,
    );
  }

  Widget _buildReadOnlyTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  String _getStatusText(UserVerificationStatus status) {
    if (status == UserVerificationStatus.VERIFIED) {
      return "Verificado";
    } else if (status == UserVerificationStatus.UNDER_REVIEW) {
      return "En Revisión";
    } else if (status == UserVerificationStatus.REJECTED) {
      return "Rechazado";
    } else {
      return "Pendiente";
    }
  }

  Color _getStatusColor(UserVerificationStatus status) {
    if (status == UserVerificationStatus.VERIFIED) {
      return AppColors.primaryGreen;
    } else if (status == UserVerificationStatus.UNDER_REVIEW) {
      return Colors.orange;
    } else if (status == UserVerificationStatus.REJECTED) {
      return Colors.red;
    } else {
      return Colors.grey;
    }
  }
}
