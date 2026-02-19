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
  Future<void> _pickFile(String key) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'], // Restricción estricta a PDF
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _documents[key] = result.files.first;
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Error seleccionando archivo: $e');
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        // Botón de regreso al registro
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Documentación',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.grey),
            tooltip: 'Simular Archivos (Dev)',
            onPressed: _simulateFilesForEmulator,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Text(
                    'Verificación de Identidad',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para habilitarte, sube tu Cédula y Licencia en formato PDF.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                children: _labels.entries.map((entry) {
                  return _buildUploadCard(entry.key, entry.value);
                }).toList(),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'ENVIAR A REVISIÓN',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard(String key, String label) {
    final file = _documents[key];
    final bool isUploaded = file != null;

    final borderColor = isUploaded
        ? AppColors.primaryGreen
        : Colors.grey.shade300;

    // Solución compatible para opacidad
    final bgColor = isUploaded
        ? AppColors.primaryGreen.withValues(alpha: 0.5)
        : Colors.white;

    final iconColor = isUploaded
        ? AppColors.primaryGreen
        : Colors.grey.shade400;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _pickFile(key),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isUploaded ? Colors.white : Colors.grey.shade50,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isUploaded
                          ? AppColors.primaryGreen.withValues(alpha: 0.2)
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    isUploaded
                        ? Icons.check_rounded
                        : Icons.cloud_upload_outlined,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isUploaded
                            ? (file.name.length > 25
                                  ? '${file.name.substring(0, 25)}...'
                                  : file.name)
                            : 'Toca para seleccionar PDF',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isUploaded
                              ? AppColors.primaryGreen
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUploaded)
                  const Icon(
                    Icons.picture_as_pdf, // Icono exclusivo PDF
                    color: Colors.redAccent,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
