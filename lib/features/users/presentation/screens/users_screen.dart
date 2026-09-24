import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../bloc/users_bloc.dart';
import '../bloc/users_event.dart';
import '../bloc/users_state.dart';
import '../widgets/add_edit_user_dialog.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    context.read<UsersBloc>().add(FetchUsersRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddEditUserDialog(List<Map<String, dynamic>> roles, {Map<String, dynamic>? user}) async {
    if (!_ensureFeatureAccess('users_roles', 'User Accounts & Roles')) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddEditUserDialog(
        user: user,
        availableRoles: roles,
      ),
    );

    if (result != null && mounted) {
      if (user == null) {
        context.read<UsersBloc>().add(CreateUserRequested(userData: result));
      } else {
        context.read<UsersBloc>().add(UpdateUserRequested(userId: user['id'], userData: result));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<UsersBloc, UsersState>(
      listener: (context, state) {
        if (state is UserActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else if (state is UsersError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Tools
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300,
                      ),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      decoration: InputDecoration(
                        hintText: context.tr('search_users_hint'),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        prefixIcon: const Icon(Icons.search_rounded),
                        prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                BlocBuilder<UsersBloc, UsersState>(
                  builder: (context, state) {
                    final roles = state is UsersLoaded ? state.availableRoles : <Map<String, dynamic>>[];
                    return ElevatedButton.icon(
                      onPressed: state is UsersLoaded 
                          ? () => _showAddEditUserDialog(roles)
                          : null,
                      icon: const Icon(Icons.person_add_rounded, size: 20),
                      label: Text(context.tr('add_user')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Users Data Table
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: BlocBuilder<UsersBloc, UsersState>(
                builder: (context, state) {
                  if (state is UsersLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is UsersLoaded) {
                    final filteredUsers = state.users.where((user) {
                      final search = _searchQuery.toLowerCase();
                      final fullName = (user['full_name'] ?? '').toLowerCase();
                      final username = (user['username'] ?? '').toLowerCase();
                      final email = (user['email'] ?? '').toLowerCase();
                      return fullName.contains(search) || 
                             username.contains(search) || 
                             email.contains(search);
                    }).toList();

                    if (filteredUsers.isEmpty) {
                      return Center(
                        child: Text(
                          context.tr('no_users_found'),
                          style: AppTheme.getFontStyle(color: Colors.grey.shade500),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 32,
                          headingRowHeight: 56,
                          headingTextStyle: AppTheme.getFontStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          columns: [
                            DataColumn(label: Text(context.tr('user_header'))),
                            DataColumn(label: Text(context.tr('username'))),
                            DataColumn(label: Text(context.tr('roles'))),
                            DataColumn(label: Text(context.tr('status'))),
                            DataColumn(label: Text(context.tr('joined'))),
                            DataColumn(label: Text(context.tr('actions'))),
                          ],
                          rows: filteredUsers.map((user) {
                            final isActive = user['is_active'] == 1;
                            final userRoles = (user['roles'] as List?) ?? [];
                            final rolesStr = userRoles.map((r) => r['name']).join(', ');

                            return DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: AppTheme.primaryColor.withAlpha(40),
                                        child: Text(
                                          (user['full_name'] ?? 'U')[0].toUpperCase(),
                                          style: TextStyle(
                                            color: AppTheme.primaryColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user['full_name'] ?? '',
                                            style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                                          ),
                                          if (user['email'] != null && user['email'].toString().isNotEmpty)
                                            Text(
                                              user['email'],
                                              style: AppTheme.getFontStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(user['username'] ?? '')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppTheme.infoColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      rolesStr.isEmpty ? 'None' : rolesStr,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 12,
                                        color: AppTheme.infoColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive 
                                          ? AppTheme.successColor.withAlpha(20)
                                          : AppTheme.errorColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isActive ? AppTheme.successColor : AppTheme.errorColor,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          isActive ? context.tr('active') : context.tr('inactive'),
                                          style: AppTheme.getFontStyle(
                                            fontSize: 12,
                                            color: isActive ? AppTheme.successColor : AppTheme.errorColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(Text(
                                  (user['created_at']?.toString().split(' ')[0]) ?? '',
                                  style: AppTheme.getFontStyle(fontSize: 13),
                                )),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_rounded, size: 18),
                                        onPressed: () => _showAddEditUserDialog(state.availableRoles, user: user),
                                        tooltip: context.tr('edit_user'),
                                        color: AppTheme.primaryColor,
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                          size: 18,
                                        ),
                                        tooltip: isActive ? context.tr('deactivate') : context.tr('activate'),
                                        color: isActive ? AppTheme.errorColor : AppTheme.successColor,
                                        onPressed: () {
                                          if (!_ensureFeatureAccess('users_roles', 'User Accounts & Roles')) return;
                                          context.read<UsersBloc>().add(
                                            UpdateUserRequested(
                                              userId: user['id'],
                                              userData: {'isActive': !isActive},
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  }

                  return const SizedBox();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
