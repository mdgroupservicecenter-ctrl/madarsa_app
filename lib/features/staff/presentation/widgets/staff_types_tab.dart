import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import 'package:dio/dio.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/platform_utils.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_service.dart';

/// Staff Administration tab — manages Staff Types & Qualifications
class StaffTypesTab extends StatefulWidget {
  const StaffTypesTab({super.key});

  @override
  State<StaffTypesTab> createState() => _StaffTypesTabState();
}

class _StaffTypesTabState extends State<StaffTypesTab> {
  // 0 = Staff Types, 1 = Qualifications
  int _activeSection = 0;

  List<Map<String, dynamic>> _staffTypes = [];
  List<Map<String, dynamic>> _qualifications = [];
  bool _loadingTypes = true;
  bool _loadingQuals = true;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTypes();
    _loadQualifications();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  ApiClient get _apiClient => ApiClient();

  // ── Load Data ──────────────────────────────────────────────────────────────
  Future<void> _loadTypes() async {
    setState(() => _loadingTypes = true);
    try {
      final resp = await _apiClient.get('/staff/types');
      final dynamic raw = resp.data;
      List data = [];
      if (raw is List) data = raw;
      else if (raw is Map && raw['data'] is List) data = raw['data'];
      setState(() {
        _staffTypes = List<Map<String, dynamic>>.from(data);
        _loadingTypes = false;
      });
    } catch (_) {
      setState(() => _loadingTypes = false);
    }
  }

  Future<void> _loadQualifications() async {
    setState(() => _loadingQuals = true);
    try {
      final resp = await _apiClient.get('/staff/qualifications');
      final dynamic raw = resp.data;
      List data = [];
      if (raw is List) data = raw;
      else if (raw is Map && raw['data'] is List) data = raw['data'];
      setState(() {
        _qualifications = List<Map<String, dynamic>>.from(data);
        _loadingQuals = false;
      });
    } catch (_) {
      setState(() => _loadingQuals = false);
    }
  }

  // ── CRUD ────────────────────────────────────────────────────────────────────
  Future<void> _addItem() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final endpoint =
        _activeSection == 0 ? '/staff/types' : '/staff/qualifications';
    final label = _activeSection == 0 ? 'Staff type' : 'Qualification';
    try {
      await _apiClient.post(endpoint, data: {
        'name': name,
        'description': _descCtrl.text.trim(),
      });
      if (_activeSection == 0) {
        FirebaseService.syncStaffTypes();
      } else {
        FirebaseService.syncStaffQualifications();
      }
      _nameCtrl.clear();
      _descCtrl.clear();
      if (mounted) Navigator.pop(context);
      _activeSection == 0 ? _loadTypes() : _loadQualifications();
      _showSnack('$label "$name" added!', Colors.green);
    } catch (e) {
      _showSnack('Error: ${_extractError(e)}', Colors.red);
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    _nameCtrl.text = item['name'] ?? '';
    _descCtrl.text = item['description'] ?? '';
    final endpoint = _activeSection == 0
        ? '/staff/types/${item['id']}'
        : '/staff/qualifications/${item['id']}';
    final label = _activeSection == 0 ? 'Staff type' : 'Qualification';

    _openForm(
      title: "${context.tr('edit')} $label",
      icon: _activeSection == 0
          ? Icons.work_rounded
          : Icons.school_rounded,
      onSave: () async {
        final name = _nameCtrl.text.trim();
        if (name.isEmpty) return;
        try {
          await _apiClient.put(endpoint, data: {
            'name': name,
            'description': _descCtrl.text.trim(),
          });
          if (_activeSection == 0) {
            FirebaseService.syncStaffTypes();
          } else {
            FirebaseService.syncStaffQualifications();
          }
          _nameCtrl.clear();
          _descCtrl.clear();
          if (mounted) Navigator.pop(context);
          _activeSection == 0 ? _loadTypes() : _loadQualifications();
          _showSnack('$label updated!', Colors.green);
        } catch (e) {
          _showSnack('Error: ${_extractError(e)}', Colors.red);
        }
      },
    );
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final label = _activeSection == 0 ? 'Staff Type' : 'Qualification';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $label',
            style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
        content: Text(
          'Delete "${item['name']}"? This cannot be undone.',
          style: AppTheme.getFontStyle(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final endpoint = _activeSection == 0
          ? '/staff/types/${item['id']}'
          : '/staff/qualifications/${item['id']}';
      try {
        await _apiClient.delete(endpoint);
        if (_activeSection == 0) {
          FirebaseService.syncStaffTypes();
        } else {
          FirebaseService.syncStaffQualifications();
        }
        _activeSection == 0 ? _loadTypes() : _loadQualifications();
        _showSnack('$label deleted!', Colors.orange);
      } catch (e) {
        _showSnack('Error: ${_extractError(e)}', Colors.red);
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _extractError(dynamic e) {
    if (e is DioException && e.response?.data is Map) {
      return e.response?.data['error'] ?? e.message ?? 'Unknown error';
    }
    return e.toString();
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppTheme.getFontStyle()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAddDialog() {
    _nameCtrl.clear();
    _descCtrl.clear();
    final label = _activeSection == 0 ? 'Staff Type' : 'Qualification';
    _openForm(
      title: "${context.tr('add')} $label",
      icon: _activeSection == 0
          ? Icons.work_rounded
          : Icons.school_rounded,
      onSave: _addItem,
    );
  }

  void _openForm({
    required String title,
    required IconData icon,
    required VoidCallback onSave,
  }) {
    if (context.isMobile || MediaQuery.of(context).size.width < 700) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _AdminFormPage(
            title: title,
            icon: icon,
            nameCtrl: _nameCtrl,
            descCtrl: _descCtrl,
            onSave: onSave,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => _buildFormDialog(
          title: title,
          icon: icon,
          onSave: onSave,
        ),
      );
    }
  }

  // ── Form Dialog ─────────────────────────────────────────────────────────────
  Widget _buildFormDialog({
    required String title,
    required IconData icon,
    required VoidCallback onSave,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withAlpha(20),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: AppTheme.getFontStyle(
                fontSize: 17,
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
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: AppTheme.getFontStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: context.tr('name_required'),
                labelStyle: AppTheme.getFontStyle(fontSize: 13),
                prefixIcon: Icon(Icons.label_rounded,
                    size: 18, color: AppTheme.primaryColor),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.primaryColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              style: AppTheme.getFontStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: context.tr('description_optional_lc'),
                labelStyle: AppTheme.getFontStyle(fontSize: 13),
                prefixIcon: Icon(Icons.notes_rounded,
                    size: 18, color: AppTheme.primaryColor),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppTheme.primaryColor, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel'), style: AppTheme.getFontStyle()),
        ),
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save_rounded, size: 16),
          label: Text(context.tr('save'),
              style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 700;
    final scale = isCompact ? (width / 375.0).clamp(0.75, 1.0) : 1.0;

    final items = _activeSection == 0 ? _staffTypes : _qualifications;
    final isLoading = _activeSection == 0 ? _loadingTypes : _loadingQuals;
    final sectionLabel =
        _activeSection == 0 ? 'Staff Types' : 'Qualifications';
    final sectionDesc = _activeSection == 0
        ? 'Manage staff roles for your madarsa'
        : 'Manage qualification options for staff';
    final sectionIcon =
        _activeSection == 0 ? Icons.work_rounded : Icons.school_rounded;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? (8.0 * scale) : 24,
        vertical: isCompact ? (10.0 * scale) : 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff Administration',
                      style: AppTheme.getFontStyle(
                        fontSize: isCompact ? (16.0 * scale) : 20,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Manage staff types & qualifications',
                      style: AppTheme.getFontStyle(
                          fontSize: isCompact ? (10.0 * scale) : 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              isCompact
                  ? IconButton(
                      onPressed: _showAddDialog,
                      icon: Icon(Icons.add_rounded, size: 20 * scale),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10 * scale),
                        ),
                        padding: EdgeInsets.all(8 * scale),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _showAddDialog,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Add $sectionLabel',
                          style:
                              AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ],
          ),
          SizedBox(height: isCompact ? (12.0 * scale) : 20),

          // ── Section Toggle ─────────────────────────────────────────────
          Container(
            padding: EdgeInsets.all(4 * scale),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12 * scale),
            ),
            child: Row(
              children: [
                _buildToggleBtn(
                  label: context.tr('staff_types'),
                  icon: Icons.work_rounded,
                  isActive: _activeSection == 0,
                  isDark: isDark,
                  scale: scale,
                  onTap: () => setState(() => _activeSection = 0),
                ),
                SizedBox(width: 4 * scale),
                _buildToggleBtn(
                  label: context.tr('qualifications'),
                  icon: Icons.school_rounded,
                  isActive: _activeSection == 1,
                  isDark: isDark,
                  scale: scale,
                  onTap: () => setState(() => _activeSection = 1),
                ),
              ],
            ),
          ),
          SizedBox(height: isCompact ? (12.0 * scale) : 20),

          // ── Section Info ───────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8 * scale),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryColor.withAlpha(isDark ? 30 : 15),
                ),
                child: Icon(sectionIcon,
                    size: 16 * scale, color: AppTheme.primaryColor),
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectionLabel,
                      style: AppTheme.getFontStyle(
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      sectionDesc,
                      style: AppTheme.getFontStyle(
                          fontSize: 11 * scale, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * scale),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 6 * scale),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(isDark ? 30 : 15),
                  borderRadius: BorderRadius.circular(20 * scale),
                ),
                child: Text(
                  '${items.length} items',
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? (10.0 * scale) : 16),

          // ── List / Grid ──────────────────────────────────────────────
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? _buildEmptyState(sectionLabel, sectionIcon)
                    : isCompact
                        ? ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: 10 * scale),
                            itemBuilder: (context, i) => _buildItemCard(
                              items[i],
                              isDark,
                              sectionIcon,
                              scale,
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 14,
                              childAspectRatio: 2.8,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, i) => _buildItemCard(
                              items[i],
                              isDark,
                              sectionIcon,
                              1.0,
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  // ── Toggle Button ──────────────────────────────────────────────────────────
  Widget _buildToggleBtn({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isDark,
    required double scale,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10 * scale),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * scale),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withAlpha(40),
                      blurRadius: 6 * scale,
                      offset: Offset(0, 2 * scale),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15 * scale,
                color: isActive
                    ? Colors.white
                    : isDark
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
              ),
              SizedBox(width: 6 * scale),
              Flexible(
                child: Text(
                  label,
                  style: AppTheme.getFontStyle(
                    fontSize: 12 * scale,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive
                        ? Colors.white
                        : isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Item Card ──────────────────────────────────────────────────────────────
  Widget _buildItemCard(
      Map<String, dynamic> item, bool isDark, IconData icon, double scale) {
    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 15 : 5),
            blurRadius: 8 * scale,
            offset: Offset(0, 2 * scale),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40 * scale,
            height: 40 * scale,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withAlpha(isDark ? 35 : 18),
            ),
            child: Icon(icon, size: 18 * scale, color: AppTheme.primaryColor),
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['name'] ?? '',
                  style: AppTheme.getFontStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                if ((item['description'] ?? '').isNotEmpty)
                  Text(
                    item['description'],
                    style: AppTheme.getFontStyle(
                      fontSize: 11 * scale,
                      color: Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_rounded, size: 16 * scale),
            color: const Color(0xFF1565C0),
            tooltip: context.tr('edit'),
            onPressed: () => _editItem(item),
          ),
          IconButton(
            icon: Icon(Icons.delete_rounded, size: 16 * scale),
            color: Colors.red,
            tooltip: context.tr('delete'),
            onPressed: () => _deleteItem(item),
          ),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(String sectionLabel, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade100,
            ),
            child: Icon(icon, size: 28, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 14),
          Text(
            'No $sectionLabel yet',
            style: AppTheme.getFontStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add_rounded),
            label: Text('Add First ${_activeSection == 0 ? 'Type' : 'Qualification'}'),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }
}

class _AdminFormPage extends StatelessWidget {
  final String title;
  final IconData icon;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final VoidCallback onSave;

  const _AdminFormPage({
    required this.title,
    required this.icon,
    required this.nameCtrl,
    required this.descCtrl,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final scale = (width / 375.0).clamp(0.75, 1.0);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF141421) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(16 * scale, 18 * scale, 16 * scale, 16 * scale),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF043927), Color(0xFF0D6B4E)],
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(12 * scale),
                    child: Container(
                      padding: EdgeInsets.all(8 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 20 * scale,
                      ),
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: AppTheme.getFontStyle(
                            fontSize: 18 * scale,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Enter details below',
                          style: AppTheme.getFontStyle(
                            fontSize: 12 * scale,
                            color: Colors.white.withAlpha(180),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20 * scale),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: AppTheme.getFontStyle(fontSize: 14 * scale),
                      decoration: InputDecoration(
                        labelText: context.tr('name_required'),
                        labelStyle: AppTheme.getFontStyle(
                          fontSize: 13 * scale,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        prefixIcon: Icon(
                          Icons.label_rounded,
                          size: 18 * scale,
                          color: AppTheme.primaryColor,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14 * scale,
                          vertical: 14 * scale,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                    SizedBox(height: 16 * scale),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      style: AppTheme.getFontStyle(fontSize: 14 * scale),
                      decoration: InputDecoration(
                        labelText: context.tr('description_optional_lc'),
                        labelStyle: AppTheme.getFontStyle(
                          fontSize: 13 * scale,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                        prefixIcon: Icon(
                          Icons.notes_rounded,
                          size: 18 * scale,
                          color: AppTheme.primaryColor,
                        ),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade50,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14 * scale,
                          vertical: 14 * scale,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withAlpha(15) : Colors.grey.shade200,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12 * scale),
                          borderSide: BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(24 * scale, 14 * scale, 24 * scale, 18 * scale),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade200,
                  ),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, size: 18 * scale),
                    label: Text(
                      context.tr('cancel'),
                      style: AppTheme.getFontStyle(fontSize: 13 * scale),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onSave,
                    icon: Icon(Icons.save_rounded, size: 18 * scale),
                    label: Text(
                      context.tr('save'),
                      style: AppTheme.getFontStyle(
                        fontSize: 14 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24 * scale,
                        vertical: 12 * scale,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * scale),
                      ),
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
}
