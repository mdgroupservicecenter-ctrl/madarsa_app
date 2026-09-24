import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'firebase_service.dart';

class StudentStatusSettings {
  static const String _prefKey = 'student_status_categories_v1';
  static const String _colorPrefKey = 'student_status_colors_map_v1';

  static const List<String> defaultStatuses = [
    'Active',
    'Inactive',
    'Graduated',
    'Passed Out',
    'Suspended',
    'On Leave',
    'Transferred',
  ];

  static const List<Color> availableColors = [
    Color(0xFF2E7D32), // Forest Green
    Color(0xFF43A047), // Emerald Green
    Color(0xFF00897B), // Teal
    Color(0xFF00ACC1), // Cyan
    Color(0xFF1565C0), // Royal Blue
    Color(0xFF3949AB), // Indigo
    Color(0xFF6A1B9A), // Purple
    Color(0xFF8E24AA), // Deep Violet
    Color(0xFFD81B60), // Pink / Rose
    Color(0xFFC62828), // Crimson Red
    Color(0xFFE53935), // Bright Red
    Color(0xFFD84315), // Deep Orange / Rust
    Color(0xFFFB8C00), // Orange
    Color(0xFFF57F17), // Amber / Gold
    Color(0xFF6D4C41), // Brown
    Color(0xFF546E7A), // Blue Grey
  ];

  static Map<String, Color> _cachedColors = {};
  static bool _colorsLoaded = false;

  static Color getDefaultColorForStatus(String status) {
    final st = status.trim().toLowerCase();
    if (st == 'active' || st == 'yes' || st == 'regular') {
      return const Color(0xFF2E7D32); // Green
    }
    if (st == 'inactive' || st == 'no') {
      return const Color(0xFFC62828); // Red
    }
    if (st.contains('graduat') || st.contains('pass') || st.contains('completed')) {
      return const Color(0xFF6A1B9A); // Purple
    }
    if (st.contains('suspend') || st.contains('rusticat') || st.contains('dismiss')) {
      return const Color(0xFFD84315); // Deep Orange / Red
    }
    if (st.contains('leave') || st.contains('chhut') || st.contains('absent')) {
      return const Color(0xFFF57F17); // Amber / Gold
    }
    if (st.contains('transfer') || st.contains('shift')) {
      return const Color(0xFF1565C0); // Blue
    }
    if (st.contains('farar') || st.contains('run') || st.contains('bhaga')) {
      return const Color(0xFFD84315); // Rust / Deep Orange
    }
    if (st.contains('new') || st.contains('admit')) {
      return const Color(0xFF00897B); // Teal
    }
    if (st.contains('promot')) {
      return const Color(0xFF3949AB); // Indigo
    }
    return const Color(0xFF00897B); // Default Teal
  }

  static Future<List<String>> getStatuses() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefKey);
    if (list != null && list.isNotEmpty) {
      return list;
    }
    return List<String>.from(defaultStatuses);
  }

  static Future<void> saveStatuses(List<String> statuses) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanList = statuses
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_prefKey, cleanList);
    FirebaseService.syncStudentStatusSettings(categories: cleanList);
  }

  static Future<List<String>> addStatus(String newStatus, [Color? color]) async {
    final list = await getStatuses();
    final clean = newStatus.trim();
    if (clean.isNotEmpty && !list.contains(clean)) {
      list.add(clean);
      await saveStatuses(list);
    }
    if (color != null) {
      await setStatusColor(clean, color);
    }
    return list;
  }

  static Future<List<String>> removeStatus(String statusToRemove) async {
    final list = await getStatuses();
    list.removeWhere((s) => s.trim().toLowerCase() == statusToRemove.trim().toLowerCase());
    await saveStatuses(list);

    // Also remove from color map
    final colors = await getStatusColors();
    colors.remove(statusToRemove.trim());
    await saveStatusColors(colors);

    return list;
  }

  // ── Color Management ──────────────────────────────────────────────────────
  static Future<Map<String, Color>> getStatusColors() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_colorPrefKey);
    final Map<String, Color> result = {};
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        decoded.forEach((key, val) {
          if (val is int) {
            result[key] = Color(val);
          }
        });
      } catch (_) {}
    }
    _cachedColors = result;
    _colorsLoaded = true;
    return result;
  }

  static Color getStatusColorSync(String status) {
    final clean = status.trim();
    if (_cachedColors.containsKey(clean)) {
      return _cachedColors[clean]!;
    }
    for (final entry in _cachedColors.entries) {
      if (entry.key.toLowerCase() == clean.toLowerCase()) {
        return entry.value;
      }
    }
    return getDefaultColorForStatus(clean);
  }

  static Future<Color> getStatusColor(String status) async {
    if (!_colorsLoaded) {
      await getStatusColors();
    }
    return getStatusColorSync(status);
  }

  static Future<void> setStatusColor(String status, Color color) async {
    final colors = await getStatusColors();
    colors[status.trim()] = color;
    _cachedColors = colors;
    final prefs = await SharedPreferences.getInstance();
    final mapToSave = colors.map((k, v) => MapEntry(k, v.toARGB32()));
    await prefs.setString(_colorPrefKey, jsonEncode(mapToSave));
    FirebaseService.syncStudentStatusSettings(colors: mapToSave);
  }

  static Future<void> saveStatusColors(Map<String, Color> colors) async {
    _cachedColors = Map.from(colors);
    _colorsLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final mapToSave = colors.map((k, v) => MapEntry(k, v.toARGB32()));
    await prefs.setString(_colorPrefKey, jsonEncode(mapToSave));
    FirebaseService.syncStudentStatusSettings(colors: mapToSave);
  }
}

class ManageStatusCategoriesDialog extends StatefulWidget {
  const ManageStatusCategoriesDialog({super.key});

  static Future<void> show(BuildContext context, {Color? barrierColor}) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) => const ManageStatusCategoriesDialog(),
    );
  }

  @override
  State<ManageStatusCategoriesDialog> createState() => _ManageStatusCategoriesDialogState();
}

class _ManageStatusCategoriesDialogState extends State<ManageStatusCategoriesDialog> {
  final _textController = TextEditingController();
  List<String> _statuses = [];
  Map<String, Color> _statusColors = {};
  bool _isLoading = true;
  String? _editingStatus;
  Color _selectedColor = const Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await StudentStatusSettings.getStatuses();
    final colors = await StudentStatusSettings.getStatusColors();
    if (mounted) {
      setState(() {
        _statuses = list;
        _statusColors = colors;
        _isLoading = false;
      });
    }
  }

  Color _getColorFor(String st) {
    if (_statusColors.containsKey(st)) {
      return _statusColors[st]!;
    }
    return StudentStatusSettings.getDefaultColorForStatus(st);
  }

  Future<void> _saveOrAddCategory() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_editingStatus != null) {
      final oldIndex = _statuses.indexOf(_editingStatus!);
      if (oldIndex != -1) {
        _statuses[oldIndex] = text;
        await StudentStatusSettings.saveStatuses(_statuses);

        // Update color
        _statusColors.remove(_editingStatus!);
        _statusColors[text] = _selectedColor;
        await StudentStatusSettings.saveStatusColors(_statusColors);
      }
      _editingStatus = null;
    } else {
      await StudentStatusSettings.addStatus(text, _selectedColor);
      _statusColors[text] = _selectedColor;
      await StudentStatusSettings.saveStatusColors(_statusColors);
    }

    _textController.clear();
    _selectedColor = const Color(0xFF2E7D32);
    _load();
  }

  void _startEditing(String st) {
    setState(() {
      _editingStatus = st;
      _textController.text = st;
      _selectedColor = _getColorFor(st);
    });
  }

  Future<void> _removeCategory(String st) async {
    final updated = await StudentStatusSettings.removeStatus(st);
    if (_editingStatus == st) {
      _editingStatus = null;
      _textController.clear();
    }
    setState(() {
      _statuses = updated;
      _statusColors.remove(st);
    });
  }

  void _showColorPickerForStatus(String st) {
    final currentColor = _getColorFor(st);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.palette_rounded, color: Color(0xFF6A1B9A), size: 22),
            const SizedBox(width: 8),
            Text(
              'Select Color for "$st"',
              style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a color badge for this status category:',
                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: StudentStatusSettings.availableColors.map((color) {
                  final isSelected = currentColor.toARGB32() == color.toARGB32();
                  return InkWell(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await StudentStatusSettings.setStatusColor(st, color);
                      await _load();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withAlpha(80),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A1B9A).withAlpha(35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.palette_rounded, color: Color(0xFF6A1B9A), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manage Statuses & Colors',
                        style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Customize status names and assigned badge colors',
                        style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Add / Edit Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: _editingStatus != null
                                ? 'Edit status name...'
                                : 'Add status (e.g. Farar, Suspended, Graduated)...',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onSubmitted: (_) => _saveOrAddCategory(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saveOrAddCategory,
                        icon: Icon(_editingStatus != null ? Icons.save_rounded : Icons.add_rounded, size: 16),
                        label: Text(_editingStatus != null ? 'Save' : 'Add'),
                        style: FilledButton.styleFrom(backgroundColor: _selectedColor),
                      ),
                      if (_editingStatus != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          onPressed: () {
                            setState(() {
                              _editingStatus = null;
                              _textController.clear();
                              _selectedColor = const Color(0xFF2E7D32);
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Color Palette Selector Row
                  Row(
                    children: [
                      Text(
                        'Badge Color:',
                        style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: StudentStatusSettings.availableColors.map((col) {
                              final isSel = _selectedColor.toARGB32() == col.toARGB32();
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () => setState(() => _selectedColor = col),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: col,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSel ? Colors.white : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: isSel
                                          ? [
                                              BoxShadow(
                                                color: col.withAlpha(120),
                                                blurRadius: 4,
                                                offset: const Offset(0, 1),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: isSel
                                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status List
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _statuses.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final st = _statuses[index];
                    final isDefault = StudentStatusSettings.defaultStatuses.contains(st);
                    final isBeingEdited = _editingStatus == st;
                    final color = _getColorFor(st);

                    return ListTile(
                      dense: true,
                      tileColor: isBeingEdited ? color.withAlpha(30) : null,
                      leading: Tooltip(
                        message: 'Click to change color',
                        child: InkWell(
                          onTap: () => _showColorPickerForStatus(st),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withAlpha(isDark ? 40 : 25),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color.withAlpha(90), width: 1.2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.palette_outlined, size: 12, color: color),
                              ],
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        st,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      subtitle: isDefault ? const Text('Default Category', style: TextStyle(fontSize: 10)) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Change Color',
                            icon: Icon(Icons.color_lens_rounded, color: color, size: 20),
                            onPressed: () => _showColorPickerForStatus(st),
                          ),
                          IconButton(
                            tooltip: 'Edit Status Name',
                            icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 18),
                            onPressed: () => _startEditing(st),
                          ),
                          if (!isDefault)
                            IconButton(
                              tooltip: 'Delete Category',
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                              onPressed: () => _removeCategory(st),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6A1B9A)),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

