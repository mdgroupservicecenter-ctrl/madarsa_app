import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/database_helper.dart';
import '../../../classes/data/repositories/classes_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../bloc/attendance_bloc.dart';
import '../../data/models/attendance_models.dart';
import '../../data/repositories/attendance_repository.dart';
import '../../../../core/services/attendance_timing_helper.dart';
import '../widgets/biometric_enrollment_dialog.dart';
import '../widgets/biometric_attendance_scanner_dialog.dart';
import 'cctv_attendance_kiosk_screen.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import '../../../settings/presentation/screens/madarsa_timings_screen.dart';
import '../../../../shared/widgets/dribbble_date_picker.dart';
import '../../../../shared/widgets/dribbble_time_picker.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final Set<String> _selectedStudentIds = {};
  bool _isAutoSaving = false;

  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }

  ImageProvider? _getStudentPhotoProvider(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final clean = path.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return NetworkImage(clean);
    }
    try {
      final file = File(clean);
      if (file.existsSync()) {
        return FileImage(file);
      }
    } catch (_) {}
    if (clean.startsWith('/') || clean.startsWith('\\')) {
      final fullUrl = '${ApiConstants.baseUrl.replaceAll("/api", "")}$clean';
      return NetworkImage(fullUrl);
    }
    return null;
  }

  // Student Attendance
  String? _selectedClassName;
  DateTime _studentDate = DateTime.now();
  List<String> _classesList = [];
  bool _loadingClasses = true;
  String _timeRecordingMode = 'both'; // 'both', 'in_only', 'out_only'

  // Madarsa Shift Support
  String? _selectedShiftId;
  String? _selectedShiftName;
  bool _manualShiftOverride = false;

  // Period Attendance
  String? _periodClassName;
  DateTime _periodDate = DateTime.now();
  int _selectedPeriodNumber = 1;
  List<Map<String, dynamic>> _classPeriodsList = [];
  bool _loadingPeriods = false;
  List<StudentAttendance> _periodStudents = [];
  bool _loadingPeriodStudents = false;
  Map<String, PeriodAttendanceRecord> _periodRecords = {};
  final Map<String, String> _classNameToId = {};

  // Staff Attendance
  DateTime _staffDate = DateTime.now();
  TimeOfDay _staffTime = TimeOfDay.now();

  // Biometrics
  bool _isFaceScanning = false;
  bool _isFingerScanning = false;

  // Scan Mode
  bool _scanModeEnabled = false;
  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocusNode = FocusNode();
  final List<String> _scanLog = [];

  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0 || _tabController.index == 1) {
        _initTimingsAndShifts();
      }
    });
    _loadClasses();
    _initTimingsAndShifts();
  }

  Future<void> _initTimingsAndShifts() async {
    await AttendanceTimingHelper.loadTimings();
    if (mounted) {
      if (AttendanceTimingHelper.shifts.isNotEmpty) {
        setState(() {
          final exists = AttendanceTimingHelper.shifts.any((s) => s['id']?.toString() == _selectedShiftId);
          if (!exists) {
            _selectedShiftId = AttendanceTimingHelper.shifts.first['id']?.toString();
            _selectedShiftName = AttendanceTimingHelper.shifts.first['name']?.toString() ??
                AttendanceTimingHelper.shifts.first['shift_name']?.toString();
          } else {
            final cur = AttendanceTimingHelper.shifts.firstWhere((s) => s['id']?.toString() == _selectedShiftId);
            _selectedShiftName = cur['name']?.toString() ?? cur['shift_name']?.toString();
          }
        });
        _loadStudentData();
      } else {
        setState(() {
          _selectedShiftId = null;
          _selectedShiftName = null;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      _loadStaffData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    try {
      final Set<String> seen = <String>{};
      final List<String> distinctClasses = <String>[];

      void addIfValid(dynamic name, [dynamic id]) {
        if (name == null) return;
        final str = name.toString().trim();
        if (str.isNotEmpty) {
          if (id != null) _classNameToId[str] = id.toString().trim();
          if (!seen.contains(str.toLowerCase())) {
            seen.add(str.toLowerCase());
            distinctClasses.add(str);
          }
        }
      }

      // 1. Fetch assigned classes from ClassesRepository (/classes)
      // Only include classes that are assigned to a department in Classes & Division
      try {
        final repo = ClassesRepository(ApiClient());
        final data = await repo.getAllClasses();
        for (final item in data) {
          if (item is Map) {
            final deptId = item['department_id']?.toString().trim();
            final isActive = item['is_active'] == 1 || item['is_active'] == true || item['is_active'] == null;
            final name = item['name']?.toString().trim();
            final id = item['id']?.toString().trim();
            if (isActive && deptId != null && deptId.isNotEmpty && deptId != 'null') {
              addIfValid(name, id);
            }
          }
        }
      } catch (e) {
        debugPrint('ClassesRepository load in attendance failed: $e');
      }

      // 2. Supplement / fallback from local SQLite (classes assigned to a department)
      if (distinctClasses.isEmpty) {
        try {
          final db = await DatabaseHelper().database;
          final rows = await db.rawQuery('''
            SELECT DISTINCT c.id, c.name 
            FROM classes c
            WHERE (c.is_active = 1 OR c.is_active IS NULL) 
              AND c.department_id IS NOT NULL 
              AND LENGTH(TRIM(c.department_id)) > 0 
              AND c.department_id != 'null'
              AND c.name IS NOT NULL 
              AND LENGTH(TRIM(c.name)) > 0
            ORDER BY c.created_at ASC, c.name ASC
          ''');
          for (final r in rows) {
            addIfValid(r['name'], r['id']);
          }
        } catch (e) {
          debugPrint('Local assigned classes load in attendance failed: $e');
        }
      }

      // 3. Fallback: if no classes are assigned to any department yet, load any active classes
      if (distinctClasses.isEmpty) {
        try {
          final db = await DatabaseHelper().database;
          final rows = await db.rawQuery('''
            SELECT DISTINCT id, name FROM classes 
            WHERE (is_active = 1 OR is_active IS NULL) 
              AND name IS NOT NULL 
              AND LENGTH(TRIM(name)) > 0
            ORDER BY name ASC
          ''');
          for (final r in rows) {
            addIfValid(r['name'], r['id']);
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _classesList = distinctClasses;
        if (_classesList.isNotEmpty) {
          if (_selectedClassName == null || !_classesList.contains(_selectedClassName)) {
            _selectedClassName = _classesList.first;
          }
          if (_periodClassName == null || !_classesList.contains(_periodClassName)) {
            _periodClassName = _classesList.first;
          }
        } else {
          _selectedClassName = null;
          _periodClassName = null;
        }
        _loadingClasses = false;
      });
      if (_selectedClassName != null) {
        _loadStudentData();
      }
      if (_periodClassName != null) {
        _loadPeriodData();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClasses = false);
    }
  }

  void _loadStudentData() {
    if (_selectedClassName != null) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
      context.read<AttendanceBloc>().add(
        LoadStudentAttendance(
          className: _selectedClassName!,
          date: dateStr,
          shiftId: _selectedShiftId,
        ),
      );
    }
  }

  void _loadStaffData() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_staffDate);
    context.read<AttendanceBloc>().add(LoadStaffAttendance(date: dateStr));
  }

  Future<void> _pickStudentDate() async {
    final picked = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: _studentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      title: 'Attendance Date',
    );
    if (picked != null && picked != _studentDate) {
      setState(() => _studentDate = picked);
      _loadStudentData();
    }
  }

  Future<void> _pickStaffDate(bool isAdmin) async {
    if (!isAdmin) return;
    final picked = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: _staffDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      title: 'Staff Attendance Date',
    );
    if (picked != null && picked != _staffDate) {
      setState(() => _staffDate = picked);
      _loadStaffData();
    }
  }

  Future<void> _pickStaffTime(bool isAdmin) async {
    if (!isAdmin) return;
    final picked = await DribbbleTimePickerDialog.show(
      context: context,
      initialTime: _staffTime,
      title: 'Staff Attendance Time',
    );
    if (picked != null) {
      setState(() => _staffTime = picked);
    }
  }

  void _openEnrollmentDialog(StudentAttendance student, String type) async {
    final res = await BiometricEnrollmentDialog.show(
      context,
      student: student,
      repository: AttendanceRepository(ApiClient()),
      initialType: type,
    );
    if (res == true && mounted) {
      final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
      if (_selectedClassName != null) {
        context.read<AttendanceBloc>().add(
          LoadStudentAttendance(
            className: _selectedClassName!,
            date: dateStr,
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$type biometric enrolled for ${student.fullName}! ✅'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  bool _canMarkAttendanceForShift({bool showPrompt = true}) {
    if (_manualShiftOverride) return true;
    final check = AttendanceTimingHelper.checkShiftWindow(
      DateTime.now(),
      targetShiftId: _selectedShiftId,
    );
    if (check.isWithinWindow) return true;

    if (showPrompt && mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.access_time_filled_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Outside Shift Hours!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Shift: ${check.shiftName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('• Shift Timing: ${check.shiftStartTime} - ${check.shiftEndTime}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('• Current Time: ${check.currentTime}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Attendance is locked outside shift hours to ensure timetable accuracy.\n\nTo record attendance at an alternate time due to emergency or network delays, click "Enable Manual Override".',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Enable Manual Override 🔓'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _manualShiftOverride = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Manual Override Activated! You can now mark attendance anytime. 🔓'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    return false;
  }

  void _showStudentBiometricRegistrationPicker(List<StudentAttendance> students) {
    if (students.isEmpty) return;
    if (_selectedStudentIds.length == 1) {
      final s = students.firstWhere((e) => e.id == _selectedStudentIds.first);
      _openEnrollmentDialog(s, 'Face');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtered = students.where((s) {
              final q = searchQuery.toLowerCase();
              return s.fullName.toLowerCase().contains(q) ||
                  (s.grNo ?? s.registrationNumber).toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.fingerprint_rounded, color: Colors.indigo, size: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Register Biometrics (Face / Fingerprint)',
                              style: AppTheme.getFontStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search student by name or GR number...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) {
                          setModalState(() => searchQuery = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          controller: scrollController,
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final s = filtered[i];
                            final hasFace = s.isEnrolledFor('Face');
                            final hasFinger = s.isEnrolledFor('Fingerprint');

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: AppTheme.primaryColor.withAlpha(25),
                                child: Text(
                                  s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                                ),
                              ),
                              title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Row(
                                children: [
                                  Text('GR: ${s.grNo ?? s.registrationNumber}', style: const TextStyle(fontSize: 10.5)),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasFace ? '📷 Face: ✓' : '📷 Face: ✗',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: hasFace ? Colors.teal : Colors.grey,
                                      fontWeight: hasFace ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasFinger ? '👆 Finger: ✓' : '👆 Finger: ✗',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: hasFinger ? Colors.blue : Colors.grey,
                                      fontWeight: hasFinger ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton.icon(
                                    icon: Icon(Icons.face_rounded, size: 13, color: hasFace ? Colors.teal : Colors.grey),
                                    label: Text(hasFace ? 'Edit Face' : '+ Face', style: const TextStyle(fontSize: 10.5)),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _openEnrollmentDialog(s, 'Face');
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    icon: Icon(Icons.fingerprint_rounded, size: 13, color: hasFinger ? Colors.blue : Colors.grey),
                                    label: Text(hasFinger ? 'Edit Finger' : '+ Finger', style: const TextStyle(fontSize: 10.5)),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _openEnrollmentDialog(s, 'Fingerprint');
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openBiometricScanner(List<StudentAttendance> students) {
    if (!_ensureFeatureAccess('attendance_mark', 'Daily Attendance Marking')) return;
    if (!_canMarkAttendanceForShift()) return;
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No students found in this class.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final targetStudent = _selectedStudentIds.isNotEmpty
        ? students.firstWhere(
            (s) => _selectedStudentIds.contains(s.id),
            orElse: () => students.first,
          )
        : students.first;

    BiometricAttendanceScannerDialog.show(
      context,
      students: students,
      targetStudent: targetStudent,
      repository: AttendanceRepository(ApiClient()),
      initialBiometricType: 'Face',
      date: DateFormat('yyyy-MM-dd').format(_studentDate),
      shiftId: _selectedShiftId,
      shiftName: _selectedShiftName,
      onAttendanceUpdated: () {
        _loadStudentData();
      },
    );
  }

  void _openCctvKiosk(List<StudentAttendance> students) async {
    if (!_ensureFeatureAccess('attendance_mark', 'Daily Attendance Marking')) return;

    String? shiftStart;
    if (_selectedShiftId != null) {
      final match = AttendanceTimingHelper.shifts.where((s) => s['id']?.toString() == _selectedShiftId).firstOrNull;
      shiftStart = match?['start_time']?.toString();
    }
    shiftStart ??= AttendanceTimingHelper.shifts.isNotEmpty ? AttendanceTimingHelper.shifts.first['start_time']?.toString() : null;

    List<StudentAttendance> allStudents = List.from(students);
    try {
      final db = await DatabaseHelper().database;
      final rows = await db.query(
        'students',
        where: 'is_active = 1 OR is_active IS NULL',
        orderBy: 'full_name ASC',
      );
      if (rows.isNotEmpty) {
        final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
        List<Map<String, dynamic>> attRows = [];
        try {
          attRows = await db.query('attendance', where: 'date = ?', whereArgs: [dateStr]);
        } catch (_) {}
        final attMap = {for (final a in attRows) a['student_id']?.toString() ?? '': a};
        final initialMap = {for (final s in students) s.id: s};

        allStudents = rows.map((r) {
          final sid = r['id']?.toString() ?? '';
          final existing = initialMap[sid];
          final todayAtt = attMap[sid];
          final fData = existing?.faceData ?? r['face_data']?.toString().trim();
          final photo = existing?.photoPath ?? r['photo_path']?.toString().trim();
          final hasFace = (fData != null && fData.isNotEmpty) ||
              (photo != null && photo.isNotEmpty && File(photo).existsSync());
          return StudentAttendance(
            id: sid,
            registrationNumber: r['registration_number']?.toString() ?? r['gr_no']?.toString() ?? '',
            grNo: r['gr_no']?.toString() ?? '',
            fullName: r['full_name']?.toString() ?? '',
            className: r['class_name']?.toString() ?? '',
            photoPath: photo,
            hasFaceEnrolled: hasFace,
            faceData: fData,
            status: existing != null ? existing.status : todayAtt?['status']?.toString(),
            checkInTime: (existing != null) ? existing.checkInTime : (todayAtt?['check_in_time']?.toString() ?? ''),
            checkOutTime: (existing != null) ? existing.checkOutTime : (todayAtt?['check_out_time']?.toString() ?? ''),
            verificationMethod: existing?.verificationMethod ?? todayAtt?['verification_method']?.toString() ?? 'Manual',
            shiftId: (existing != null && existing.shiftId.isNotEmpty) ? existing.shiftId : (todayAtt?['shift_id']?.toString() ?? _selectedShiftId ?? ''),
            shiftName: (existing != null && existing.shiftName.isNotEmpty) ? existing.shiftName : (todayAtt?['shift_name']?.toString() ?? _selectedShiftName ?? ''),
          );
        }).toList();
      }
    } catch (_) {}

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => CctvAttendanceKioskScreen(
          initialStudents: allStudents,
          repository: AttendanceRepository(ApiClient()),
          shiftId: _selectedShiftId,
          shiftName: _selectedShiftName,
          shiftStartTime: shiftStart,
        ),
      ),
    ).then((_) {
      _loadStudentData();
    });
  }


  void _applyBulkStatus(String targetStatus, List<StudentAttendance> allStudents) {
    if (!_ensureFeatureAccess('attendance_mark', 'Daily Attendance Marking')) return;
    if (targetStatus.isNotEmpty && !_canMarkAttendanceForShift()) return;
    if (allStudents.isEmpty) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
    final targetIds = _selectedStudentIds.isEmpty
        ? allStudents.map((s) => s.id).toList()
        : _selectedStudentIds.toList();

    context.read<AttendanceBloc>().add(
      BulkUpdateStudentStatus(
        studentIds: targetIds,
        status: targetStatus,
        date: dateStr,
        className: _selectedClassName,
        autoSave: true,
        timeMode: _timeRecordingMode,
        shiftId: _selectedShiftId,
        shiftName: _selectedShiftName,
      ),
    );

    setState(() {
      _isAutoSaving = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isAutoSaving = false);
    });

    if (targetStatus.isEmpty) {
      // Immediate local DB purge so that any subsequent screen sees clean state immediately
      DatabaseHelper().database.then((db) async {
        final sId = _selectedShiftId ?? '';
        for (final id in targetIds) {
          await db.delete(
            'attendance',
            where: 'student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = \'\'))',
            whereArgs: [id, dateStr, sId, sId],
          );
        }
      }).catchError((_) {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                '${targetIds.length} students attendance reset / unmarked. ↺',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              '${targetIds.length} students marked $targetStatus & Auto-Saved! ⚡',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: targetStatus == 'Present'
            ? Colors.green
            : (targetStatus == 'Late' ? Colors.orange.shade800 : Colors.red),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _updateStudentStatusWithAutoSave(StudentAttendance s, String fullStatus) {
    if (!_ensureFeatureAccess('attendance_mark', 'Daily Attendance Marking')) return;
    if (fullStatus.isNotEmpty && !_canMarkAttendanceForShift()) return;

    final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
    final timeStr = DateFormat('hh:mm:ss a').format(DateTime.now());

    String? inTime = s.checkInTime;
    String? outTime = s.checkOutTime;

    if (fullStatus == 'Present' || fullStatus == 'Late') {
      if (_timeRecordingMode == 'in_only') {
        if (inTime.isEmpty) inTime = timeStr;
      } else if (_timeRecordingMode == 'out_only') {
        outTime = timeStr;
      } else {
        // 'both'
        if (inTime.isEmpty) {
          inTime = timeStr;
        } else if (outTime.isEmpty) {
          outTime = timeStr;
        }
      }
    } else if (fullStatus == 'Absent' || fullStatus.isEmpty) {
      inTime = '';
      outTime = '';
    }

    context.read<AttendanceBloc>().add(
      AutoSaveStudentStatus(
        studentId: s.id,
        status: fullStatus,
        date: dateStr,
        checkInTime: inTime,
        checkOutTime: outTime,
        verificationMethod: fullStatus.isEmpty
            ? ''
            : (s.verificationMethod.isNotEmpty ? s.verificationMethod : 'Manual'),
        shiftId: _selectedShiftId,
        shiftName: _selectedShiftName,
      ),
    );

    setState(() {
      _isAutoSaving = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _isAutoSaving = false);
    });
  }

  void _showTimeEditorDialog(StudentAttendance s, bool isCheckIn) async {
    final title = isCheckIn ? 'IN Time (Arrival)' : 'OUT Time (Departure)';
    final currentTime = isCheckIn ? s.checkInTime : s.checkOutTime;
    final nowTime = DateFormat('hh:mm:ss a').format(DateTime.now());

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isCheckIn ? Icons.login_rounded : Icons.logout_rounded, color: isCheckIn ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$title: ${s.fullName}',
                    style: AppTheme.getFontStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (currentTime.isNotEmpty) ...[
              Text('Current Recorded Time: $currentTime', style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 12),
            ],
            ListTile(
              leading: const Icon(Icons.bolt_rounded, color: Colors.orange),
              title: Text('Set to Current Time ($nowTime)'),
              onTap: () {
                Navigator.pop(ctx);
                _saveSpecificTime(s, isCheckIn: isCheckIn, newTime: nowTime);
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time_rounded, color: Colors.blue),
              title: const Text('Pick Custom Time'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await DribbbleTimePickerDialog.show(
                  context: context,
                  initialTime: TimeOfDay.now(),
                  title: 'Pick Custom Time',
                );
                if (picked != null && mounted) {
                  final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
                  final minute = picked.minute.toString().padLeft(2, '0');
                  final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
                  final formatted = '${hour.toString().padLeft(2, '0')}:$minute:00 $period';
                  _saveSpecificTime(s, isCheckIn: isCheckIn, newTime: formatted);
                }
              },
            ),
            if (currentTime.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.clear_rounded, color: Colors.red),
                title: Text('Clear $title (Remove)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveSpecificTime(s, isCheckIn: isCheckIn, newTime: '');
                },
              ),
          ],
        ),
      ),
    );
  }

  void _saveSpecificTime(StudentAttendance s, {required bool isCheckIn, required String newTime}) {
    if (newTime.isNotEmpty && !_canMarkAttendanceForShift()) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(_studentDate);
    final inTime = isCheckIn ? newTime : s.checkInTime;
    final outTime = !isCheckIn ? newTime : s.checkOutTime;

    String currentStatus = s.status ?? 'Present';
    if (currentStatus == 'Absent' && (inTime.isNotEmpty || outTime.isNotEmpty)) {
      currentStatus = 'Present';
    }

    context.read<AttendanceBloc>().add(
      AutoSaveStudentStatus(
        studentId: s.id,
        status: currentStatus,
        date: dateStr,
        checkInTime: inTime,
        checkOutTime: outTime,
        verificationMethod: s.verificationMethod.isNotEmpty ? s.verificationMethod : 'Manual',
        shiftId: _selectedShiftId,
        shiftName: _selectedShiftName,
      ),
    );

    setState(() => _isAutoSaving = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isAutoSaving = false);
    });
  }

  void _triggerBiometricScan(String personId, String method, bool isStudent) {
    if (isStudent) {
      if (!_canMarkAttendanceForShift()) return;
      final students = context.read<AttendanceBloc>().state.students;
      final student = students.firstWhere(
        (s) => s.id == personId,
        orElse: () => StudentAttendance(id: personId, fullName: ''),
      );

      final isEnrolled = student.isEnrolledFor(method);
      if (!isEnrolled) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 28),
                const SizedBox(width: 8),
                Text('$method Not Enrolled', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${student.fullName} has no $method data registered.\n\nThe biometric attendance scanner requires an enrolled biometric template or facial photo in the system.',
                  style: AppTheme.getFontStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Would you like to enroll $method now?',
                          style: AppTheme.getFontStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                label: Text('Enroll $method Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: method == 'Face' ? Colors.teal : Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openEnrollmentDialog(student, method);
                },
              ),
            ],
          ),
        );
        return;
      }

      BiometricAttendanceScannerDialog.show(
        context,
        students: students,
        targetStudent: student,
        repository: AttendanceRepository(ApiClient()),
        initialBiometricType: method,
        date: DateFormat('yyyy-MM-dd').format(_studentDate),
        shiftId: _selectedShiftId,
        shiftName: _selectedShiftName,
        onAttendanceUpdated: () {
          _loadStudentData();
        },
      );
    } else {
      setState(() {
        if (method == 'Face') {
          _isFaceScanning = true;
        } else {
          _isFingerScanning = true;
        }
      });

      Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        final timeStr = DateFormat('hh:mm:ss a').format(DateTime.now());
        final dateStr = DateFormat('yyyy-MM-dd').format(_staffDate);
        context.read<AttendanceBloc>().add(
          UpdateStaffVerification(
            staffId: personId,
            method: method,
            time: timeStr,
          ),
        );
        context.read<AttendanceBloc>().add(
          SaveStaffAttendanceData(date: dateStr),
        );
        setState(() {
          _isFaceScanning = false;
          _isFingerScanning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$method verification successful & auto-saved! ✅'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  void _handleScan(String code) {
    if (code.trim().isEmpty) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    context.read<AttendanceBloc>().add(
      ScanAttendance(scannedCode: code.trim(), date: dateStr),
    );
    _scanController.clear();
    // re-focus for next scan
    _scanFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = context.read<AuthBloc>().state;
    bool isAdmin = false;
    if (authState is AuthAuthenticated) {
      isAdmin = authState.roles.any((r) => r['name'] == 'Admin');
    }

    return GestureDetector(
      onTap: () {
        if (_scanModeEnabled) {
          _scanFocusNode.requestFocus();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0F0F1A)
            : const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: Text(
            context.tr('attendance'),
            style: AppTheme.getFontStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: isDark
                ? Colors.grey.shade500
                : Colors.grey.shade600,
            labelStyle: AppTheme.getFontStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            tabs: [
              Tab(icon: const Icon(Icons.school_rounded, size: 18), text: context.tr('students')),
              Tab(icon: const Icon(Icons.view_timeline_rounded, size: 18), text: 'Period Attendance'),
              Tab(icon: const Icon(Icons.badge_rounded, size: 18), text: context.tr('staff')),
              Tab(
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                text: context.tr('scan_mode'),
              ),
              Tab(
                icon: const Icon(Icons.schedule_rounded, size: 18),
                text: context.tr('madarsa_timings_periods'),
              ),
            ],
          ),
        ),
        body: BlocListener<AttendanceBloc, AttendanceState>(
          listener: (context, state) {
            if (state.studentSaved) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr('attendance_saved_success')),
                  backgroundColor: Colors.green,
                ),
              );
              if (state.notifiedParents.isNotEmpty) {
                for (final name in state.notifiedParents) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(
                            Icons.sms_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SMS → Notification sent to parent of $name',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.blue.shade700,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            }
            if (state.staffSaved) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('staff_attendance_saved')),
                  backgroundColor: Colors.green,
                ),
              );
            }
            if (state.scanResult != null) {
              setState(() => _scanLog.insert(0, state.scanResult!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.scanResult!),
                  backgroundColor: state.scanResult!.startsWith('✅')
                      ? Colors.green
                      : Colors.red,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: ${state.error}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStudentTab(isDark),
              _buildPeriodAttendanceTab(isDark),
              _buildStaffTab(isDark, isAdmin),
              _buildScanTab(isDark, isAdmin),
              MadarsaTimingsScreen(
                isEmbedded: true,
                onShiftsChanged: _initTimingsAndShifts,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDENT TAB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStudentTab(bool isDark) {
    if (_loadingClasses) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── filters ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('class_dropdown_${_selectedClassName}_${_classesList.length}'),
                      value: (_selectedClassName != null && _classesList.contains(_selectedClassName))
                          ? _selectedClassName
                          : (_classesList.isNotEmpty ? _classesList.first : null),
                      decoration: InputDecoration(
                        labelText: context.tr('select_class'),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: _classesList.map((clsName) {
                        return DropdownMenuItem<String>(
                          value: clsName,
                          child: Text(
                            clsName,
                            style: AppTheme.getFontStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _selectedClassName) {
                          setState(() {
                            _selectedClassName = val;
                            _selectedStudentIds.clear();
                          });
                          _loadStudentData();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: _pickStudentDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 20, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(_studentDate),
                                  style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down_circle_outlined, size: 18, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildShiftBar(isDark),
          const SizedBox(height: 8),
          // ── list ──
          Expanded(
            child: BlocBuilder<AttendanceBloc, AttendanceState>(
              buildWhen: (prev, curr) =>
                  prev.students != curr.students ||
                  prev.studentLoading != curr.studentLoading,
              builder: (context, state) {
                if (state.studentLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = state.students;
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      'No students found in this class.',
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    _buildBulkAttendanceToolbar(list, isDark),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) =>
                            _buildStudentCard(list[i], isDark),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkAttendanceToolbar(List<StudentAttendance> students, bool isDark) {
    final allSelected = students.isNotEmpty && _selectedStudentIds.length == students.length;
    final anySelected = _selectedStudentIds.isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E1E2F), const Color(0xFF252538)]
                : [const Color(0xFFF0FDF4), const Color(0xFFF8FAFC)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.green.shade100,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: allSelected ? true : (anySelected ? null : false),
                      tristate: true,
                      activeColor: AppTheme.primaryColor,
                      onChanged: (val) {
                        setState(() {
                          if (allSelected) {
                            _selectedStudentIds.clear();
                          } else {
                            _selectedStudentIds.clear();
                            _selectedStudentIds.addAll(students.map((s) => s.id));
                          }
                        });
                      },
                    ),
                    Text(
                      anySelected
                          ? '${_selectedStudentIds.length}/${students.length} Selected'
                          : 'Select All (${students.length})',
                      style: AppTheme.getFontStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isAutoSaving
                        ? Colors.amber.withAlpha(40)
                        : Colors.green.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isAutoSaving ? Colors.amber : Colors.green.shade400,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isAutoSaving ? Icons.sync_rounded : Icons.bolt_rounded,
                        size: 14,
                        color: _isAutoSaving ? Colors.amber.shade800 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isAutoSaving ? 'Auto-Saving...' : 'Auto-Save Active',
                        style: AppTheme.getFontStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _isAutoSaving ? Colors.amber.shade900 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text(
                    anySelected ? 'Mark Selected Present' : 'Mark All Present',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _applyBulkStatus('Present', students),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text(
                    anySelected ? 'Mark Selected Absent' : 'Mark All Absent',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _applyBulkStatus('Absent', students),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.access_time_filled_rounded, size: 16),
                  label: Text(
                    anySelected ? 'Mark Selected Late' : 'Mark All Late',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _applyBulkStatus('Late', students),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.blueGrey),
                  label: Text(
                    anySelected ? 'Reset Selected' : 'Reset / Re-mark All',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.blueGrey.shade400, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _applyBulkStatus('', students),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.fingerprint_rounded, size: 16),
                  label: Text(
                    'Register Biometrics',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showStudentBiometricRegistrationPicker(students),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: Colors.teal),
                  label: Text(
                    'Biometric Scanner',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.teal, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openBiometricScanner(students),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.videocam_rounded, size: 16),
                  label: Text(
                    '🎥 CCTV Live Kiosk',
                    style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openCctvKiosk(students),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.white.withAlpha(220),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 15, color: Colors.teal),
                      const SizedBox(width: 5),
                      Text(
                        'Time Option:',
                        style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  _buildTimeModeChip('in_only', '🟢 IN Only', 'Only entry / check-in time will be saved'),
                  _buildTimeModeChip('out_only', '🔴 OUT Only', 'Only departure / check-out time will be saved'),
                  _buildTimeModeChip('both', '🔄 Both (IN & OUT)', 'Both check-in and check-out times will be saved'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeModeChip(String mode, String label, String tooltip) {
    final isSelected = _timeRecordingMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          setState(() {
            _timeRecordingMode = mode;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade400,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentCard(StudentAttendance s, bool isDark) {
    final isSelected = _selectedStudentIds.contains(s.id);
    final faceEnrolled = s.isEnrolledFor('Face');
    final fingerEnrolled = s.isEnrolledFor('Fingerprint');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              activeColor: AppTheme.primaryColor,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedStudentIds.add(s.id);
                  } else {
                    _selectedStudentIds.remove(s.id);
                  }
                });
              },
            ),
            Builder(
              builder: (context) {
                final photoProvider = _getStudentPhotoProvider(s.photoPath);
                return CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withAlpha(20),
                  backgroundImage: photoProvider,
                  child: photoProvider == null
                      ? Text(
                          s.fullName.isNotEmpty
                              ? s.fullName.substring(0, 1).toUpperCase()
                              : '?',
                          style: AppTheme.getFontStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                );
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fullName,
                    style: AppTheme.getFontStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'GR: ${s.grNo ?? s.registrationNumber}',
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      if (s.status == 'Late')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.orange.shade700, width: 0.9),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.alarm_on_rounded, size: 11, color: Colors.orange.shade900),
                              const SizedBox(width: 2),
                              Text(
                                'LATE',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      InkWell(
                        onTap: () => _openEnrollmentDialog(s, 'Face'),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: faceEnrolled ? Colors.teal.withAlpha(20) : Colors.grey.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: faceEnrolled ? Colors.teal.withAlpha(80) : Colors.grey.withAlpha(60),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.face_rounded,
                                size: 11,
                                color: faceEnrolled ? Colors.teal : Colors.grey,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                faceEnrolled ? 'Face ✓' : 'Face +',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: faceEnrolled ? Colors.teal : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _openEnrollmentDialog(s, 'Fingerprint'),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: fingerEnrolled ? Colors.blue.withAlpha(20) : Colors.grey.withAlpha(20),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: fingerEnrolled ? Colors.blue.withAlpha(80) : Colors.grey.withAlpha(60),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fingerprint_rounded,
                                size: 11,
                                color: fingerEnrolled ? Colors.blue : Colors.grey,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                fingerEnrolled ? 'Finger ✓' : 'Finger +',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: fingerEnrolled ? Colors.blue : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Interactive IN Time Chip with distinct Late indicator
                      Builder(
                        builder: (context) {
                          final isLate = s.status == 'Late';
                          final inBgColor = isLate
                              ? Colors.orange.withAlpha(25)
                              : (s.checkInTime.isNotEmpty ? Colors.green.withAlpha(20) : Colors.grey.withAlpha(15));
                          final inBorderColor = isLate
                              ? Colors.orange.shade700
                              : (s.checkInTime.isNotEmpty ? Colors.green.shade600 : Colors.grey.shade400);
                          final inTextColor = isLate
                              ? Colors.orange.shade900
                              : (s.checkInTime.isNotEmpty ? Colors.green.shade900 : Colors.grey.shade700);
                          final inIcon = isLate
                              ? Icons.alarm_on_rounded
                              : Icons.login_rounded;
                          final inIconColor = isLate
                              ? Colors.orange.shade900
                              : (s.checkInTime.isNotEmpty ? Colors.green.shade800 : Colors.grey.shade600);
                          final inText = s.checkInTime.isNotEmpty
                              ? (isLate ? 'IN (Late): ${s.checkInTime}' : 'IN: ${s.checkInTime}')
                              : '+ IN Time';

                          return Tooltip(
                            message: 'Click to set, change, or clear IN Time',
                            child: InkWell(
                              onTap: () => _showTimeEditorDialog(s, true),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: inBgColor,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: inBorderColor,
                                    width: (isLate || s.checkInTime.isNotEmpty) ? 1.2 : 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      inIcon,
                                      size: 11,
                                      color: inIconColor,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      inText,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 10,
                                        color: inTextColor,
                                        fontWeight: (isLate || s.checkInTime.isNotEmpty) ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Interactive OUT Time Chip
                      Tooltip(
                        message: 'Click to set, change, or clear OUT Time',
                        child: InkWell(
                          onTap: () => _showTimeEditorDialog(s, false),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: s.checkOutTime.isNotEmpty ? Colors.red.withAlpha(20) : Colors.grey.withAlpha(15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: s.checkOutTime.isNotEmpty ? Colors.red.shade600 : Colors.grey.shade400,
                                width: s.checkOutTime.isNotEmpty ? 1.2 : 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.logout_rounded,
                                  size: 11,
                                  color: s.checkOutTime.isNotEmpty ? Colors.red.shade800 : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  s.checkOutTime.isNotEmpty ? 'OUT: ${s.checkOutTime}' : '+ OUT Time',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 10,
                                    color: s.checkOutTime.isNotEmpty ? Colors.red.shade900 : Colors.grey.shade700,
                                    fontWeight: s.checkOutTime.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (s.verificationMethod.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.withAlpha(15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'via ${s.verificationMethod}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.indigo,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Face Scan Attendance (Cam / External)',
              icon: Icon(
                Icons.face_retouching_natural_rounded,
                color: faceEnrolled ? Colors.teal : Colors.grey.shade400,
              ),
              onPressed: () => _triggerBiometricScan(s.id, 'Face', true),
            ),
            IconButton(
              tooltip: 'Fingerprint Attendance (Mobile / USB)',
              icon: Icon(
                Icons.fingerprint_rounded,
                color: fingerEnrolled ? Colors.blue : Colors.grey.shade400,
              ),
              onPressed: () => _triggerBiometricScan(s.id, 'Fingerprint', true),
            ),
            _statusChip(
              'P',
              'Present',
              s.status == 'Present',
              Colors.green,
              s.id,
              true,
            ),
            const SizedBox(width: 4),
            _statusChip(
              'A',
              'Absent',
              s.status == 'Absent',
              Colors.red,
              s.id,
              true,
            ),
            const SizedBox(width: 4),
            _statusChip(
              'L',
              'Late',
              s.status == 'Late',
              Colors.orange,
              s.id,
              true,
            ),
            if (s.status != null && s.status!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Clear / Reset Attendance',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _updateStudentStatusWithAutoSave(s, ''),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withAlpha(20),
                      border: Border.all(color: Colors.blueGrey.shade300, width: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.refresh_rounded, size: 16, color: Colors.blueGrey),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShiftBar(bool isDark) {
    if (AttendanceTimingHelper.shifts.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No shifts found. Add shifts in "Madarsa Timings & Periods" tab.',
                style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'Reload Shifts',
              onPressed: () => _initTimingsAndShifts(),
            ),
          ],
        ),
      );
    }

    final windowCheck = AttendanceTimingHelper.checkShiftWindow(
      DateTime.now(),
      targetShiftId: _selectedShiftId,
    );
    final isOutside = !windowCheck.isWithinWindow;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOutside && !_manualShiftOverride
              ? Colors.orange.shade400
              : (isDark ? Colors.white12 : Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                'Shift:',
                style: AppTheme.getFontStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: AttendanceTimingHelper.shifts.map((shift) {
                      final sId = shift['id']?.toString() ?? '';
                      final sName = shift['name']?.toString() ?? shift['shift_name']?.toString() ?? 'Shift';
                      final isSelected = _selectedShiftId == sId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('$sName (${shift['start_time'] ?? '08:00'} - ${shift['end_time'] ?? '13:00'})'),
                          labelStyle: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryColor,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedShiftId = sId;
                                _selectedShiftName = sName;
                                _selectedStudentIds.clear();
                              });
                              _loadStudentData();
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              Tooltip(
                message: 'Refresh Shifts',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await _initTimingsAndShifts();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Shifts refreshed! 🔄'),
                          duration: Duration(milliseconds: 900),
                        ),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryColor),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: _manualShiftOverride
                    ? 'Manual Override ON: Shift time restriction is disabled.'
                    : 'Click to enable Manual Override for attendance outside shift hours.',
                child: FilterChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    _manualShiftOverride ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                    size: 14,
                    color: _manualShiftOverride ? Colors.orange.shade900 : Colors.grey.shade700,
                  ),
                  label: Text(
                    _manualShiftOverride ? 'Override ON 🔓' : 'Shift Lock 🔒',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _manualShiftOverride ? Colors.orange.shade900 : Colors.grey.shade700,
                    ),
                  ),
                  selected: _manualShiftOverride,
                  selectedColor: Colors.orange.withAlpha(50),
                  onSelected: (val) {
                    setState(() => _manualShiftOverride = val);
                    if (val) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Manual Override Activated! You can now mark attendance anytime. 🔓'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          if (isOutside && !_manualShiftOverride) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade300, width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 13, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Currently outside shift hours (${windowCheck.shiftStartTime} - ${windowCheck.shiftEndTime}). Turn on "Override ON 🔓" to mark attendance.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() => _manualShiftOverride = true);
                    },
                    child: Text(
                      'ENABLE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERIOD ATTENDANCE
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _pickPeriodDate() async {
    final picked = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: _periodDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      title: 'Period Attendance Date',
    );
    if (picked != null && picked != _periodDate) {
      setState(() => _periodDate = picked);
      _loadPeriodData();
    }
  }

  Future<void> _loadPeriodData() async {
    if (_periodClassName == null) return;
    setState(() {
      _loadingPeriods = true;
      _loadingPeriodStudents = true;
    });

    try {
      final classId = _classNameToId[_periodClassName] ?? '';
      List<Map<String, dynamic>> periods = [];
      try {
        final client = ApiClient();
        final res = await client.get('/academic/class-periods', queryParams: {'class_id': classId});
        if (res.data is List && (res.data as List).isNotEmpty) {
          periods = List<Map<String, dynamic>>.from(res.data as List);
        }
      } catch (e) {
        debugPrint('Failed to load class periods: $e');
      }

      if (periods.isEmpty) {
        periods = List.generate(8, (i) => {
          'period_number': i + 1,
          'book_name': 'Period ${i + 1}',
          'start_time': '${(8 + i).toString().padLeft(2, '0')}:00',
          'end_time': '${(8 + i + 1).toString().padLeft(2, '0')}:00',
        });
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_periodDate);
      final students = await AttendanceRepository(ApiClient()).getStudentAttendance(
        className: _periodClassName!,
        date: dateStr,
      );

      final pRecords = await AttendanceRepository(ApiClient()).getPeriodAttendance(
        className: _periodClassName!,
        classId: classId,
        date: dateStr,
        periodNumber: _selectedPeriodNumber,
      );

      final Map<String, PeriodAttendanceRecord> recordMap = {};
      for (final r in pRecords) {
        recordMap[r.studentId] = r;
      }

      if (!mounted) return;
      setState(() {
        _classPeriodsList = periods;
        _periodStudents = students;
        _periodRecords = recordMap;
        _loadingPeriods = false;
        _loadingPeriodStudents = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPeriods = false;
          _loadingPeriodStudents = false;
        });
      }
    }
  }

  Future<void> _selectPeriod(int periodNum) async {
    setState(() {
      _selectedPeriodNumber = periodNum;
      _loadingPeriodStudents = true;
    });

    try {
      final classId = _classNameToId[_periodClassName] ?? '';
      final dateStr = DateFormat('yyyy-MM-dd').format(_periodDate);
      final pRecords = await AttendanceRepository(ApiClient()).getPeriodAttendance(
        className: _periodClassName!,
        classId: classId,
        date: dateStr,
        periodNumber: periodNum,
      );

      final Map<String, PeriodAttendanceRecord> recordMap = {};
      for (final r in pRecords) {
        recordMap[r.studentId] = r;
      }

      if (mounted) {
        setState(() {
          _periodRecords = recordMap;
          _loadingPeriodStudents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPeriodStudents = false);
    }
  }

  Future<void> _markPeriodStudentStatus(StudentAttendance student, String status) async {
    final nowTime = DateFormat('hh:mm:ss a').format(DateTime.now());
    final dateStr = DateFormat('yyyy-MM-dd').format(_periodDate);
    final classId = _classNameToId[_periodClassName] ?? '';

    String? periodId;
    final matchingPeriod = _classPeriodsList.firstWhere(
      (p) => (int.tryParse(p['period_number']?.toString() ?? '') ?? 0) == _selectedPeriodNumber,
      orElse: () => <String, dynamic>{},
    );
    if (matchingPeriod.isNotEmpty) {
      periodId = matchingPeriod['id']?.toString();
    }

    final newRecord = PeriodAttendanceRecord(
      studentId: student.id,
      fullName: student.fullName,
      grNo: student.grNo,
      classId: classId,
      periodId: periodId,
      periodNumber: _selectedPeriodNumber,
      date: dateStr,
      status: status,
      time: nowTime,
    );

    setState(() {
      _periodRecords[student.id] = newRecord;
    });

    try {
      await AttendanceRepository(ApiClient()).saveSinglePeriodAttendance(
        studentId: student.id,
        classId: classId,
        periodId: periodId,
        periodNumber: _selectedPeriodNumber,
        date: dateStr,
        status: status,
        time: nowTime,
      );
    } catch (e) {
      debugPrint('Auto-save period attendance failed: $e');
    }
  }

  Future<void> _bulkMarkPeriodAttendance(String status) async {
    if (_periodStudents.isEmpty) return;

    final nowTime = DateFormat('hh:mm:ss a').format(DateTime.now());
    final dateStr = DateFormat('yyyy-MM-dd').format(_periodDate);
    final classId = _classNameToId[_periodClassName] ?? '';
    final studentIds = _periodStudents.map((s) => s.id).toList();

    String? periodId;
    final matchingPeriod = _classPeriodsList.firstWhere(
      (p) => (int.tryParse(p['period_number']?.toString() ?? '') ?? 0) == _selectedPeriodNumber,
      orElse: () => <String, dynamic>{},
    );
    if (matchingPeriod.isNotEmpty) {
      periodId = matchingPeriod['id']?.toString();
    }

    setState(() {
      for (final s in _periodStudents) {
        _periodRecords[s.id] = PeriodAttendanceRecord(
          studentId: s.id,
          fullName: s.fullName,
          grNo: s.grNo,
          classId: classId,
          periodId: periodId,
          periodNumber: _selectedPeriodNumber,
          date: dateStr,
          status: status,
          time: nowTime,
        );
      }
    });

    try {
      await AttendanceRepository(ApiClient()).bulkPeriodAttendance(
        classId: classId,
        periodId: periodId,
        periodNumber: _selectedPeriodNumber,
        date: dateStr,
        status: status,
        studentIds: studentIds,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Period $_selectedPeriodNumber: All ${studentIds.length} students marked $status! ⚡',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: status == 'Present' ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Bulk period attendance failed: $e');
    }
  }

  Widget _buildPeriodAttendanceTab(bool isDark) {
    if (_loadingClasses) {
      return const Center(child: CircularProgressIndicator());
    }

    final totalStudents = _periodStudents.length;
    int presentCount = 0;
    int absentCount = 0;
    for (final s in _periodStudents) {
      final rec = _periodRecords[s.id];
      if (rec != null) {
        if (rec.status == 'Present') presentCount++;
        if (rec.status == 'Absent') absentCount++;
      }
    }
    final double percentage = totalStudents > 0 ? (presentCount / totalStudents) * 100 : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Class & Date Selector Card ──
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('period_class_dropdown_${_periodClassName}_${_classesList.length}'),
                      value: (_periodClassName != null && _classesList.contains(_periodClassName))
                          ? _periodClassName
                          : (_classesList.isNotEmpty ? _classesList.first : null),
                      decoration: InputDecoration(
                        labelText: 'Select Class',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: _classesList.map((clsName) {
                        return DropdownMenuItem<String>(
                          value: clsName,
                          child: Text(
                            clsName,
                            style: AppTheme.getFontStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null && val != _periodClassName) {
                          setState(() {
                            _periodClassName = val;
                          });
                          _loadPeriodData();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: InkWell(
                      onTap: _pickPeriodDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.calendar_month_rounded, size: 20, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('dd/MM/yyyy').format(_periodDate),
                                  style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            const Icon(Icons.arrow_drop_down_circle_outlined, size: 18, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Period Chips Selector ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: Colors.teal.shade400),
                const SizedBox(width: 8),
                Text(
                  'Periods:',
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _loadingPeriods
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _classPeriodsList.map((p) {
                              final pNum = int.tryParse(p['period_number']?.toString() ?? '') ?? 1;
                              final bookName = p['book_name']?.toString() ?? p['name']?.toString() ?? 'Period $pNum';
                              final timeSpan = (p['start_time'] != null && p['end_time'] != null)
                                  ? ' (${p['start_time']} - ${p['end_time']})'
                                  : '';
                              final isSelected = _selectedPeriodNumber == pNum;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text('P$pNum: $bookName$timeSpan'),
                                  labelStyle: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.teal.shade700,
                                  onSelected: (val) {
                                    if (val) {
                                      _selectPeriod(pNum);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Period Stats & Quick Bulk Actions Bar ──
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.teal.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal),
                        ),
                        child: Text(
                          'Period $_selectedPeriodNumber',
                          style: AppTheme.getFontStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ),
                      Text(
                        'Total: $totalStudents',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'P: $presentCount',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'A: $absentCount',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                      ),
                      Text(
                        '(${percentage.toStringAsFixed(0)}%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: percentage >= 75 ? Colors.green.shade700 : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle_rounded, size: 14),
                        label: const Text('All Present', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => _bulkMarkPeriodAttendance('Present'),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cancel_rounded, size: 14),
                        label: const Text('All Absent', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () => _bulkMarkPeriodAttendance('Absent'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Period Students List ──
          Expanded(
            child: _loadingPeriodStudents
                ? const Center(child: CircularProgressIndicator())
                : _periodStudents.isEmpty
                    ? Center(
                        child: Text(
                          'No students found in this class.',
                          style: AppTheme.getFontStyle(fontSize: 14, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _periodStudents.length,
                        itemBuilder: (ctx, i) {
                          final s = _periodStudents[i];
                          final rec = _periodRecords[s.id];
                          final status = rec?.status ?? '';
                          final isPresent = status == 'Present';
                          final isAbsent = status == 'Absent';
                          final timeStr = rec?.time ?? '';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isPresent
                                    ? Colors.green.shade300
                                    : (isAbsent
                                        ? Colors.red.shade300
                                        : (isDark ? Colors.grey.shade800 : Colors.grey.shade300)),
                                width: (isPresent || isAbsent) ? 1.2 : 0.8,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isPresent
                                        ? Colors.green.withAlpha(30)
                                        : (isAbsent ? Colors.red.withAlpha(30) : Colors.grey.withAlpha(30)),
                                    child: Text(
                                      s.fullName.isNotEmpty ? s.fullName.substring(0, 1).toUpperCase() : '?',
                                      style: TextStyle(
                                        color: isPresent ? Colors.green : (isAbsent ? Colors.red : Colors.grey),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.fullName,
                                          style: AppTheme.getFontStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              'GR: ${s.grNo ?? s.registrationNumber}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                            if (timeStr.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade600),
                                              const SizedBox(width: 3),
                                              Text(
                                                timeStr,
                                                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (status.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPresent ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isPresent ? Colors.green : Colors.red,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isPresent ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                            size: 11,
                                            color: isPresent ? Colors.green : Colors.red,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isPresent ? Colors.green : Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _markPeriodStudentStatus(s, 'Present'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isPresent ? Colors.green.shade600 : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.green.shade600,
                                          width: isPresent ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Text(
                                        'P',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isPresent ? Colors.white : Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _markPeriodStudentStatus(s, 'Absent'),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isAbsent ? Colors.red.shade600 : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.red.shade600,
                                          width: isAbsent ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Text(
                                        'A',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isAbsent ? Colors.white : Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAFF TAB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildStaffTab(bool isDark, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── date / time row ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: isAdmin ? () => _pickStaffDate(isAdmin) : null,
                      child: _dateTimeBox(
                        'Date: ${DateFormat('dd/MM/yyyy').format(_staffDate)}',
                        Icons.calendar_today_rounded,
                        !isAdmin,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: isAdmin ? () => _pickStaffTime(isAdmin) : null,
                      child: _dateTimeBox(
                        'Time: ${_staffTime.format(context)}',
                        Icons.access_time_rounded,
                        !isAdmin,
                      ),
                    ),
                  ),
                  if (!isAdmin) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(15),
                        border: Border.all(color: Colors.amber.shade700),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Tooltip(
                        message: 'Only Admin can edit date & time',
                        child: Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_isFaceScanning || _isFingerScanning) ...[
            _buildBiometricAnimation(),
            const SizedBox(height: 12),
          ],
          // ── staff list ──
          Expanded(
            child: BlocBuilder<AttendanceBloc, AttendanceState>(
              buildWhen: (prev, curr) =>
                  prev.staff != curr.staff ||
                  prev.staffLoading != curr.staffLoading,
              builder: (context, state) {
                if (state.staffLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = state.staff;
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      'No staff members found.',
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) =>
                            _buildStaffCard(list[i], isDark, isAdmin),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffCard(StaffAttendance s, bool isDark, bool isAdmin) {
    final checkedIn = s.checkInTime.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.withAlpha(20),
              child: Text(
                s.fullName.isNotEmpty
                    ? s.fullName.substring(0, 1).toUpperCase()
                    : '?',
                style: AppTheme.getFontStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.fullName,
                    style: AppTheme.getFontStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.staffType} • ${s.staffNo}',
                    style: AppTheme.getFontStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  if (checkedIn || s.checkOutTime.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (checkedIn)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.withAlpha(50)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.login_rounded, size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  'IN: ${s.checkInTime}',
                                  style: AppTheme.getFontStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        if (s.checkOutTime.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.withAlpha(50)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.logout_rounded, size: 12, color: Colors.red),
                                const SizedBox(width: 4),
                                Text(
                                  'OUT: ${s.checkOutTime}',
                                  style: AppTheme.getFontStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (s.checkOutTime.isEmpty) ...[
              IconButton(
                tooltip: context.tr('face_scan'),
                icon: const Icon(
                  Icons.face_retouching_natural_rounded,
                  color: Colors.teal,
                ),
                onPressed: () => _triggerBiometricScan(s.id, 'Face', false),
              ),
              IconButton(
                tooltip: context.tr('fingerprint'),
                icon: const Icon(Icons.fingerprint_rounded, color: Colors.blue),
                onPressed: () => _triggerBiometricScan(s.id, 'Fingerprint', false),
              ),
            ],
            const SizedBox(width: 4),
            _statusChip(
              'P',
              'Present',
              s.status == 'Present',
              Colors.green,
              s.id,
              false,
            ),
            const SizedBox(width: 4),
            _statusChip(
              'A',
              'Absent',
              s.status == 'Absent',
              Colors.red,
              s.id,
              false,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCAN MODE TAB
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildScanTab(bool isDark, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── scan mode header ──
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _scanModeEnabled
                    ? Colors.green.withAlpha(100)
                    : Colors.grey.shade300,
                width: 1.5,
              ),
            ),
            color: _scanModeEnabled ? Colors.green.withAlpha(15) : null,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 40,
                        color: _scanModeEnabled ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'External Scanner Mode',
                              style: AppTheme.getFontStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _scanModeEnabled
                                  ? 'Scanner active — scan any barcode / QR code, or type GR No / Staff No and press Enter'
                                  : 'Turn on to accept input from barcode scanners, QR readers, or cameras',
                              style: AppTheme.getFontStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _scanModeEnabled,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          setState(() => _scanModeEnabled = val);
                          if (val) {
                            // Ensure both student and staff data are loaded
                            _loadStudentData();
                            _loadStaffData();
                            Future.delayed(
                              const Duration(milliseconds: 300),
                              () => _scanFocusNode.requestFocus(),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  if (_scanModeEnabled) ...[
                    const SizedBox(height: 16),
                    // ── scan input field ──
                    RawKeyboardListener(
                      focusNode: FocusNode(),
                      onKey: (_) {},
                      child: TextField(
                        controller: _scanController,
                        focusNode: _scanFocusNode,
                        autofocus: _scanModeEnabled,
                        decoration: InputDecoration(
                          hintText:
                              'Scan barcode / QR or type GR No / Staff No...',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.send_rounded),
                            onPressed: () => _handleScan(_scanController.text),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.white.withAlpha(10)
                              : Colors.white,
                        ),
                        style: AppTheme.getFontStyle(fontSize: 16),
                        onSubmitted: _handleScan,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── info banner ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withAlpha(15),
                        border: Border.all(color: Colors.blue.withAlpha(60)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'USB Barcode Scanner automatically types the code and presses Enter.\n'
                              'Camera/QR Scanner se bhi scan kar sakte hain. Student ka GR No ya Staff No scan hona chahiye.',
                              style: AppTheme.getFontStyle(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // ── scan log ──
          Expanded(
            child: _scanLog.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _scanModeEnabled
                              ? 'Ready to scan...'
                              : 'Enable Scan Mode to start',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanLog.length,
                    itemBuilder: (_, i) {
                      final log = _scanLog[i];
                      final isSuccess = log.startsWith('✅');
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: isSuccess
                            ? Colors.green.withAlpha(15)
                            : Colors.red.withAlpha(15),
                        child: ListTile(
                          leading: Icon(
                            isSuccess
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            color: isSuccess ? Colors.green : Colors.red,
                          ),
                          title: Text(
                            log,
                            style: AppTheme.getFontStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            DateFormat(
                              'dd/MM/yyyy - hh:mm:ss a',
                            ).format(DateTime.now()),
                            style: AppTheme.getFontStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _statusChip(
    String short,
    String full,
    bool selected,
    Color color,
    String personId,
    bool isStudent,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (isStudent) {
          final students = context.read<AttendanceBloc>().state.students;
          final s = students.firstWhere(
            (x) => x.id == personId,
            orElse: () => StudentAttendance(id: personId, fullName: ''),
          );
          if (selected) {
            _updateStudentStatusWithAutoSave(s, '');
          } else {
            _updateStudentStatusWithAutoSave(s, full);
          }
        } else {
          final dateStr = DateFormat('yyyy-MM-dd').format(_staffDate);
          if (full == 'Present') {
            final timeStr = DateFormat('hh:mm:ss a').format(DateTime.now());
            context.read<AttendanceBloc>().add(
              UpdateStaffVerification(
                staffId: personId,
                method: 'Manual',
                time: timeStr,
              ),
            );
          } else {
            context.read<AttendanceBloc>().add(
              UpdateStaffStatus(staffId: personId, status: full),
            );
          }
          context.read<AttendanceBloc>().add(
            SaveStaffAttendanceData(date: dateStr),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(25) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Colors.grey.shade400,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          short,
          style: AppTheme.getFontStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? color : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _dateTimeBox(String text, IconData icon, bool locked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: locked ? Colors.grey.shade100.withAlpha(20) : Colors.transparent,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: locked ? Colors.grey : AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                text,
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: locked ? Colors.grey : null,
                ),
              ),
            ],
          ),
          Icon(
            Icons.arrow_drop_down_circle_outlined,
            size: 18,
            color: locked ? Colors.grey.shade300 : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricAnimation() {
    final isFace = _isFaceScanning;
    final title = isFace ? 'Face Scanner Active' : 'Fingerprint Scanner Active';
    final desc = isFace
        ? 'Scanning facial parameters...'
        : 'Reading fingerprint sensor...';
    final icon = isFace
        ? Icons.face_retouching_natural_rounded
        : Icons.fingerprint_rounded;
    final color = isFace ? Colors.teal : Colors.blue;

    return Card(
      color: color.withAlpha(20),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withAlpha(100), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: 140,
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: AppTheme.getFontStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Icon(icon, size: 32, color: color),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              desc,
              style: AppTheme.getFontStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
