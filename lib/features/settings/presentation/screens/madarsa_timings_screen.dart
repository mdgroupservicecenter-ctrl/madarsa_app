import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/attendance_timing_helper.dart';
import '../../../../core/services/cctv_schedule_resolver.dart';
import '../../../classes/data/repositories/academic_repository.dart';
import '../../../../shared/widgets/dribbble_time_picker.dart';

class MadarsaTimingsScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onShiftsChanged;
  const MadarsaTimingsScreen({super.key, this.isEmbedded = false, this.onShiftsChanged});

  @override
  State<MadarsaTimingsScreen> createState() => _MadarsaTimingsScreenState();
}

class _MadarsaTimingsScreenState extends State<MadarsaTimingsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ApiClient _apiClient = ApiClient();
  late final AcademicRepository _academicRepository;

  bool _isLoading = true;
  bool _isSavingGeneral = false;
  bool _isSavingPeriods = false;

  // General Settings
  final TextEditingController _graceMinutesController = TextEditingController(text: '15');
  String _hijriAdjustment = '0';

  // Shifts
  List<Map<String, dynamic>> _shifts = [];

  // Classes & Books
  List<Map<String, dynamic>> _classes = [];
  String? _selectedClassId;
  List<Map<String, dynamic>> _selectedClassBooks = [];

  // Period inputs per book index
  final Map<String, TextEditingController> _periodControllers = {};
  final Map<String, TimeOfDay> _periodStartTimes = {};
  final Map<String, TimeOfDay> _periodEndTimes = {};
  final Map<String, String?> _periodRecordIds = {};

  @override
  void initState() {
    super.initState();
    _academicRepository = AcademicRepository(_apiClient);
    _loadAllData();
  }

  @override
  void dispose() {
    _graceMinutesController.dispose();
    for (var controller in _periodControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Load General Settings
      final settings = await _apiClient.get('/settings/general');
      final data = settings.data as Map<String, dynamic>;

      _hijriAdjustment = data['hijri_adjustment']?.toString() ?? '0';
      _graceMinutesController.text = data['late_grace_minutes']?.toString() ?? '15';

      // 2. Load Shifts
      final shiftsResponse = await _apiClient.get('/settings/shifts');
      _shifts = List<Map<String, dynamic>>.from(shiftsResponse.data as List);

      // 3. Load Academic Hierarchy
      final hierarchy = await _academicRepository.getAcademicHierarchy();
      _classes = List<Map<String, dynamic>>.from(hierarchy);

      if (_classes.isNotEmpty) {
        _selectedClassId = _classes.first['id']?.toString();
        await _onClassChanged(_selectedClassId);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _showSnackBar('Failed to load timings settings: $e', isError: true);
      setState(() => _isLoading = false);
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime12Hour(dynamic time) {
    if (time == null) return '--:--:--';
    int hour = 8;
    int minute = 0;
    int second = 0;
    if (time is TimeOfDay) {
      hour = time.hour;
      minute = time.minute;
    } else if (time is String) {
      final parts = time.split(':');
      hour = int.tryParse(parts[0]) ?? 8;
      minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      second = parts.length > 2 ? (int.tryParse(parts[2].split(' ')[0]) ?? 0) : 0;
    }
    final dt = DateTime(2026, 1, 1, hour, minute, second);
    return DateFormat('hh:mm:ss a').format(dt);
  }

  Future<void> _onClassChanged(String? classId) async {
    if (classId == null) return;
    setState(() {
      _selectedClassId = classId;
      _selectedClassBooks = [];
      _periodControllers.clear();
      _periodStartTimes.clear();
      _periodEndTimes.clear();
      _periodRecordIds.clear();
    });

    final targetClass = _classes.where((c) => c['id']?.toString() == classId).firstOrNull;
    final booksList = <Map<String, dynamic>>[];
    final seenBookIds = <String>{};
    final courses = targetClass?['courses'] as List? ?? [];
    for (final course in courses) {
      final books = course['books'] as List? ?? [];
      for (final book in books) {
        final bId = book['book_id']?.toString() ?? '';
        if (!seenBookIds.contains(bId)) {
          seenBookIds.add(bId);
          booksList.add(Map<String, dynamic>.from(book));
        }
      }
    }

    setState(() {
      _selectedClassBooks = booksList;
    });

    try {
      final response = await _apiClient.get('/academic/class-periods', queryParams: {'class_id': classId});
      final periods = response.data as List;

      for (final book in _selectedClassBooks) {
        final bId = book['book_id']?.toString() ?? '';
        _periodControllers[bId] = TextEditingController();
        _periodStartTimes[bId] = const TimeOfDay(hour: 8, minute: 0);
        _periodEndTimes[bId] = const TimeOfDay(hour: 9, minute: 0);

        final match = periods.where(
          (p) => p['book_id']?.toString() == bId,
        ).firstOrNull;

        if (match != null) {
          _periodRecordIds[bId] = match['id']?.toString();
          _periodControllers[bId]!.text = match['period_number']?.toString() ?? '';
          _periodStartTimes[bId] = _parseTimeOfDay(match['start_time'] ?? '08:00');
          _periodEndTimes[bId] = _parseTimeOfDay(match['end_time'] ?? '09:00');
          // Use teacher_name from period response if available
          if (match['teacher_name'] != null && match['teacher_name'].toString().isNotEmpty) {
            book['teacher_name'] = match['teacher_name'];
          }
        }
      }

      // Sort selected class books by period number
      _selectedClassBooks.sort((a, b) {
        final aId = a['book_id']?.toString() ?? '';
        final bId = b['book_id']?.toString() ?? '';

        final aPeriodText = _periodControllers[aId]?.text.trim() ?? '';
        final bPeriodText = _periodControllers[bId]?.text.trim() ?? '';

        final aPeriod = int.tryParse(aPeriodText) ?? 999;
        final bPeriod = int.tryParse(bPeriodText) ?? 999;

        return aPeriod.compareTo(bPeriod);
      });
    } catch (e) {
      _showSnackBar('Failed to load period schedules: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickPeriodTime(String bookId, bool isStart) async {
    final initial = isStart ? _periodStartTimes[bookId]! : _periodEndTimes[bookId]!;
    final picked = await DribbbleTimePickerDialog.show(
      context: context,
      initialTime: initial,
      title: isStart ? 'Period Start Time' : 'Period End Time',
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _periodStartTimes[bookId] = picked;
        } else {
          _periodEndTimes[bookId] = picked;
        }
      });
    }
  }

  // ── Shifts CRUD ────────────────────────────────────────────────────
  Future<void> _addShift() async {
    final result = await _showShiftDialog();
    if (result != null) {
      try {
        await _apiClient.post('/settings/shifts', data: result);
        _showSnackBar('Shift added successfully! 🎉');
        _loadAllData();
        await AttendanceTimingHelper.loadTimings();
        await CctvScheduleResolver().syncFromMadarsaTimings();
        widget.onShiftsChanged?.call();
      } catch (e) {
        _showSnackBar('Failed to add shift: $e', isError: true);
      }
    }
  }

  Future<void> _editShift(Map<String, dynamic> shift) async {
    final result = await _showShiftDialog(existing: shift);
    if (result != null) {
      try {
        await _apiClient.put('/settings/shifts/${shift['id']}', data: result);
        _showSnackBar('Shift updated successfully! 🎉');
        _loadAllData();
        await AttendanceTimingHelper.loadTimings();
        await CctvScheduleResolver().syncFromMadarsaTimings();
        widget.onShiftsChanged?.call();
      } catch (e) {
        _showSnackBar('Failed to update shift: $e', isError: true);
      }
    }
  }

  Future<void> _deleteShift(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('delete_shift')),
        content: Text(context.tr('confirm_delete_shift')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _apiClient.delete('/settings/shifts/$id');
        _showSnackBar('Shift deleted! 🗑️');
        _loadAllData();
        await AttendanceTimingHelper.loadTimings();
        await CctvScheduleResolver().syncFromMadarsaTimings();
        widget.onShiftsChanged?.call();
      } catch (e) {
        _showSnackBar('Failed to delete shift: $e', isError: true);
      }
    }
  }

  Future<Map<String, dynamic>?> _showShiftDialog({Map<String, dynamic>? existing}) async {
    final nameController = TextEditingController(text: existing?['shift_name'] ?? '');
    TimeOfDay startTime = _parseTimeOfDay(existing?['start_time'] ?? '08:00');
    TimeOfDay endTime = _parseTimeOfDay(existing?['end_time'] ?? '13:00');

    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? 'Add New Shift' : 'Edit Shift'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Shift Name',
                      hintText: 'e.g. Morning, Evening',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await DribbbleTimePickerDialog.show(
                              context: ctx,
                              initialTime: startTime,
                              title: 'Shift Start Time',
                            );
                            if (picked != null) {
                              setDialogState(() => startTime = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Start Time',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text(_formatTime12Hour(startTime), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await DribbbleTimePickerDialog.show(
                              context: ctx,
                              initialTime: endTime,
                              title: 'Shift End Time',
                            );
                            if (picked != null) {
                              setDialogState(() => endTime = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: context.tr('end_time'),
                              border: const OutlineInputBorder(),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text(_formatTime12Hour(endTime), style: const TextStyle(fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(ctx, {
                      'shift_name': nameController.text.trim(),
                      'start_time': _formatTimeOfDay(startTime),
                      'end_time': _formatTimeOfDay(endTime),
                    });
                  },
                  child: Text(context.tr('save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Save General Settings ──────────────────────────────────────────
  Future<void> _saveGeneralSettings() async {
    setState(() => _isSavingGeneral = true);
    try {
      await _apiClient.put('/settings/general', data: {
        'hijri_adjustment': _hijriAdjustment,
        'late_grace_minutes': _graceMinutesController.text.trim(),
      });
      _showSnackBar('General settings saved successfully! 🎉');
      AttendanceTimingHelper.loadTimings();
    } catch (e) {
      _showSnackBar('Failed to save settings: $e', isError: true);
    } finally {
      setState(() => _isSavingGeneral = false);
    }
  }

  // ── Save Period ────────────────────────────────────────────────────
  Future<void> _savePeriods() async {
    if (_selectedClassId == null) return;
    setState(() => _isSavingPeriods = true);
    try {
      for (final book in _selectedClassBooks) {
        final bId = book['book_id']?.toString() ?? '';
        final periodNum = _periodControllers[bId]?.text.trim() ?? '';
        if (periodNum.isEmpty) continue;

        await _apiClient.post('/academic/class-periods', data: {
          'class_id': _selectedClassId,
          'book_id': bId,
          'period_number': int.tryParse(periodNum) ?? 1,
          'start_time': _formatTimeOfDay(_periodStartTimes[bId] ?? const TimeOfDay(hour: 8, minute: 0)),
          'end_time': _formatTimeOfDay(_periodEndTimes[bId] ?? const TimeOfDay(hour: 9, minute: 0)),
        });
      }
      _showSnackBar('Periods saved successfully! 🎉');
      await _onClassChanged(_selectedClassId);
      CctvScheduleResolver().syncFromMadarsaTimings();
    } catch (e) {
      _showSnackBar('Failed to save periods: $e', isError: true);
    } finally {
      setState(() => _isSavingPeriods = false);
    }
  }

  Future<void> _deletePeriod(String bookId) async {
    final recordId = _periodRecordIds[bookId];
    if (recordId == null) return;
    try {
      await _apiClient.delete('/academic/class-periods/$recordId');
      setState(() {
        _periodRecordIds.remove(bookId);
        _periodControllers[bookId]?.clear();
      });
      _showSnackBar('Period removed! 🗑️');
      await _onClassChanged(_selectedClassId);
      CctvScheduleResolver().syncFromMadarsaTimings();
    } catch (e) {
      _showSnackBar('Failed to delete period: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD UI
  // ═══════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── SHIFTS SECTION ──────────────────────────────────
                  _buildSectionHeader('Madarsa Shifts', Icons.schedule_rounded),
                  const SizedBox(height: 8),
                  Text(
                    'Add multiple time shifts (Morning, Evening, etc.)',
                    style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ..._shifts.map((shift) => _buildShiftCard(shift, isDark)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addShift,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('add_new_shift')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.primaryColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── GENERAL SETTINGS ────────────────────────────────
                  _buildSectionHeader('General Settings', Icons.settings_rounded),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildSettingRow(
                            'Late Grace Minutes',
                            'Students arriving within these minutes after shift start are marked Present',
                            child: SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _graceMinutesController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  suffixText: 'min',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSavingGeneral ? null : _saveGeneralSettings,
                              icon: _isSavingGeneral
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_rounded),
                              label: Text(_isSavingGeneral ? 'Saving...' : 'Save Settings'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── CLASS PERIODS SECTION ───────────────────────────
                  _buildSectionHeader('Class-wise Periods', Icons.menu_book_rounded),
                  const SizedBox(height: 12),

                  // Class Dropdown
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedClassId,
                            decoration: const InputDecoration(
                              labelText: 'Select Class',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.class_rounded),
                            ),
                            items: _classes.map((cls) {
                              return DropdownMenuItem(
                                value: cls['id']?.toString(),
                                child: Text(cls['name']?.toString() ?? ''),
                              );
                            }).toList(),
                            onChanged: (val) => _onClassChanged(val),
                          ),
                          const SizedBox(height: 16),
                          if (_selectedClassBooks.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No books assigned to this class.',
                                  style: AppTheme.getFontStyle(fontSize: 14, color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ..._selectedClassBooks.asMap().entries.map((entry) {
                              return _buildBookPeriodCard(entry.value, isDark);
                            }),
                          if (_selectedClassBooks.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isSavingPeriods ? null : _savePeriods,
                                icon: _isSavingPeriods
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.save_rounded),
                                label: Text(_isSavingPeriods ? 'Saving...' : 'Save Periods'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Madarsa Timings & Periods',
          style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: content,
    );
  }

  // ── Section Header ──────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTheme.getFontStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ── Shift Card ──────────────────────────────────────────────────────
  Widget _buildShiftCard(Map<String, dynamic> shift, bool isDark) {
    final startTime = shift['start_time'] ?? '08:00';
    final endTime = shift['end_time'] ?? '13:00';
    final shiftName = shift['shift_name'] ?? 'Shift';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.schedule_rounded, color: AppTheme.primaryColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shiftName,
                    style: AppTheme.getFontStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.withAlpha(60)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.login_rounded, size: 14, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(_formatTime12Hour(startTime), style: AppTheme.getFontStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.withAlpha(60)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.logout_rounded, size: 14, color: Colors.red),
                            const SizedBox(width: 4),
                            Text(_formatTime12Hour(endTime), style: AppTheme.getFontStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('edit_shift'),
              icon: Icon(Icons.edit_rounded, color: Colors.blue.shade600, size: 20),
              onPressed: () => _editShift(shift),
            ),
            IconButton(
              tooltip: context.tr('delete_shift'),
              icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
              onPressed: () => _deleteShift(shift['id']),
            ),
          ],
        ),
      ),
    );
  }

  // ── Setting Row ─────────────────────────────────────────────────────
  Widget _buildSettingRow(String title, String subtitle, {required Widget child}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        child,
      ],
    );
  }

  // ── Book Period Card — with teacher name ────────────────────────────
  Widget _buildBookPeriodCard(Map<String, dynamic> book, bool isDark) {
    final bookId = book['book_id']?.toString() ?? '';
    final bookName = book['name']?.toString() ?? 'Book';
    final bookAuthor = book['author']?.toString() ?? '';
    final teacherName = book['teacher_name']?.toString() ?? '';
    final hasPeriod = _periodRecordIds[bookId] != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasPeriod ? Colors.green.withAlpha(60) : Colors.grey.withAlpha(30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book info row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.book_rounded, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bookName,
                        style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      if (bookAuthor.isNotEmpty)
                        Text(
                          bookAuthor,
                          style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                if (teacherName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withAlpha(50)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_rounded, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          teacherName,
                          style: AppTheme.getFontStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                if (hasPeriod)
                  IconButton(
                    tooltip: 'Remove Period',
                    icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 20),
                    onPressed: () => _deletePeriod(bookId),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Period settings row
            Row(
              children: [
                // Period Number
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _periodControllers[bookId],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Period #',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Start Time
                Expanded(
                  child: InkWell(
                    onTap: () => _pickPeriodTime(bookId, true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Start',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime12Hour(_periodStartTimes[bookId] ?? const TimeOfDay(hour: 8, minute: 0)),
                            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // End Time
                Expanded(
                  child: InkWell(
                    onTap: () => _pickPeriodTime(bookId, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: context.tr('end'),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.stop_rounded, size: 16, color: Colors.red),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime12Hour(_periodEndTimes[bookId] ?? const TimeOfDay(hour: 9, minute: 0)),
                            style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
