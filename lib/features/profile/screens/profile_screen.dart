// lib/features/profile/screens/profile_screen.dart

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
          _imageFile = null;
        });
        _showSnack("Perfil actualizado correctamente");
      }
    } catch (e) {
      if (mounted) {
        _showSnack("Error: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  // DIÁLOGO SEGURO PARA ACTUALIZAR CONTRASEÑA
  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final dialogFormKey = GlobalKey<FormState>();

    bool isCurrentObscured = true;
    bool isNewObscured = true;
    bool isConfirmObscured = true;
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: dialogFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.security_rounded,
                        color: AppColors.primaryGreen,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Actualizar Contraseña",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Por seguridad, te enviaremos una notificación de confirmación a tu correo inmediatamente después del cambio.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        color: Colors.white54,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // CONTRASEÑA ACTUAL
                    _buildDialogPasswordField(
                      controller: currentPasswordController,
                      label: "CONTRASEÑA ACTUAL",
                      isObscured: isCurrentObscured,
                      onToggleVisibility: () {
                        setDialogState(
                          () => isCurrentObscured = !isCurrentObscured,
                        );
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La contraseña actual es requerida';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // NUEVA CONTRASEÑA
                    _buildDialogPasswordField(
                      controller: newPasswordController,
                      label: "NUEVA CONTRASEÑA",
                      isObscured: isNewObscured,
                      onToggleVisibility: () {
                        setDialogState(() => isNewObscured = !isNewObscured);
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La nueva contraseña es requerida';
                        }
                        if (value.length < 6) {
                          return 'Debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // CONFIRMAR NUEVA CONTRASEÑA
                    _buildDialogPasswordField(
                      controller: confirmPasswordController,
                      label: "CONFIRMAR NUEVA CONTRASEÑA",
                      isObscured: isConfirmObscured,
                      onToggleVisibility: () {
                        setDialogState(
                          () => isConfirmObscured = !isConfirmObscured,
                        );
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirma tu contraseña';
                        }
                        if (value != newPasswordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isDialogLoading
                                ? null
                                : () => Navigator.pop(ctx),
                            child: Text(
                              "CANCELAR",
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.bold,
                                color: Colors.white30,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isDialogLoading
                                ? null
                                : () async {
                                    if (!dialogFormKey.currentState!
                                        .validate()) {
                                      return;
                                    }

                                    setDialogState(
                                      () => isDialogLoading = true,
                                    );

                                    try {
                                      // Llamamos de manera defensiva al método del provider si existe
                                      await context
                                          .read<AuthProvider>()
                                          .changePassword(
                                            currentPassword:
                                                currentPasswordController.text,
                                            newPassword:
                                                newPasswordController.text,
                                            confirmPassword:
                                                confirmPasswordController.text,
                                          );
                                      if (context.mounted) {
                                        Navigator.pop(ctx);
                                        _showSnack(
                                          "Contraseña actualizada exitosamente.",
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        _showSnack(
                                          e.toString().replaceAll(
                                            "Exception: ",
                                            "",
                                          ),
                                          isError: true,
                                        );
                                      }
                                    } finally {
                                      setDialogState(
                                        () => isDialogLoading = false,
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              disabledBackgroundColor: Colors.white10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: isDialogLoading
                                ? const SizedBox(
                                    width: 23,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    "GUARDAR",
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isObscured,
    required VoidCallback onToggleVisibility,
    required String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isObscured,
          validator: validator,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: Colors.white30,
              size: 18,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                isObscured
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 16,
                color: Colors.white30,
              ),
              onPressed: onToggleVisibility,
            ),
            filled: true,
            fillColor: cardColor,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 12,
            ),
            errorStyle: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // PROTOCOLO DE ELIMINACIÓN DEFINITIVA
  void _showDeleteAccountDialog() {
    final confirmController = TextEditingController();
    bool canDelete = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.report_gmailerrorred_rounded,
                      color: Colors.redAccent,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "¿Eliminar cuenta definitivamente?",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Esta acción borrará de forma inmediata y definitiva tu perfil de conductor, tus vehículos asociados, historial de viajes y tus saldos del servidor sin excepción alguna. Esta acción NO se puede deshacer.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      color: Colors.white54,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Escribe la palabra 'ELIMINAR' para confirmar:",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (val) {
                      setDialogState(() {
                        canDelete = val.trim() == "ELIMINAR";
                      });
                    },
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                    decoration: InputDecoration(
                      hintText: "ELIMINAR",
                      hintStyle: const TextStyle(color: Colors.white12),
                      filled: true,
                      fillColor: darkBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            "CANCELAR",
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              color: Colors.white30,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: canDelete
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _executeAccountDeletion();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            disabledBackgroundColor: Colors.white10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            "ELIMINAR",
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              color: canDelete ? Colors.white : Colors.white30,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _executeAccountDeletion() async {
    setState(() => _isLoading = true);

    try {
      final success = await context.read<AuthProvider>().deleteUserAccount();
      if (success && mounted) {
        _showSnack("Tu cuenta y datos han sido eliminados definitivamente.");
      } else {
        _showSnack(
          "No se pudo procesar la solicitud. Intenta de nuevo.",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack("Error: $e", isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user == null) {
      return Scaffold(
        backgroundColor: darkBg,
        body: const Center(child: CircularProgressIndicator()),
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
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'El nombre no puede estar vacío';
                                    }
                                    if (value.trim().length < 3) {
                                      return 'Nombre demasiado corto';
                                    }
                                    return null;
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
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'El celular es obligatorio';
                                    }
                                    if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                                      return 'Ingresa 10 dígitos válidos';
                                    }
                                    return null;
                                  },
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
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'El correo es obligatorio';
                                    }
                                    final emailRegex = RegExp(
                                      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                    );
                                    if (!emailRegex.hasMatch(value)) {
                                      return 'Correo electrónico no válido';
                                    }
                                    return null;
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
                                const Divider(
                                  color: Colors.white10,
                                  height: 30,
                                ),
                                _buildActionTile(
                                  icon: Icons.lock_outline_rounded,
                                  title: "Seguridad de la cuenta",
                                  subtitle: "Cambiar contraseña",
                                  onTap: _showChangePasswordDialog,
                                ),
                                if (_isBioAvailable) ...[
                                  const Divider(
                                    color: Colors.white10,
                                    height: 30,
                                  ),
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ZONA DE ELIMINACIÓN SEGURA
                          _buildGlassContainer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionTitle("ZONA DE ELIMINACIÓN"),
                                const SizedBox(height: 15),
                                Text(
                                  "La eliminación de la cuenta es permanente e irreversible. Se borrarán todos tus datos de conductor, turnos e historial sin excepción.",
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12,
                                    color: Colors.white54,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: OutlinedButton.icon(
                                    onPressed: _showDeleteAccountDialog,
                                    icon: const Icon(
                                      Icons.delete_forever_rounded,
                                      color: Colors.redAccent,
                                    ),
                                    label: Text(
                                      "ELIMINAR MI CUENTA",
                                      style: GoogleFonts.montserrat(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.redAccent,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      backgroundColor: Colors.red.withValues(
                                        alpha: 0.02,
                                      ),
                                    ),
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(width: 15),
        Text(
          "MI PERFIL",
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _buildAvatarSection(User user) => Center(
    child: Stack(
      alignment: Alignment.center,
      children: [
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
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => _showImagePickerOptions(),
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
    String? Function(String?)? validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.montserrat(
          color: Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 8),
      TextFormField(
        controller: controller,
        focusNode: focus,
        readOnly: !editable,
        validator: validator,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
        inputFormatters: isPhone
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ]
            : [],
        decoration: InputDecoration(
          prefixIcon: Icon(
            icon,
            color: editable ? AppColors.primaryGreen : Colors.white30,
            size: 18,
          ),
          suffixIcon: !editable
              ? IconButton(
                  icon: const Icon(Icons.edit, size: 16, color: Colors.white30),
                  onPressed: onEdit,
                )
              : null,
          filled: true,
          fillColor: editable ? cardColor : cardColor.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 12,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primaryGreen,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
      ),
      const SizedBox(height: 15),
    ],
  );

  Widget _buildStatusRow(User user) => Row(
    children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.verified_user_rounded,
          color: AppColors.primaryGreen,
          size: 20,
        ),
      ),
      const SizedBox(width: 15),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Estado de cuenta",
              style: GoogleFonts.montserrat(
                color: Colors.white30,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              user.verificationStatus
                  .toString()
                  .split('.')
                  .last
                  .replaceAll('_', ' '),
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      const Icon(Icons.lock_rounded, size: 14, color: Colors.white24),
    ],
  );

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primaryGreen, size: 20),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.montserrat(
                      fontSize: 10,
                      color: Colors.white30,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(String title, Widget trailing) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: GoogleFonts.montserrat(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing,
    ],
  );

  Widget _buildGlassContainer({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: cardColor.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
