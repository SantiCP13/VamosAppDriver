import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../services/driver_auth_service.dart';
import 'verification_check_screen.dart';

class RegisterScreen extends StatefulWidget {
  final String? emailPreIngresado;

  const RegisterScreen({super.key, this.emailPreIngresado});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _fvLicenciaCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  // Archivos
  File? _selfieFile;
  File? _cedulaFile;
  final ImagePicker _picker = ImagePicker();

  final _authService = DriverAuthService();

  bool _isLoading = false;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    if (widget.emailPreIngresado != null) {
      _emailCtrl.text = widget.emailPreIngresado!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _docCtrl.dispose();
    _fvLicenciaCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // --- LÓGICA DE FOTOS ---
  Future<void> _pickImage(bool isSelfie) async {
    // Para selfie abrimos cámara frontal, para documento abrimos cámara trasera o galería
    final XFile? image = await _picker.pickImage(
      source: isSelfie ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 70, // Comprimimos un poco para que no pese tanto
      preferredCameraDevice: isSelfie ? CameraDevice.front : CameraDevice.rear,
    );

    if (image != null) {
      setState(() {
        if (isSelfie) {
          _selfieFile = File(image.path);
        } else {
          _cedulaFile = File(image.path);
        }
      });
    }
  }

  // --- LÓGICA DE FECHA ---
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryGreen,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _fvLicenciaCtrl.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // --- SUBMIT ---
  Future<void> _handleRegister() async {
    // 1. Validar Textos
    if (!_formKey.currentState!.validate()) {
      _showSnack("Por favor revisa los campos en rojo", isError: true);
      return;
    }

    // 2. Validar Fotos
    if (_selfieFile == null || _cedulaFile == null) {
      _showSnack(
        "Debes adjuntar tu Selfie y la foto de tu Documento",
        isError: true,
      );
      return;
    }

    setState(() => _isLoading = true);

    // Modal inamovible
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      ),
    );

    try {
      await _authService.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        passwordConfirmation: _passCtrl.text.trim(),
        documento: _docCtrl.text.trim(),
        fvLicencia: _fvLicenciaCtrl.text.trim(),
        selfieFile: _selfieFile!,
        cedulaFile: _cedulaFile!,
      );

      if (!mounted) return;

      Navigator.of(context).pop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerificationCheckScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      String msg = e.toString().replaceAll('Exception: ', '');
      _showSnack(msg, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- UI HELPERS ---
  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 30, left: 40, right: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : AppColors.primaryGreen,
        content: Row(
          children: [
            Icon(
              isError ? Icons.cancel_outlined : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _getInputStyle({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.grey.shade600,
      ),
      prefixIcon: Icon(icon, size: 20, color: AppColors.primaryGreen),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffixIcon,
    );
  }

  // Widget para los botones de subir archivos
  Widget _buildFilePickerBtn({
    required String title,
    required IconData icon,
    required bool isSelfie,
    required File? file,
  }) {
    bool hasFile = file != null;
    return InkWell(
      onTap: () => _pickImage(isSelfie),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.primaryGreen.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          border: Border.all(
            color: hasFile ? AppColors.primaryGreen : Colors.grey.shade300,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle : icon,
              color: hasFile ? AppColors.primaryGreen : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: const Color.fromARGB(221, 1, 26, 85),
                    ),
                  ),
                  Text(
                    hasFile
                        ? "Archivo cargado con éxito"
                        : "Toca para subir o tomar foto",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: hasFile
                          ? AppColors.primaryGreen
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Únete al equipo",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20),
                  child: Text(
                    "Completa tus datos y sube tus documentos para empezar a conducir.",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),

                // --- TEXTOS ---
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: _getInputStyle(
                    label: "Nombre Completo",
                    icon: Icons.person_outline,
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _docCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _getInputStyle(
                    label: "Cédula de Ciudadanía",
                    icon: Icons.badge_outlined,
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _getInputStyle(
                    label: "Celular",
                    icon: Icons.phone_android_outlined,
                  ),
                  validator: (v) => v!.length < 10 ? 'Número inválido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _getInputStyle(
                    label: "Correo electrónico",
                    icon: Icons.alternate_email,
                  ),
                  validator: (v) => !v!.contains('@') ? 'Inválido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _fvLicenciaCtrl,
                  readOnly: true,
                  onTap: _selectDate,
                  decoration: _getInputStyle(
                    label: "Fecha Vencimiento Licencia",
                    icon: Icons.calendar_month_outlined,
                  ),
                  validator: (v) => v!.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 24),

                // --- CONTRASEÑAS ---
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: _getInputStyle(
                    label: "Crear Contraseña",
                    icon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (v) =>
                      v!.length < 8 ? 'Mínimo 8 caracteres' : null,
                ),
                const SizedBox(height: 16),

                const SizedBox(height: 40),
                // --- ARCHIVOS ---
                Text(
                  "Documentos Requeridos",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                _buildFilePickerBtn(
                  title: "Selfie del Conductor",
                  icon: Icons.camera_front_outlined,
                  isSelfie: true,
                  file: _selfieFile,
                ),
                const SizedBox(height: 12),

                _buildFilePickerBtn(
                  title: "PDF con Cédula y Licencia",
                  icon: Icons.document_scanner_outlined,
                  isSelfie: false,
                  file: _cedulaFile,
                ),
                const SizedBox(height: 24),

                // --- BOTÓN ---
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: Text(
                      "REGISTRARME Y ENVIAR",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
