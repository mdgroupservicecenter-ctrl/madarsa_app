import 'package:madarsa_app/core/theme/app_theme.dart';
import 'dart:io';


import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';


import 'package:google_fonts/google_fonts.dart';


import 'package:provider/provider.dart';


import 'package:file_picker/file_picker.dart';


import '../../../../core/network/api_client.dart';


import '../../../../core/constants/app_constants.dart';


import '../../data/repositories/settings_repository.dart';



class GalleryManagementScreen extends StatefulWidget {
  const GalleryManagementScreen({super.key});

  @override
  State<GalleryManagementScreen> createState() => _GalleryManagementScreenState();
}

class _GalleryManagementScreenState extends State<GalleryManagementScreen> {
  late final SettingsRepository _repository;
  bool _isLoading = true;
  List<dynamic> _images = [];

  @override
  void initState() {
    super.initState();
    _repository = SettingsRepository(ApiClient());
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.getGallery();
      setState(() {
        _images = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load gallery: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final filePath = result.files.single.path!;
        
        // Let's ask for title before uploading
        String? title = await _showTitleDialog();
        
        await _repository.uploadGalleryImage(filePath, title ?? 'Madarsa Photo', 'General');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('image_uploaded'))));
        }
        _loadGallery(); // Refresh
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload image: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _showTitleDialog() async {
    String title = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('add_photo_title')),
        content: TextField(
          decoration: const InputDecoration(hintText: 'e.g., Annual Function 2023'),
          onChanged: (value) => title = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, title), child: Text(context.tr('upload'))),
        ],
      ),
    );
  }

  Future<void> _deleteImage(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('delete_image_title')),
        content: Text(context.tr('confirm_delete_image')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true), 
            child: Text(context.tr('delete'))
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _repository.deleteGalleryImage(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('image_deleted'))));
      }
      _loadGallery();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete image: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Website Gallery', style: AppTheme.getFontStyle()),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _uploadImage,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: Text(context.tr('add_photo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _images.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text('No photos added yet', style: AppTheme.getFontStyle(color: Colors.grey.shade600, fontSize: 16)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                final img = _images[index];
                // Note: img['image_path'] is relative (e.g. /uploads/gallery/xyz)
                // We construct the full URL to load it in the desktop app
                final imageUrl = '${ApiConstants.baseUrl.replaceAll("/api", "")}${img['image_path']}';
                
                return Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          color: Colors.black.withAlpha(180),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(
                            img['title'] ?? '',
                            style: AppTheme.getFontStyle(color: Colors.white, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 14,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                            onPressed: () => _deleteImage(img['id']),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
