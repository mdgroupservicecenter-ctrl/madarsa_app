import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:madarsa_app/core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/roles_bloc.dart';
import '../bloc/roles_event.dart';
import '../bloc/roles_state.dart';
import 'add_edit_role_screen.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
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
    context.read<RolesBloc>().add(FetchRolesRequested());
  }

  void _navigateToRoleForm(BuildContext context, Map<String, dynamic> permissionsData, {Map<String, dynamic>? role}) {
    if (!_ensureFeatureAccess('users_permissions', 'User Roles & Permissions')) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<RolesBloc>(),
          child: AddEditRoleScreen(
            role: role,
            permissionsData: permissionsData,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<RolesBloc, RolesState>(
      listener: (context, state) {
        if (state is RoleActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppTheme.successColor),
          );
        } else if (state is RolesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: AppTheme.errorColor),
          );
        }
      },
      builder: (context, state) {
        if (state is RolesLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is RolesLoaded) {
          final roles = state.roles;
          final permissionsData = state.permissionsData;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header actions
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        if (!_ensureFeatureAccess('users_permissions', 'User Roles & Permissions')) return;
                        if (permissionsData != null) {
                          _navigateToRoleForm(context, permissionsData);
                        }
                      },
                      icon: const Icon(Icons.add_moderator_rounded, size: 20),
                      label: Text(context.tr('create_custom_role')),
                    )
                  ],
                ),
              ),

              // Roles Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 24,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: roles.length,
                  itemBuilder: (context, index) {
                    final role = roles[index];
                    final isSystem = role['is_system'] == 1;
                    final isActive = role['is_active'] == 1;
                    final userCount = role['user_count'] ?? 0;

                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSystem 
                              ? AppTheme.accentColor.withAlpha(50)
                              : (isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 30 : 5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSystem ? AppTheme.accentColor.withAlpha(30) : AppTheme.primaryColor.withAlpha(20),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isSystem ? context.tr('system_role') : context.tr('custom_role'),
                                  style: AppTheme.getFontStyle(
                                    fontSize: 11,
                                    color: isSystem ? AppTheme.accentColor : AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (!isSystem)
                                IconButton(
                                  icon: Icon(
                                    isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                    size: 20,
                                    color: isActive ? AppTheme.errorColor : AppTheme.successColor,
                                  ),
                                  onPressed: () {
                                    if (!_ensureFeatureAccess('users_permissions', 'User Roles & Permissions')) return;
                                    context.read<RolesBloc>().add(ToggleRoleStatusRequested(id: role['id']));
                                  },
                                  tooltip: isActive ? context.tr('deactivate_role') : context.tr('activate_role'),
                                )
                            ],
                          ),
                          const Spacer(),
                          Text(
                            role['name'],
                            style: AppTheme.getFontStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            role['description'] ?? context.tr('no_description'),
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.people_rounded, size: 16, color: Colors.grey.shade500),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$userCount ${context.tr('users_count')}',
                                    style: AppTheme.getFontStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              if (!isSystem)
                                TextButton.icon(
                                  onPressed: () {
                                    if (permissionsData != null) {
                                      _navigateToRoleForm(context, permissionsData, role: role);
                                    }
                                  },
                                  icon: const Icon(Icons.edit_note_rounded, size: 16),
                                  label: Text(context.tr('edit_permissions')),
                                )
                            ],
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }
        return const SizedBox();
      },
    );
  }
}
