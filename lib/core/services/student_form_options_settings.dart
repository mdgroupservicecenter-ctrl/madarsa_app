import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'firebase_service.dart';

class StudentFormOptionsSettings {
  static const String _genderKey = 'student_gender_options_v1';
  static const String _admissionTypeKey = 'student_admission_type_options_v1';
  static const String _conditionTypeKey = 'student_condition_type_options_v1';

  static const List<String> defaultGenders = ['Male', 'Female', 'Other'];
  static const List<String> defaultAdmissionTypes = [
    'New',
    'Old',
    'Promoted',
    'Regular',
    'Private',
    'Hosteller',
    'Day Scholar',
    'Re-admission',
  ];
  static const List<String> defaultConditions = [
    'Regular',
    'Scholarship',
    'Partial',
    'Concession',
    'Orphan Free',
    'Staff Child',
  ];

  // Genders
  static Future<List<String>> getGenders() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_genderKey);
    if (list != null && list.isNotEmpty) return list;
    return List<String>.from(defaultGenders);
  }

  static Future<void> saveGenders(List<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanList = items
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_genderKey, cleanList);
    FirebaseService.syncGenderOptions(options: cleanList);
  }

  // Admission Types
  static Future<List<String>> getAdmissionTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_admissionTypeKey);
    if (list != null && list.isNotEmpty) return list;
    return List<String>.from(defaultAdmissionTypes);
  }

  static Future<void> saveAdmissionTypes(List<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanList = items
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_admissionTypeKey, cleanList);
    FirebaseService.syncAdmissionTypes(options: cleanList);
  }

  // Fee Conditions
  static Future<List<String>> getConditions() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_conditionTypeKey);
    if (list != null && list.isNotEmpty) return list;
    return List<String>.from(defaultConditions);
  }

  static Future<void> saveConditions(List<String> items) async {
    final prefs = await SharedPreferences.getInstance();
    final cleanList = items
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    await prefs.setStringList(_conditionTypeKey, cleanList);
    FirebaseService.syncFeeConditions(options: cleanList);
  }
}

class ManageFormOptionsDialog extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color themeColor;
  final Future<List<String>> Function() getOptions;
  final Future<void> Function(List<String>) saveOptions;

  const ManageFormOptionsDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.themeColor,
    required this.getOptions,
    required this.saveOptions,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color themeColor,
    required Future<List<String>> Function() getOptions,
    required Future<void> Function(List<String>) saveOptions,
    Color? barrierColor,
  }) async {
    await showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) => ManageFormOptionsDialog(
        title: title,
        icon: icon,
        themeColor: themeColor,
        getOptions: getOptions,
        saveOptions: saveOptions,
      ),
    );
  }

  @override
  State<ManageFormOptionsDialog> createState() => _ManageFormOptionsDialogState();
}

class _ManageFormOptionsDialogState extends State<ManageFormOptionsDialog> {
  final _textController = TextEditingController();
  List<String> _items = [];
  bool _isLoading = true;
  String? _editingItem;

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
    final list = await widget.getOptions();
    if (mounted) {
      setState(() {
        _items = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveOrAddOption() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_editingItem != null) {
      final index = _items.indexOf(_editingItem!);
      if (index != -1) {
        _items[index] = text;
      }
      _editingItem = null;
    } else {
      if (!_items.contains(text)) {
        _items.add(text);
      }
    }
    _textController.clear();
    await widget.saveOptions(_items);
    await _load();
  }

  Future<void> _removeOption(String item) async {
    _items.remove(item);
    await widget.saveOptions(_items);
    await _load();
  }

  void _startEditing(String item) {
    setState(() {
      _editingItem = item;
      _textController.text = item;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingItem = null;
      _textController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, color: widget.themeColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Input Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: _editingItem != null ? 'Edit option name...' : 'Add new option...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) => _saveOrAddOption(),
                  ),
                ),
                const SizedBox(width: 8),
                if (_editingItem != null) ...[
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.grey),
                    onPressed: _cancelEditing,
                    tooltip: 'Cancel edit',
                  ),
                ],
                FilledButton(
                  onPressed: _saveOrAddOption,
                  style: FilledButton.styleFrom(backgroundColor: widget.themeColor),
                  child: Text(_editingItem != null ? 'Update' : 'Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return ListTile(
                      dense: true,
                      title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 18),
                            onPressed: () => _startEditing(item),
                            tooltip: 'Edit / Rename',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                            onPressed: () => _removeOption(item),
                            tooltip: 'Delete',
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
                  style: FilledButton.styleFrom(backgroundColor: widget.themeColor),
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
