import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';

class AddEditUserDialog extends StatefulWidget {
  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> availableRoles;

  const AddEditUserDialog({
    super.key,
    this.user,
    required this.availableRoles,
  });

  @override
  State<AddEditUserDialog> createState() => _AddEditUserDialogState();
}

class _AddEditUserDialogState extends State<AddEditUserDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _usernameController;
  late TextEditingController _fullNameController;
  late TextEditingController _passwordController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  
  bool _isActive = true;
  List<String> _selectedRoleIds = [];
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user?['username'] ?? '');
    _fullNameController = TextEditingController(text: widget.user?['full_name'] ?? '');
    _passwordController = TextEditingController();
    _emailController = TextEditingController(text: widget.user?['email'] ?? '');
    _phoneController = TextEditingController(text: widget.user?['phone'] ?? '');
    
    if (widget.user != null) {
      _isActive = widget.user!['is_active'] == 1;
      if (widget.user!['roles'] != null) {
        _selectedRoleIds = (widget.user!['roles'] as List)
            .map((r) => r['id'].toString())
            .toList();
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final userData = {
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'roleIds': _selectedRoleIds,
        'isActive': _isActive,
      };

      if (widget.user == null) {
        // Validation for new users
        userData['username'] = _usernameController.text.trim();
        userData['password'] = _passwordController.text;
      } else if (_passwordController.text.isNotEmpty) {
        // Password update for existing user is usually a separate flow, 
        // but if we handle it here, it requires 'reset_password' action.
        // For simplicity, we just pass what we can or let parent handle it.
      }

      Navigator.of(context).pop(userData);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.user != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      child: Container(
        width: min(500.0, MediaQuery.of(context).size.width - 32),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEditing ? 'Edit User' : 'Add New User',
                      style: AppTheme.getFontStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Username (Disabled when editing)
                TextFormField(
                  controller: _usernameController,
                  enabled: !isEditing,
                  decoration: InputDecoration(
                    labelText: 'Username *',
                    prefixIcon: const Icon(Icons.account_circle_rounded),
                  ),
                  validator: (value) => value!.isEmpty ? 'Required field' : null,
                ),
                const SizedBox(height: 16),
                
                // Full Name
                TextFormField(
                  controller: _fullNameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) => value!.isEmpty ? 'Required field' : null,
                ),
                const SizedBox(height: 16),

                // Password (Only required on creation)
                if (!isEditing)
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) => !isEditing && value!.isEmpty ? 'Required field' : null,
                  ),
                if (!isEditing) const SizedBox(height: 16),

                // Email
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 24),

                // Roles Selection
                Text(
                  'Assign Roles',
                  style: AppTheme.getFontStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.availableRoles.map((role) {
                    final isSelected = _selectedRoleIds.contains(role['id']);
                    return FilterChip(
                      selected: isSelected,
                      label: Text(role['name']),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedRoleIds.add(role['id']);
                          } else {
                            _selectedRoleIds.remove(role['id']);
                          }
                        });
                      },
                      selectedColor: AppTheme.primaryColor.withAlpha(40),
                      checkmarkColor: AppTheme.primaryColor,
                      labelStyle: AppTheme.getFontStyle(
                        color: isSelected && !isDark ? AppTheme.primaryColor : null,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Active Status
                SwitchListTile(
                  title: Text(
                    'Active Account',
                    style: AppTheme.getFontStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Can log in to the system',
                    style: AppTheme.getFontStyle(fontSize: 12),
                  ),
                  value: _isActive,
                  activeColor: AppTheme.primaryColor,
                  onChanged: (value) => setState(() => _isActive = value),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 32),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        context.tr('cancel'),
                        style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _submit,
                      child: Text(
                        context.tr('save'),
                        style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
