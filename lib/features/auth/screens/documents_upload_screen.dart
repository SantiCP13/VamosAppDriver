import 'dart:io';
import 'dart:typed_data'; // Necesario para Uint8List en modo Mock
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../services/driver_auth_service.dart';
import 'verification_check_screen.dart';

class DocumentsUploadScreen extends StatefulWidget {
  const DocumentsUploadScreen({super.key});

  @override
  State<DocumentsUploadScreen> createState() => _DocumentsUploadScreenState();
}

class _DocumentsUploadScreenState extends State<DocumentsUploadScreen> {
  final DriverAuthService _authService = DriverAuthService();
  bool _isSubmitting = false;

  // --- LÓGICA DE NEGOCIO: DOCUMENTOS DE CONDUCTOR ---
  // Simplificado: 1 PDF para Cédula, 1 PDF para Licencia
  final Map<String, PlatformFile?> _documents = {
    'cedula': null,
    'license': null,
  };

  final Map<String, String> _labels = {
    'cedula': 'Cédula de Ciudadanía (PDF)',
    'license': 'Licencia de Conducción (PDF)',
  };

  // --- SELECCIÓN DE ARCHIVOS (SOLO PDF) ---
  // --- SELECCIÓN DE ARCHIVOS (SOLO PDF) ---
  Future<void> _pickFile(String key) async {
    if (_isSubmitting) return;

    try {
      // Uso de FilePicker.platform.pickFiles
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _documents[key] = result.files.first;
        });
      }
    } catch (e) {
      debugPrint("Error FilePicker: $e");
      _showErrorSnackBar('Error seleccionando archivo.');
    }
  }

  // --- SIMULACIÓN DEV (MOCKS) ---
  void _simulateFilesForEmulator() {
    setState(() {
      for (var key in _documents.keys) {
        _documents[key] = PlatformFile(
          name: 'simulacion_${key}_mock.pdf',
          size: 1024,
          path: '/dev/null',
          bytes: Uint8List.fromList([0, 1, 2]),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '⚡ Archivos PDF simulados cargados (Dev)',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.amber[700],
      ),
    );
  }

  // --- ENVÍO DE FORMULARIO ---
  Future<void> _submitAll() async {
    if (_documents.containsValue(null)) {
      _showErrorSnackBar('Debes cargar ambos documentos obligatorios.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      for (var entry in _documents.entries) {
        final platformFile = entry.value!;
        // Manejo seguro del File (Mock vs Real)
        File fileToUpload = File(platformFile.path ?? '');
        await _authService.uploadDocument(entry.key, fileToUpload);
      }

      await _authService.submitDocumentsForReview();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerificationCheckScreen()),
      );
    } catch (e) {
      _showErrorSnackBar('Error al subir documentos. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Documentación',
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          // SOLUCIÓN AL ERROR: Botón para usar la función simuladora
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: Colors.white30),
            onPressed: _simulateFilesForEmulator,
            tooltip: "Simular archivos (Modo Dev)",
          ),
        ],
      ),
      body: Stack(
        children: [
          // Fondo oscuro igual al registro
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.45),
                radius: 1.8,
                colors: [AppColors.surfaceDark, AppColors.darkBlue],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.primaryGreen,
                        size: 50,
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'Verificación Legal',
                        style: GoogleFonts.montserrat(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Para habilitarte como conductor profesional, necesitamos estos documentos en PDF.',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          color: Colors.white60,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    children: _labels.entries.map((entry) {
                      return _buildUploadCard(entry.key, entry.value);
                    }).toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: _buildSubmitButton(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard(String key, String label) {
    final file = _documents[key];
    final bool isUploaded = file != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isUploaded
            ? AppColors.primaryGreen.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUploaded ? AppColors.primaryGreen : Colors.white10,
          width: 1.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isUploaded
                ? AppColors.primaryGreen
                : Colors.white.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isUploaded ? Icons.task_alt_rounded : Icons.picture_as_pdf_rounded,
            color: Colors.white,
          ),
        ),
        title: Text(
          label,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          isUploaded ? file.name : "Click para seleccionar PDF",
          style: GoogleFonts.montserrat(
            color: isUploaded ? AppColors.primaryGreen : Colors.white38,
            fontSize: 12,
          ),
        ),
        onTap: () => _pickFile(key),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submitAll,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: _isSubmitting
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                'ENVIAR DOCUMENTACIÓN',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}
