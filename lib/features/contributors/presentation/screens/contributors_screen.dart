import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/contributor_model.dart';
import '../bloc/contributors_bloc.dart';
import '../widgets/contributor_form_dialog.dart';
import 'contributor_profile_screen.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';

class ContributorsScreen extends StatefulWidget {
  const ContributorsScreen({super.key});

  @override
  State<ContributorsScreen> createState() => _ContributorsScreenState();
}

class _ContributorsScreenState extends State<ContributorsScreen> {
  final _searchController = TextEditingController();
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
    context.read<ContributorsBloc>().add(LoadContributors());
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showFormDialog([Contributor? contributor]) {
    if (!_ensureFeatureAccess('donors_records', 'Donor Database')) return;

    showDialog(
      context: context,
      builder: (dialogContext) => BlocProvider.value(
        value: context.read<ContributorsBloc>(),
        child: ContributorFormDialog(contributor: contributor),
      ),
    );
  }

  void _confirmDelete(String id, String name) {
    if (!_ensureFeatureAccess('donors_records', 'Donor Database')) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('delete_contributor'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          context.tr('delete_contributor_confirm').replaceAll('{name}', name),
          style: AppTheme.getFontStyle(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel'), style: AppTheme.getFontStyle()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ContributorsBloc>().add(DeleteContributorEvent(id));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: Text(context.tr('delete'), style: AppTheme.getFontStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: BlocBuilder<ContributorsBloc, ContributorsState>(
        builder: (context, state) {
          if (state is ContributorsLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ContributorsError) {
            return Center(
              child: Text(
                state.message,
                style: AppTheme.getFontStyle(color: AppTheme.errorColor),
              ),
            );
          }
          if (state is ContributorsLoaded) {
            final list = state.contributors;
            
            // Filter local list based on query
            final filtered = list.where((c) {
              final name = c.name.toLowerCase();
              final phone = (c.phone ?? '').toLowerCase();
              final email = (c.email ?? '').toLowerCase();
              return name.contains(_searchQuery) ||
                     phone.contains(_searchQuery) ||
                     email.contains(_searchQuery);
            }).toList();

            // Calculate aggregations
            final totalContributors = list.length;
            final totalStudents = list.fold<int>(0, (sum, c) => sum + c.totalStudentsHelped);
            final totalContribution = list.fold<double>(0, (sum, c) => sum + c.totalContributionAmount);

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stat Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          title: context.tr('total_contributors'),
                          value: '$totalContributors',
                          icon: Icons.people_rounded,
                          color: AppTheme.primaryColor,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: context.tr('sponsored_students'),
                          value: '$totalStudents',
                          icon: Icons.school_rounded,
                          color: Colors.blue.shade700,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          title: context.tr('total_sponsoring_monthly'),
                          value: '₹${totalContribution.toStringAsFixed(0)}',
                          icon: Icons.currency_rupee_rounded,
                          color: Colors.orange.shade700,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Actions Bar
                  Row(
                    children: [
                      // Search Field
                      Expanded(
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                            ),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: AppTheme.getFontStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: context.tr('search_contributors_hint'),
                              hintStyle: AppTheme.getFontStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 18,
                                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Add button
                      FilledButton.icon(
                        onPressed: () => _showFormDialog(),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(
                          context.tr('add_contributor'),
                          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Content Table
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF161625) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _searchQuery.isEmpty
                                    ? context.tr('no_contributors_found')
                                    : context.tr('no_match_found'),
                                style: AppTheme.getFontStyle(color: Colors.grey.shade500),
                              ),
                            )
                          : ListView(
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columnSpacing: 34,
                                    headingRowColor: WidgetStateProperty.all(
                                      isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
                                    ),
                                    columns: [
                                      DataColumn(label: Text(context.tr('contributor_name'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('mobile'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('email'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('address'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('students'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('contribution'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text(context.tr('actions'), style: AppTheme.getFontStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: filtered.map((c) {
                                      return DataRow(cells: [
                                        DataCell(Text(c.name, style: AppTheme.getFontStyle(fontWeight: FontWeight.w600))),
                                        DataCell(Text(c.phone ?? '-', style: AppTheme.getFontStyle())),
                                        DataCell(Text(c.email ?? '-', style: AppTheme.getFontStyle())),
                                        DataCell(
                                          SizedBox(
                                            width: 140,
                                            child: Text(
                                              c.address ?? '-',
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTheme.getFontStyle(),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryColor.withAlpha(20),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${c.totalStudentsHelped}',
                                              style: AppTheme.getFontStyle(
                                                color: AppTheme.primaryColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '₹${c.totalContributionAmount.toStringAsFixed(0)}',
                                            style: AppTheme.getFontStyle(
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.visibility_rounded, size: 18),
                                                color: AppTheme.primaryColor,
                                                onPressed: () {
                                                  if (!_ensureFeatureAccess('donors_records', 'Donor Database')) return;
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ContributorProfileScreen(
                                                        contributorId: c.id,
                                                      ),
                                                    ),
                                                  ).then((_) => context.read<ContributorsBloc>().add(LoadContributors()));
                                                },
                                                tooltip: 'View Profile',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_rounded, size: 18),
                                                color: Colors.blue.shade700,
                                                onPressed: () => _showFormDialog(c),
                                                tooltip: 'Edit Info',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_rounded, size: 18),
                                                color: AppTheme.errorColor,
                                                onPressed: () => _confirmDelete(c.id, c.name),
                                                tooltip: 'Delete Contributor',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ]);
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            );
          }
          return Center(child: Text(context.tr('no_data')));
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.getFontStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
