import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/biometric_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final Color darkBg = const Color(0xFF0B0F19);
  final Color cardColor = const Color(0xFF161B2E);

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
  bool _isBioAvailable = false;
  bool _isBioEnabled = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _checkBiometricSupport();
  }

  Future<void> _checkBiometricSupport() async {
    final bioService = sl<BiometricService>();
    final storage = sl<StorageService>();
    bool available = await bioService.isAvailable();
    bool enabled = await storage.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _isBioAvailable = available;
        _isBioEnabled = enabled;
      });
    }
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

  bool get _isEditing =>
      _isNameEditable ||
      _isPhoneEditable ||
      _isEmailEditable ||
      _imageFile != null;

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });

    try {
      await context.read<AuthProvider>().updateProfileData(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        imageFile: _imageFile,
      );
      if (mounted) {
        setState(() {
          _isNameEditable = false;
          _isPhoneEditable = false;
          _isEmailEditable = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Perfil actualizado"),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F19),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildAvatarSection(user),
                          const SizedBox(height: 40),
                          _buildGlassContainer(
                            child: Column(
                              children: [
                                _sectionTitle("INFORMACIÓN PERSONAL"),
                                const SizedBox(height: 20),
                                _buildInput(
                                  _nameController,
                                  _nameFocus,
                                  "NOMBRE COMPLETO",
                                  Icons.person_outline,
                                  _isNameEditable,
                                  () {
                                    setState(() {
                                      _isNameEditable = true;
                                    });
                                  },
                                ),
                                _buildInput(
                                  _phoneController,
                                  _phoneFocus,
                                  "CELULAR",
                                  Icons.phone_android_rounded,
                                  _isPhoneEditable,
                                  () {
                                    setState(() {
                                      _isPhoneEditable = true;
                                    });
                                  },
                                  isPhone: true,
                                ),
                                _buildInput(
                                  _emailController,
                                  _emailFocus,
                                  "CORREO",
                                  Icons.alternate_email_rounded,
                                  _isEmailEditable,
                                  () {
                                    setState(() {
                                      _isEmailEditable = true;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildGlassContainer(
                            child: Column(
                              children: [
                                _sectionTitle("CUENTA Y SEGURIDAD"),
                                const SizedBox(height: 20),
                                _buildStatusRow(user),
                                if (_isBioAvailable)
                                  const Divider(
                                    color: Colors.white10,
                                    height: 30,
                                  ),
                                if (_isBioAvailable)
                                  _buildSettingsTile(
                                    "Acceso Biométrico",
                                    Switch.adaptive(
                                      value: _isBioEnabled,
                                      onChanged: (v) async {
                                        await sl<StorageService>()
                                            .setBiometricEnabled(v);
                                        setState(() {
                                          _isBioEnabled = v;
                                        });
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isEditing)
            Positioned(
              bottom: 30,
              left: 24,
              right: 24,
              child: _buildSaveButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
        ),
        Text(
          "MI PERFIL",
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );

  Widget _buildAvatarSection(User user) => Center(
    child: Stack(
      alignment: Alignment.center,
      children: [
        // 1. Efecto de resplandor sutil (glow)
        Container(
          width: 125,
          height: 125,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.primaryGreen, Colors.blueAccent],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryGreen.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
        ),

        // 2. Avatar con estado de carga
        CircleAvatar(
          radius: 58,
          backgroundColor: darkBg,
          backgroundImage: _imageFile != null
              ? FileImage(_imageFile!)
              : (user.photoUrl != null && user.photoUrl!.isNotEmpty
                    ? NetworkImage(user.photoUrl!)
                    : null),
          child: (_isLoading && _imageFile != null)
              ? const CircularProgressIndicator(color: AppColors.primaryGreen)
              : (user.photoUrl == null && _imageFile == null)
              ? const Icon(Icons.camera_alt, color: Colors.white24, size: 40)
              : null,
        ),

        // 3. Botón de edición con estilo Glassmorphism
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: () =>
                _showImagePickerOptions(), // <--- Llama al modal de selección
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                shape: BoxShape.circle,
                border: Border.all(color: darkBg, width: 3),
              ),
              child: const Icon(
                Icons.camera_enhance_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  // Modal robusto para elegir origen de imagen
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt,
                color: AppColors.primaryGreen,
              ),
              title: Text(
                "Cámara",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: AppColors.primaryGreen,
              ),
              title: Text(
                "Galería",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
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
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 600,
    );
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Widget _buildInput(
    TextEditingController controller,
    FocusNode focus,
    String label,
    IconData icon,
    bool editable,
    VoidCallback onEdit, {
    bool isPhone = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.montserrat(
          color: Colors.grey,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        focusNode: focus,
        readOnly: !editable,
        style: const TextStyle(color: Colors.white),
        keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
        inputFormatters: isPhone
            ? [FilteringTextInputFormatter.digitsOnly]
            : [],
        decoration: InputDecoration(
          prefixIcon: Icon(
            icon,
            color: editable ? AppColors.primaryGreen : Colors.white30,
          ),
          suffixIcon: !editable
              ? IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: Colors.white30),
                  onPressed: onEdit,
                )
              : null,
          filled: true,
          fillColor: cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      const SizedBox(height: 15),
    ],
  );

  Widget _buildStatusRow(User user) => Row(
    children: [
      Icon(Icons.verified_user, color: AppColors.primaryGreen),
      const SizedBox(width: 15),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Estado de cuenta",
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
          ),
          Text(
            user.verificationStatus.toString().split('.').last,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildSettingsTile(String title, Widget trailing) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(title, style: GoogleFonts.poppins(color: Colors.white)),
      trailing,
    ],
  );

  Widget _buildGlassContainer({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: cardColor.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: Colors.white10),
    ),
    child: child,
  );

  Widget _sectionTitle(String title) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      title,
      style: GoogleFonts.montserrat(
        color: AppColors.primaryGreen,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _buildSaveButton() => ElevatedButton(
    onPressed: _isLoading ? null : _saveChanges,
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primaryGreen,
      minimumSize: const Size(double.infinity, 60),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    child: _isLoading
        ? const CircularProgressIndicator(color: Colors.white)
        : Text(
            "GUARDAR CAMBIOS",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
  );
}
