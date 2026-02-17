import 'dart:io';
import 'package:file_picker/file_picker.dart'; // NUEVO IMPORT
import 'package:flutter/material.dart';
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

  // Mapa para guardar los archivos seleccionados
  final Map<String, PlatformFile?> _documents = {
    'license_front': null,
    'license_back': null,
    'property_card': null,
    'soat': null,
  };

  final Map<String, String> _labels = {
    'license_front': 'Licencia (Frente)',
    'license_back': 'Licencia (Reverso)',
    'property_card': 'Tarjeta de Propiedad',
    'soat': 'SOAT Vigente',
  };

  // --- LÓGICA DE SELECCIÓN DE ARCHIVOS (REAL) ---
  Future<void> _pickFile(String key) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], // PERMITE PDF
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _documents[key] = result.files.first;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error seleccionando archivo: $e')),
      );
    }
  }

  // --- LÓGICA MOCK PARA EMULADOR (SOLO DEV) ---
  void _simulateFilesForEmulator() {
    setState(() {
      // Llenamos con "archivos fantasma" para poder pasar la validación
      for (var key in _documents.keys) {
        _documents[key] = PlatformFile(
          name: 'simulacion_$key.pdf',
          size: 1024,
          path: '/dev/null',
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('⚡ Archivos simulados cargados')),
    );
  }

  // --- LÓGICA DE ENVÍO ---
  Future<void> _submitAll() async {
    if (_documents.containsValue(null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Faltan documentos obligatorios.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Enviamos cada archivo
      for (var entry in _documents.entries) {
        final platformFile = entry.value!;

        // Convertimos PlatformFile a File para la subida real
        // NOTA: En Mock, el path puede ser inválido, el servicio lo ignorará si es MockOnly
        File fileToUpload = File(platformFile.path!);

        await _authService.uploadDocument(entry.key, fileToUpload);
      }

      await _authService.submitDocumentsForReview();

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const VerificationCheckScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentación Legal'),
        automaticallyImplyLeading: false,
        actions: [
          // BOTÓN MÁGICO PARA EMULADOR
          IconButton(
            icon: const Icon(
              Icons.auto_fix_high,
              color: Colors.blue,
            ), // Varita mágica
            tooltip: 'Simular Archivos (Dev)',
            onPressed: _simulateFilesForEmulator,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              _authService.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              children: const [
                Icon(Icons.info_outline, color: Colors.blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sube tus documentos en PDF o Foto legible para agilizar el FUEC.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _labels.entries.map((entry) {
                return _buildDocTile(entry.key, entry.value);
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('ENVIAR DOCUMENTOS'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocTile(String key, String label) {
    final file = _documents[key];
    final bool isUploaded = file != null;

    // Determinar icono según extensión
    IconData fileIcon = Icons.insert_drive_file;
    Color iconColor = Colors.grey;

    if (isUploaded) {
      final ext = file.extension?.toLowerCase() ?? '';
      if (ext == 'pdf') {
        fileIcon = Icons.picture_as_pdf;
        iconColor = Colors.red;
      } else if (['jpg', 'jpeg', 'png'].contains(ext)) {
        fileIcon = Icons.image;
        iconColor = Colors.green;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isUploaded
              ? Colors.green.shade50
              : Colors.grey.shade100,
          child: Icon(
            isUploaded ? Icons.check : Icons.upload_file,
            color: isUploaded ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          // Simplemente usa la variable directa. Dart sabe que 'file' existe aquí.
          isUploaded ? file.name : 'Seleccionar PDF o Imagen',
          style: TextStyle(color: isUploaded ? Colors.black87 : Colors.grey),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isUploaded
            ? Icon(fileIcon, color: iconColor)
            : const Icon(Icons.chevron_right),
        onTap: () => _pickFile(key),
      ),
    );
  }
}
