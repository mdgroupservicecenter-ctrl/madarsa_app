import 'package:madarsa_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';


import 'package:google_fonts/google_fonts.dart';


import 'package:provider/provider.dart';


import 'package:dio/dio.dart';


import '../../../../core/network/api_client.dart';


import '../../data/repositories/settings_repository.dart';



class WebsiteSettingsScreen extends StatefulWidget {
  const WebsiteSettingsScreen({super.key});

  @override
  State<WebsiteSettingsScreen> createState() => _WebsiteSettingsScreenState();
}

class _WebsiteSettingsScreenState extends State<WebsiteSettingsScreen> {
  late final SettingsRepository _repository;
  bool _isLoading = true;

  final _aboutController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _mapUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = SettingsRepository(ApiClient());
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await _repository.getWebsiteSettings();
      setState(() {
        _aboutController.text = data['website_about'] ?? '';
        _phoneController.text = data['website_contact_phone'] ?? '';
        _emailController.text = data['website_contact_email'] ?? '';
        _addressController.text = data['website_address'] ?? '';
        _mapUrlController.text = data['website_map_url'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await _repository.updateWebsiteSettings({
        'website_about': _aboutController.text,
        'website_contact_phone': _phoneController.text,
        'website_contact_email': _emailController.text,
        'website_address': _addressController.text,
        'website_map_url': _mapUrlController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('website_settings_saved'))));
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString();
        if (e is DioException) {
          errorMsg = e.response?.data?['error'] ?? e.message ?? e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save settings: $errorMsg')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Website Content', style: AppTheme.getFontStyle()),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(context.tr('save_changes')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('About Madarsa'),
            const SizedBox(height: 12),
            TextField(
              controller: _aboutController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: context.tr('enter_about_us_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('Contact Information'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: context.tr('email_address'), border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Physical Address', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('Location Map'),
            const SizedBox(height: 12),
            TextField(
              controller: _mapUrlController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.tr('google_maps_embed_url'),
                hintText: 'https://www.google.com/maps/embed?...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.map),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'To get this URL: Go to Google Maps -> Search Location -> Share -> Embed a map -> Copy the src URL inside the iframe.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.w600),
    );
  }
}
