import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/students_bloc.dart';

class DocumentUploadDialog extends StatefulWidget {
  final String studentId;

  const DocumentUploadDialog({super.key, required this.studentId});

  @override
  State<DocumentUploadDialog> createState() => _DocumentUploadDialogState();
}

class _DocumentUploadDialogState extends State<DocumentUploadDialog> {
  final _nameController = TextEditingController();
  PlatformFile? _selectedFile;
  bool _isUploading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  void _upload() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('enter_document_name'))));
      return;
    }
    if (_selectedFile == null || _selectedFile!.path == null) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('select_file_error'))));
       return;
    }

    setState(() {
      _isUploading = true;
    });

    context.read<StudentsBloc>().add(UploadStudentDocument(
      studentId: widget.studentId,
      documentName: _nameController.text.trim(),
      filePath: _selectedFile!.path!,
    ));

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8 * scale),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0D6B4E).withAlpha(20),
            ),
            child: Icon(Icons.upload_file_rounded, size: 18 * scale, color: const Color(0xFF0D6B4E)),
          ),
          SizedBox(width: 10 * scale),
          Expanded(
            child: Text(
              context.tr('upload_document'),
              style: TextStyle(
                fontSize: 17 * scale,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 14 * scale),
              decoration: InputDecoration(
                labelText: context.tr('document_name'),
                hintText: context.tr('birth_cert_eg'),
                labelStyle: TextStyle(fontSize: 13 * scale),
                hintStyle: TextStyle(fontSize: 13 * scale),
              ),
            ),
            SizedBox(height: 16 * scale),
            if (_selectedFile != null)
              Container(
                padding: EdgeInsets.all(12 * scale),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(10 * scale),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    Icon(Icons.file_present_rounded, color: Colors.blue, size: 20 * scale),
                    SizedBox(width: 8 * scale),
                    Expanded(
                      child: Text(
                        _selectedFile!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13 * scale),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 18 * scale),
                      onPressed: () => setState(() => _selectedFile = null),
                    )
                  ],
                ),
              ),
            if (_selectedFile == null)
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: Icon(Icons.folder_open_rounded, size: 18 * scale),
                label: Text(context.tr('choose_file'), style: TextStyle(fontSize: 13 * scale)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
                ),
              )
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel'), style: TextStyle(fontSize: 13 * scale)),
        ),
        FilledButton(
          onPressed: _isUploading ? null : _upload,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0D6B4E),
            padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 10 * scale),
          ),
          child: _isUploading
              ? SizedBox(width: 18 * scale, height: 18 * scale, child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(context.tr('upload'), style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w600)),
        )
      ],
    );
  }
}
