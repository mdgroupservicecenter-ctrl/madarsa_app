import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/contributor_model.dart';
import '../bloc/contributors_bloc.dart';

class ContributorFormDialog extends StatefulWidget {
  final Contributor? contributor;

  const ContributorFormDialog({super.key, this.contributor});

  @override
  State<ContributorFormDialog> createState() => _ContributorFormDialogState();
}

class _ContributorFormDialogState extends State<ContributorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.contributor != null) {
      final c = widget.contributor!;
      _nameController.text = c.name;
      _phoneController.text = c.phone ?? '';
      _emailController.text = c.email ?? '';
      _addressController.text = c.address ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        'address': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
      };

      if (widget.contributor == null) {
        context.read<ContributorsBloc>().add(CreateContributorEvent(data));
      } else {
        context.read<ContributorsBloc>().add(UpdateContributorEvent(id: widget.contributor!.id, data: data));
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.contributor != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: min(480.0, MediaQuery.of(context).size.width - 32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 100 : 30),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(isEdit ? Icons.edit_rounded : Icons.person_add_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    isEdit ? 'Edit Contributor' : 'Add Contributor',
                    style: AppTheme.getFontStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildField(
                        label: 'Contributor Name *',
                        controller: _nameController,
                        icon: Icons.person_outline_rounded,
                        isDark: isDark,
                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        label: 'Mobile Number (10 Digits) *',
                        controller: _phoneController,
                        icon: Icons.phone_rounded,
                        isDark: isDark,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Mobile number is required';
                          }
                          final cleaned = v.trim().replaceAll(RegExp(r'\D'), '');
                          if (cleaned.length != 10) {
                            return 'Mobile number must be exactly 10 digits';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        label: 'Email Address',
                        controller: _emailController,
                        icon: Icons.email_rounded,
                        isDark: isDark,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        label: 'Address',
                        controller: _addressController,
                        icon: Icons.location_on_rounded,
                        isDark: isDark,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: AppTheme.getFontStyle()),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: Icon(isEdit ? Icons.save_rounded : Icons.add_rounded, size: 18),
                    label: Text(
                      isEdit ? 'Update' : 'Add',
                      style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      style: AppTheme.getFontStyle(fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.getFontStyle(
          fontSize: 13,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        prefixIcon: Icon(icon, size: 18, color: AppTheme.primaryColor),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }
}
