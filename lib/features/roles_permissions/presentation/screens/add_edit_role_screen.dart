import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/roles_bloc.dart';
import '../bloc/roles_event.dart';

class AddEditRoleScreen extends StatefulWidget {
  final Map<String, dynamic>? role;
  final Map<String, dynamic> permissionsData;

  const AddEditRoleScreen({
    super.key,
    this.role,
    required this.permissionsData,
  });

  @override
  State<AddEditRoleScreen> createState() => _AddEditRoleScreenState();
}

class _AddEditRoleScreenState extends State<AddEditRoleScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  
  // Set of selected permission IDs
  final Set<String> _selectedPermissions = {};

  final List<String> _orderedActions = ['view', 'create', 'edit', 'delete'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role?['name'] ?? '');
    _descController = TextEditingController(text: widget.role?['description'] ?? '');

    // If editing a role, populate existing permissions
    if (widget.role != null && widget.role!['permissions'] != null) {
      final perms = widget.role!['permissions'] as List;
      for (var p in perms) {
        _selectedPermissions.add(p['id'].toString());
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _saveRole() {
    if (_formKey.currentState!.validate()) {
      final roleData = {
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'permissionIds': _selectedPermissions.toList(),
      };

      if (widget.role == null) {
        context.read<RolesBloc>().add(CreateRoleRequested(roleData: roleData));
      } else {
        context.read<RolesBloc>().add(UpdateRoleRequested(id: widget.role!['id'], roleData: roleData));
      }
      Navigator.pop(context);
    }
  }

  void _toggleModuleAll(String module, List dynamicPerms, bool selectAll) {
    setState(() {
      for (var p in dynamicPerms) {
        if (selectAll) {
          _selectedPermissions.add(p['id'].toString());
        } else {
          _selectedPermissions.remove(p['id'].toString());
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSystemRole = widget.role?['is_system'] == 1;

    final groupedPermissions = widget.permissionsData['grouped'] as Map<String, dynamic>;
    final moduleNames = groupedPermissions.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.role == null ? 'Create Custom Role' : 'Edit Role'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Details Header
            Container(
              padding: const EdgeInsets.all(24),
              color: isDark ? const Color(0xFF161625) : Colors.white,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _nameController,
                      enabled: !isSystemRole,
                      decoration: const InputDecoration(
                        labelText: 'Role Name *',
                        prefixIcon: Icon(Icons.badge_rounded),
                      ),
                      validator: (val) => val!.isEmpty ? 'Name required' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _descController,
                      decoration: InputDecoration(
                        labelText: context.tr('description'),
                        prefixIcon: Icon(Icons.description_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton.icon(
                    onPressed: _saveRole,
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: Text(context.tr('save_role')),
                  ),
                ],
              ),
            ),
            
            // Permissions Matrix Grid
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  children: [
                    // Grid Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFF0F2F5),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'MODULE (Select All)',
                              style: AppTheme.getFontStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          for (var action in _orderedActions)
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Text(
                                  action.toUpperCase(),
                                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    // Grid Body
                    Expanded(
                      child: ListView.separated(
                        itemCount: moduleNames.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) {
                          final moduleName = moduleNames[index];
                          final perms = groupedPermissions[moduleName] as List;
                          
                          // Check if all available perms for this module are selected
                          final allSelected = perms.every((p) => _selectedPermissions.contains(p['id'].toString()));

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: allSelected,
                                        activeColor: AppTheme.primaryColor,
                                        onChanged: (val) => _toggleModuleAll(moduleName, perms, val ?? false),
                                      ),
                                      Text(
                                        moduleName.toUpperCase(),
                                        style: AppTheme.getFontStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                for (var action in _orderedActions)
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: _buildPermissionCheckbox(perms, action),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionCheckbox(List dynamicPerms, String targetAction) {
    // Find the permission matching this action
    final permMatch = dynamicPerms.where((p) => p['action'] == targetAction).toList();
    if (permMatch.isEmpty) return const Text('-'); // No such permission defined

    final perm = permMatch.first;
    final permId = perm['id'].toString();
    final isSelected = _selectedPermissions.contains(permId);

    // Some logic: If you have create/edit/delete, you intuitively MUST have view.
    // In advanced designs we auto-check view, but here we keep it raw RBAC.
    return Checkbox(
      value: isSelected,
      activeColor: AppTheme.primaryColor,
      onChanged: (val) {
        setState(() {
          if (val == true) {
            _selectedPermissions.add(permId);
            // Auto select 'view' if any other action is selected
            if (targetAction != 'view') {
              final viewPerm = dynamicPerms.where((p) => p['action'] == 'view').toList();
              if (viewPerm.isNotEmpty) {
                _selectedPermissions.add(viewPerm.first['id'].toString());
              }
            }
          } else {
            _selectedPermissions.remove(permId);
            // If view is unselected, unselect all others logically?
            if (targetAction == 'view') {
               for (var p in dynamicPerms) {
                 _selectedPermissions.remove(p['id'].toString());
               }
            }
          }
        });
      },
    );
  }
}
