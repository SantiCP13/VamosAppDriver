import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart'; // Añadir esta
import 'dart:ui';
import 'package:flutter/services.dart'; // <--- ESTA ES LA QUE FALTA

import '../../../core/theme/app_colors.dart';
import '../services/driver_auth_service.dart';
import 'pending_approval_screen.dart'; // Import corregido
import 'splash_screen.dart';

class RegisterScreen extends StatefulWidget {
  final String? emailPreIngresado;
  const RegisterScreen({super.key, this.emailPreIngresado});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePass = true;
  final _scrollController = ScrollController();
  Map<String, bool> _fieldErrors = {};

  // Controladores
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _fvLicenciaCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController(); // Nueva

  String _tipoDocumento = 'CC'; // Nueva
  bool _aceptaTerminos = false; // Nueva
  bool _isPickerActive = false; // <--- FLAG PARA EVITAR CRASH

  File? _selfieFile;
  File? _cedulaFile;
  File? _licenciaFile; // <--- AGREGA ESTA LÍNEA

  final ImagePicker _picker = ImagePicker();
  final _authService = DriverAuthService();

  @override
  void initState() {
    super.initState();
    if (widget.emailPreIngresado != null) {
      _emailCtrl.text = widget.emailPreIngresado!;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _docCtrl.dispose();
    _fvLicenciaCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

  // Cambia el método para aceptar un entero o un enum para identificar el archivo
  Future<void> _pickDocument(int type) async {
    if (_isPickerActive) return;

    setState(() => _isPickerActive = true);

    try {
      // 0: Selfie (Sigue siendo solo cámara/foto)
      if (type == 0) {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 70,
        );
        if (photo != null) {
          setState(() => _selfieFile = File(photo.path));
        }
      }
      // 1 y 2: Cédula y Licencia (Acepta PDF e Imágenes)
      else {
        // CORRECCIÓN: FilePicker.platform.pickFiles es la forma correcta
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
          allowMultiple: false,
        );

        if (result != null && result.files.single.path != null) {
          setState(() {
            if (type == 1) _cedulaFile = File(result.files.single.path!);
            if (type == 2) _licenciaFile = File(result.files.single.path!);
          });
        }
      }
    } on PlatformException catch (e) {
      debugPrint("Error de plataforma: $e");
      _showSnack("El selector ya está abierto o hubo un error.", isError: true);
    } finally {
      // Damos un pequeño respiro al sistema para evitar el crash de 'already_active'
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _isPickerActive = false);
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2050),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryGreen,
            onPrimary: Colors.white,
            surface: AppColors.surfaceDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _fvLicenciaCtrl.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
        _fieldErrors['licencia'] = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    String? errorDetail;
    setState(() => _fieldErrors = {});

    // 1. Validaciones de campos
    if (_nameCtrl.text.trim().length < 3) {
      _fieldErrors['nombre'] = true;
      errorDetail = "Escribe tu nombre completo.";
    } else if (_docCtrl.text.length < 6) {
      _fieldErrors['documento'] = true;
      errorDetail = "Cédula inválida.";
    } else if (_phoneCtrl.text.length != 10) {
      _fieldErrors['telefono'] = true;
      errorDetail = "El celular debe tener 10 dígitos.";
    } else if (!_isValidEmail(_emailCtrl.text)) {
      _fieldErrors['email'] = true;
      errorDetail = "Formato de email inválido.";
    } else if (_fvLicenciaCtrl.text.isEmpty) {
      _fieldErrors['licencia'] = true;
      errorDetail = "Selecciona la fecha de vencimiento.";
    } else if (_passCtrl.text.length < 8) {
      _fieldErrors['password'] = true;
      errorDetail = "Mínimo 8 caracteres para la contraseña.";
    } else if (_passCtrl.text != _confirmPassCtrl.text) {
      _fieldErrors['confirmPassword'] = true;
      errorDetail = "Las contraseñas no coinciden.";
    } else if (_selfieFile == null ||
        _cedulaFile == null ||
        _licenciaFile == null) {
      _showSnack(
        "Debes subir la selfie, la cédula y la licencia.",
        isError: true,
      );
      return;
    } else if (!_aceptaTerminos) {
      errorDetail = "Debes autorizar el tratamiento de datos personales.";
    }

    if (errorDetail != null) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
      _showSnack(errorDetail, isError: true);
      return;
    }

    setState(() => _isLoading = true);

    // 2. Definimos y empujamos la ruta de carga
    final loadingRoute = MaterialPageRoute(
      builder: (_) => const SplashScreen(
        logoPath: 'assets/images/logo.png',
        isLoader: true,
        isDark: true,
      ),
    );
    Navigator.push(context, loadingRoute);

    try {
      await _authService.register(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        passwordConfirmation: _confirmPassCtrl.text.trim(),
        documento: _docCtrl.text.trim(),
        tipoDocumento: _tipoDocumento,
        fvLicencia: _fvLicenciaCtrl.text.trim(),
        selfieFile: _selfieFile!,
        cedulaFile: _cedulaFile!,
        licenciaFile: _licenciaFile!,
      );

      // 3. Eliminamos el loader de forma segura
      if (mounted) {
        Navigator.of(context).removeRoute(loadingRoute);
      }

      Navigator.pushReplacement(
        // ignore: use_build_context_synchronously
        context,
        MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
      );
    } catch (e) {
      // 4. En caso de error, removemos el loader y mostramos el snackbar con el mensaje real
      if (mounted) {
        Navigator.of(context).removeRoute(loadingRoute);
      }
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFFD32F2F)
            : AppColors.primaryGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Text(
          msg,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D121F),
      extendBodyBehindAppBar: true,

      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.45),
                radius: 1.8,
                colors: [Color(0xFF25335A), Color(0xFF0D121F)],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                left: 28.0,
                right: 28.0,
                top: 20.0,
              ), // Agregamos un top padding aquí también
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 120),
                    Text(
                      "Únete al equipo",
                      style: GoogleFonts.montserrat(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Activa tu perfil profesional y empieza a generar ingresos.",
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 40),

                    _buildSectionHeader("Información Personal"),
                    const SizedBox(height: 20),
                    _buildPremiumField(
                      _nameCtrl,
                      "Nombre Completo",
                      Icons.person_outline,
                      fieldKey: 'nombre',
                    ),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildIdTypeDropdown()),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: _buildPremiumField(
                            _docCtrl,
                            "Número ID",
                            Icons.badge_outlined,
                            type: TextInputType.number,
                            fieldKey: 'documento',
                            maxLength: 10,
                          ),
                        ),
                      ],
                    ),

                    _buildPremiumField(
                      _phoneCtrl,
                      "Número de Celular",
                      Icons.phone_android_outlined,
                      type: TextInputType.phone,
                      fieldKey: 'telefono',
                      maxLength: 10,
                    ),
                    _buildPremiumField(
                      _emailCtrl,
                      "Email",
                      Icons.alternate_email,
                      type: TextInputType.emailAddress,
                      fieldKey: 'email',
                    ),
                    _buildPremiumField(
                      _fvLicenciaCtrl,
                      "Vencimiento Licencia",
                      Icons.calendar_today_rounded,
                      readOnly: true,
                      onTap: _selectDate,
                      fieldKey: 'licencia',
                    ),
                    _buildPremiumField(
                      _passCtrl,
                      "Contraseña",
                      Icons.lock_outline_rounded,
                      isPass: true,
                      fieldKey: 'password',
                    ),
                    _buildPremiumField(
                      _confirmPassCtrl,
                      "Confirmar Contraseña",
                      Icons.lock_reset_rounded,
                      isPass: true,
                      fieldKey: 'confirmPassword',
                    ),

                    const SizedBox(height: 30),
                    _buildSectionHeader("Validación de Identidad"),
                    const SizedBox(height: 20),
                    _buildFileCard(
                      "Selfie de Verificación",
                      Icons.face_unlock_rounded,
                      _selfieFile != null,
                      () => _pickDocument(0),
                    ),
                    const SizedBox(height: 12),
                    _buildFileCard(
                      "Foto de Cédula",
                      Icons.badge_outlined,
                      _cedulaFile != null,
                      () => _pickDocument(1),
                    ),
                    const SizedBox(height: 12),

                    _buildFileCard(
                      "Licencia de Conducción", // <--- NUEVO CARD
                      Icons.drive_eta_rounded,
                      _licenciaFile != null,
                      () => _pickDocument(2),
                    ),

                    const SizedBox(height: 20),
                    _buildAceptacionDatos(),
                    const SizedBox(height: 40),
                    _buildSubmitButton(),
                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  // ignore: deprecated_member_use
                  backgroundColor: Colors.white.withOpacity(0.1),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.montserrat(
          fontWeight: FontWeight.w800,
          fontSize: 11,
          color: AppColors.primaryGreen,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildIdTypeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            "Tipo",
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
        Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Center(
            child: DropdownButton<String>(
              value: _tipoDocumento,
              dropdownColor: AppColors.surfaceDark,
              isExpanded: true,
              underline: const SizedBox(),
              icon: const Icon(
                Icons.keyboard_arrow_down,
                color: AppColors.primaryGreen,
              ),
              items: ['CC', 'CE', 'PPT'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(
                    value,
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _tipoDocumento = val!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
    bool readOnly = false,
    VoidCallback? onTap,
    bool isPass = false,
    String? fieldKey,
    int? maxLength,
  }) {
    bool hasError = fieldKey != null && (_fieldErrors[fieldKey] ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: hasError ? Colors.redAccent : Colors.white70,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasError
                  ? Colors.red.withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: TextFormField(
                controller: ctrl,
                readOnly: readOnly,
                onTap: onTap,
                obscureText: isPass && _obscurePass,
                keyboardType: type,
                maxLength: maxLength,
                onChanged: (val) {
                  if (fieldKey != null && hasError) {
                    // <--- Asegúrate de que tenga las llaves
                    setState(() => _fieldErrors[fieldKey] = false);
                  }
                },
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  counterText: "",
                  hintText: "Escribe aquí...",
                  hintStyle: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  prefixIcon: Icon(
                    icon,
                    color: hasError ? Colors.redAccent : AppColors.primaryGreen,
                    size: 22,
                  ),
                  suffixIcon: isPass
                      ? IconButton(
                          icon: Icon(
                            _obscurePass
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.white54,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: AppColors.primaryGreen,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileCard(
    String title,
    IconData icon,
    bool hasFile,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.primaryGreen.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasFile
                ? AppColors.primaryGreen
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle_rounded : icon,
              color: hasFile ? AppColors.primaryGreen : Colors.white54,
              size: 30,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    hasFile
                        ? "Documento cargado"
                        : "Toca para subir el archivo",
                    style: GoogleFonts.montserrat(
                      color: Colors.white54,
                      fontSize: 12,
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

  Widget _buildAceptacionDatos() {
    return Row(
      children: [
        Checkbox(
          value: _aceptaTerminos,
          activeColor: AppColors.primaryGreen,
          side: const BorderSide(color: Colors.white54),
          onChanged: (val) => setState(() => _aceptaTerminos = val ?? false),
        ),
        Expanded(
          child: Text(
            "Autorizo el tratamiento de mis datos personales (Ley 1581).",
            style: GoogleFonts.montserrat(
              fontSize: 11,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.35),
            blurRadius: 25,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                "REGÍSTRATE",
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
      ),
    );
  }
}
