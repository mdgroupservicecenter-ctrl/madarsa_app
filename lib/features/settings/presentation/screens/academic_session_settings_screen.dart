import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/firebase_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/storage/database_helper.dart';
import '../../data/models/vacation_model.dart';
import '../../../../shared/widgets/movable_resizable_dialog.dart';
import '../../../students/presentation/widgets/class_progression_series_dialog.dart';

class AcademicSessionSettingsScreen extends StatefulWidget {
  const AcademicSessionSettingsScreen({super.key});

  @override
  State<AcademicSessionSettingsScreen> createState() => _AcademicSessionSettingsScreenState();
}

class _AcademicSessionSettingsScreenState extends State<AcademicSessionSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRunningPromotion = false;

  // Session Config
  late TextEditingController _yearNameController;
  late TextEditingController _hijriYearController;
  late TextEditingController _startDateController;
  late TextEditingController _endDateController;
  late TextEditingController _passingPercentageController;
  late TextEditingController _annualExpenseController;
  bool _autoPromoteEnabled = true;
  String? _autoPromotedAt;

  // Vacations List
  List<Vacation> _vacations = [];

  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _yearNameController = TextEditingController();
    _hijriYearController = TextEditingController();
    _startDateController = TextEditingController();
    _endDateController = TextEditingController();
    _passingPercentageController = TextEditingController(text: '40.0');
    _annualExpenseController = TextEditingController(text: '15000');

    _loadData();
  }

  @override
  void dispose() {
    _yearNameController.dispose();
    _hijriYearController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _passingPercentageController.dispose();
    _annualExpenseController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final config = await DatabaseHelper().getCurrentAcademicSessionConfig();
      final vacListRaw = await DatabaseHelper().getVacations();

      if (mounted) {
        setState(() {
          _yearNameController.text = config['year_name']?.toString() ?? '${DateTime.now().year}-${DateTime.now().year + 1}';
          _hijriYearController.text = config['year_name_hijri']?.toString() ?? '${DateTime.now().year - 579}-${DateTime.now().year - 578} H';
          _startDateController.text = config['start_date']?.toString() ?? '${DateTime.now().year}-06-01';
          _endDateController.text = config['end_date']?.toString() ?? '${DateTime.now().year + 1}-04-30';
          _passingPercentageController.text = ((config['passing_percentage'] as num?)?.toDouble() ?? 40.0).toString();
          _annualExpenseController.text = ((config['annual_student_expense'] as num?)?.toDouble() ?? 15000.0).toStringAsFixed(0);
          _autoPromoteEnabled = (config['auto_promote_enabled'] ?? 1) == 1;
          _autoPromotedAt = config['auto_promoted_at']?.toString();

          _vacations = vacListRaw.map((v) => Vacation.fromJson(v)).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    DateTime initial = DateTime.now();
    try {
      if (controller.text.trim().isNotEmpty) {
        initial = DateTime.parse(controller.text.trim());
      }
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        controller.text = picked.toIso8601String().split('T').first;
      });
    }
  }

  Future<void> _saveSessionConfig() async {
    setState(() => _isSaving = true);
    try {
      final oldConfig = await DatabaseHelper().getCurrentAcademicSessionConfig();
      final oldYear = oldConfig['year_name']?.toString().trim();
      final newYear = _yearNameController.text.trim();

      final configMap = {
        'year_name': newYear,
        'year_name_hijri': _hijriYearController.text.trim(),
        'start_date': _startDateController.text.trim(),
        'end_date': _endDateController.text.trim(),
        'auto_promote_enabled': _autoPromoteEnabled ? 1 : 0,
        'passing_percentage': double.tryParse(_passingPercentageController.text.trim()) ?? 40.0,
        'annual_student_expense': double.tryParse(_annualExpenseController.text.trim()) ?? 15000.0,
      };

      await DatabaseHelper().saveAcademicSessionConfig(configMap);

      // Online Cloud Sync
      try {
        await FirebaseService.syncAcademicSessionConfig(configMap);
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Academic Session settings saved and synced to cloud successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // If academic year has changed, offer to run auto-promotion now
        if (oldYear != null && oldYear.isNotEmpty && oldYear != newYear) {
          _promptPromotionOnYearChange(oldYear, newYear);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _promptPromotionOnYearChange(String oldYear, String newYear) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.upgrade_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('Advance Students to New Academic Year?'),
          ],
        ),
        content: Text(
          'You changed the Academic Session Year from "$oldYear" to "$newYear".\n\n'
          'Would you like to run Automatic Progression & Promotion now?\n\n'
          '• Students will advance to their next Class and Department based on the configured Progression Series.\n'
          '• All academic records (attendance, exam marks, books, fees, expenses) from "$oldYear" will be preserved in their Academic History.\n'
          '• All changes will be saved locally and synced to online Cloud storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, Keep Classes As Is'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Auto-Promote All Students'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _runPromotionWithYear(oldYear);
    }
  }

  Future<void> _runAutoPromotionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            const Text('Run Year-End Auto Promotion'),
          ],
        ),
        content: const Text(
          'Are you sure you want to run Annual Promotion now?\n\n'
          '• Students who passed will automatically advance to their next class & department.\n'
          '• Previous year snapshot (attendance, books, exams, fees, expenses) will be archived.\n'
          '• Students who failed will remain in their current class.\n'
          '• All records will be synced to online Cloud storage.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
            child: const Text('Confirm & Promote Now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    _runPromotionWithYear(_yearNameController.text.trim());
  }

  Future<void> _runPromotionWithYear(String academicYearToArchive) async {
    setState(() => _isRunningPromotion = true);
    try {
      final passPct = double.tryParse(_passingPercentageController.text.trim()) ?? 40.0;
      final result = await DatabaseHelper().executeAutomaticYearEndPromotion(
        passingPercentage: passPct,
        academicYear: academicYearToArchive,
        force: true, // User manually triggered
      );

      if (mounted) {
        setState(() {
          _isRunningPromotion = false;
          _autoPromotedAt = result['executed_at']?.toString();
        });

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 8),
                Text('Promotion Completed!'),
              ],
            ),
            content: Text(
              'Academic Year-End Auto Promotion finished successfully!\n\n'
              '• Total Students Processed: ${result['total_students']}\n'
              '• Promoted to Next Class & Department: ${result['promoted_count']}\n'
              '• Graduated / Farigh: ${result['farigh_count']}\n'
              '• Repeated (Failed): ${result['repeated_count']}\n\n'
              'All academic records, book marks, fees, and expenses have been archived and synced to online Cloud storage.',
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRunningPromotion = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-promotion failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openVacationDialog([Vacation? vacation]) {
    final isEdit = vacation != null;
    final titleController = TextEditingController(text: vacation?.title ?? '');
    final startController = TextEditingController(text: vacation?.startDate ?? _dateFormat.format(DateTime.now()));
    final endController = TextEditingController(text: vacation?.endDate ?? _dateFormat.format(DateTime.now().add(const Duration(days: 15))));
    final remarksController = TextEditingController(text: vacation?.remarks ?? '');
    String vacType = vacation?.vacationType ?? 'Ramzan';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int days = 1;
          try {
            final s = DateTime.parse(startController.text);
            final e = DateTime.parse(endController.text);
            days = e.difference(s).inDays + 1;
            if (days < 0) days = 0;
          } catch (_) {}

          return MovableResizableDialog(
            initialWidth: 500,
            initialHeight: 520,
            minWidth: 400,
            minHeight: 450,
            headerLeading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: Colors.white.withAlpha(30), shape: BoxShape.circle),
              child: const Icon(Icons.beach_access_rounded, color: Colors.white, size: 20),
            ),
            title: Text(
              isEdit ? 'Edit Vacation (تعطیل ترمیم کریں)' : 'Add Vacation (تعطیل کا اندراج)',
              style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            content: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Vacation Title / Naam *',
                      hintText: 'e.g. تعطیلاتِ رمضان المبارک / Ramzan Vacation',
                      prefixIcon: Icon(Icons.title_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _QuickChip(
                        label: 'تعطیلاتِ رمضان المبارک',
                        onTap: () => setModalState(() {
                          titleController.text = 'تعطیلاتِ رمضان المبارک';
                          vacType = 'Ramzan';
                        }),
                      ),
                      _QuickChip(
                        label: 'تعطیلاتِ عید الاضحی',
                        onTap: () => setModalState(() {
                          titleController.text = 'تعطیلاتِ عید الاضحی';
                          vacType = 'Eid';
                        }),
                      ),
                      _QuickChip(
                        label: 'گرمیوں کی چھٹیاں',
                        onTap: () => setModalState(() {
                          titleController.text = 'گرمیوں کی چھٹیاں (Summer Vacation)';
                          vacType = 'Summer';
                        }),
                      ),
                      _QuickChip(
                        label: 'سردیوں کی چھٹیاں',
                        onTap: () => setModalState(() {
                          titleController.text = 'سردیوں کی چھٹیاں (Winter Vacation)';
                          vacType = 'Winter';
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: vacType,
                    decoration: const InputDecoration(
                      labelText: 'Vacation Category',
                      prefixIcon: Icon(Icons.category_rounded, size: 20),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Ramzan', child: Text('Ramzan Vacation (تعطیلاتِ رمضان)')),
                      DropdownMenuItem(value: 'Eid', child: Text('Eid Vacation (تعطیلاتِ عید)')),
                      DropdownMenuItem(value: 'Summer', child: Text('Summer Vacation (گرمیوں کی چھٹیاں)')),
                      DropdownMenuItem(value: 'Winter', child: Text('Winter Vacation (سردیوں کی چھٹیاں)')),
                      DropdownMenuItem(value: 'General', child: Text('General / Other (دیگر تعطیلات)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setModalState(() => vacType = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: startController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Start Date *',
                            prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(startController.text) ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2050),
                            );
                            if (picked != null) {
                              setModalState(() {
                                startController.text = _dateFormat.format(picked);
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: endController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'End Date *',
                            prefixIcon: Icon(Icons.event_rounded, size: 18),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(endController.text) ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2050),
                            );
                            if (picked != null) {
                              setModalState(() {
                                endController.text = _dateFormat.format(picked);
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        Text(
                          'Total Duration: $days Days (دن)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Remarks (Optional)',
                      hintText: 'e.g. Madarsa reopens on 10th Shawwal',
                      prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter vacation title'), backgroundColor: Colors.red),
                      );
                      return;
                    }

                    final id = isEdit ? vacation.id : 'vac_${DateTime.now().millisecondsSinceEpoch}';
                    final data = {
                      'id': id,
                      'title': titleController.text.trim(),
                      'vacation_type': vacType,
                      'start_date': startController.text.trim(),
                      'end_date': endController.text.trim(),
                      'total_days': days,
                      'remarks': remarksController.text.trim().isNotEmpty ? remarksController.text.trim() : null,
                      'academic_year_id': _yearNameController.text.trim(),
                      'updated_at': DateTime.now().toIso8601String(),
                    };

                    if (isEdit) {
                      await DatabaseHelper().updateVacation(id, data);
                    } else {
                      data['created_at'] = DateTime.now().toIso8601String();
                      await DatabaseHelper().insertVacation(data);
                    }

                    if (context.mounted) {
                      Navigator.pop(ctx);
                      _loadData();
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(isEdit ? 'Update Vacation' : 'Save Vacation'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteVacation(Vacation vacation) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Vacation'),
        content: Text('Are you sure you want to delete "${vacation.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper().deleteVacation(vacation.id);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF12121A) : const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Academic Session, Dates & Vacations (تعلیمی سال و تعطیلات)'),
        elevation: 0,
        actions: [
          if (!_isLoading)
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveSessionConfig,
              icon: _isSaving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSessionDatesCard(isDark),
                  const SizedBox(height: 24),
                  _buildVacationsCard(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildSessionDatesCard(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_month_rounded, color: AppTheme.primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Madarsa Academic Session & Dates (تعلیمی سال اور تاریخ)',
                        style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Define session start and end dates. Passing students auto-promote when session end date arrives.',
                        style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _yearNameController,
                    decoration: const InputDecoration(
                      labelText: 'Academic Year *',
                      hintText: 'e.g. 2025-2026',
                      prefixIcon: Icon(Icons.school_rounded, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _hijriYearController,
                    decoration: const InputDecoration(
                      labelText: 'Hijri Year',
                      hintText: 'e.g. 1446-1447 H',
                      prefixIcon: Icon(Icons.star_border_rounded, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startDateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Session Start Date *',
                      prefixIcon: Icon(Icons.play_circle_outline_rounded, size: 18),
                    ),
                    onTap: () => _pickDate(_startDateController),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _endDateController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Session End Date *',
                      prefixIcon: Icon(Icons.flag_rounded, size: 18),
                    ),
                    onTap: () => _pickDate(_endDateController),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic Annual Promotion on Session End Date'),
                    subtitle: const Text('When session end date arrives, automatically advance passing students and archive previous year.'),
                    value: _autoPromoteEnabled,
                    activeThumbColor: const Color(0xFF0D6B4E),
                    onChanged: (v) => setState(() => _autoPromoteEnabled = v),
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _passingPercentageController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Passing Marks % Threshold *',
                            hintText: '40.0',
                            suffixText: '%',
                            prefixIcon: Icon(Icons.percent_rounded, size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _annualExpenseController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Annual Expense Per Student (فی طالب علم سالانہ خرچ) *',
                            hintText: '15000',
                            prefixText: '₹ ',
                            prefixIcon: Icon(Icons.payments_outlined, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(5) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schema_rounded, color: Color(0xFF0D6B4E), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Class Progression Series (کلاسوں کی سلسلہ وار اگلی کلاس)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              Text(
                                'Set which class comes after which class, and which class is the graduation final year.',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => ClassProgressionSeriesDialog.show(context),
                          icon: const Icon(Icons.tune_rounded, size: 14),
                          label: const Text('Configure Series Order'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0D6B4E),
                            side: const BorderSide(color: Color(0xFF0D6B4E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_autoPromotedAt != null)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Last Auto-Promoted: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.tryParse(_autoPromotedAt!) ?? DateTime.now())}',
                        style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  const Text('Status: Not executed yet for current session', style: TextStyle(fontSize: 12, color: Colors.grey)),

                FilledButton.icon(
                  onPressed: _isRunningPromotion ? null : _runAutoPromotionDialog,
                  icon: _isRunningPromotion
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_isRunningPromotion ? 'Processing Promotion...' : 'Run Auto-Promotion Now (ابھی سالانہ ترقی چلائیں)'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacationsCard(bool isDark) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.beach_access_rounded, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Madarsa Vacations & Holidays (تعطیلات اور چھٹیاں)',
                          style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Create and manage vacation periods (Ramzan, Eid, Summer, Winter).',
                          style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: () => _openVacationDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Vacation (تعطیل کا اندراج)'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
                ),
              ],
            ),
            const Divider(height: 32),

            if (_vacations.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.beach_access_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('No vacations created for this academic session yet.'),
                    const SizedBox(height: 6),
                    Text(
                      'Click "Add Vacation" to configure Ramzan, Eid, or Summer holidays.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _vacations.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final v = _vacations[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _getVacationColor(v.vacationType).withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.beach_access_rounded, color: _getVacationColor(v.vacationType), size: 20),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    v.title,
                                    style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _getVacationColor(v.vacationType).withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      v.vacationType,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _getVacationColor(v.vacationType)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.date_range_rounded, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${v.startDate}  →  ${v.endDate} (${v.totalDays} Days)',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                  if (v.remarks != null && v.remarks!.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    Text('• ${v.remarks}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Edit Vacation',
                          onPressed: () => _openVacationDialog(v),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                          tooltip: 'Delete Vacation',
                          onPressed: () => _deleteVacation(v),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Color _getVacationColor(String type) {
    switch (type.toLowerCase()) {
      case 'ramzan':
        return const Color(0xFF0D6B4E);
      case 'eid':
        return const Color(0xFF1565C0);
      case 'summer':
        return Colors.orange.shade800;
      case 'winter':
        return Colors.teal;
      default:
        return Colors.purple;
    }
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
