import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/pdf_service.dart';
import '../../../classes/data/repositories/academic_repository.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../bloc/exam_bloc.dart';
import '../bloc/exam_event.dart';
import '../bloc/exam_state.dart';
import '../../data/models/exam_models.dart';
import '../../data/repositories/exam_local_repository.dart';
import '../../data/services/exam_result_export_service.dart';
import '../../data/services/seating_export_service.dart';
import '../../data/algorithm/seating_models.dart';
import '../widgets/seating_grid_widget.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/grading_helper.dart';
import '../../../../shared/widgets/dribbble_date_picker.dart';
import '../../../../shared/widgets/dribbble_time_picker.dart';
import '../../../../core/licensing/license_cubit.dart';
import '../../../../core/licensing/license_model.dart';
import '../../../licensing/presentation/upgrade_plan_dialog.dart';
import 'result_card_designer_screen.dart';
import '../../../students/data/models/student_model.dart';

class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<int> _expandedExamIds = {};
  final Map<int, List<ExamSchedule>> _examSchedulesMap = {};
  List<Exam> _cachedExams = [];

  bool _ensureFeatureAccess(String featureKey, String featureName) {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess(featureKey)) {
      UpgradePlanDialog.show(context, highlightModule: featureName);
      return false;
    }
    return true;
  }
  List<ExamHall> _cachedHalls = [];
  List<ExamSchedule> _cachedSchedules = [];
  SeatingResult? _cachedSeatingResult;
  ExamHall? _cachedSeatingHall;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    context.read<ExamBloc>().add(LoadExamsData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocConsumer<ExamBloc, ExamState>(
      listener: (context, state) {
        if (state is ExamError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (state is ExamOperationSuccess) {
          if (state.message.toLowerCase().contains('cleared')) {
            _cachedSeatingResult = null;
            _cachedSeatingHall = null;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is ExamLoaded) {
          _cachedExams = state.exams;
          _cachedHalls = state.halls;
          _examSchedulesMap.addAll(state.schedulesMap);
        } else if (state is SchedulesLoaded) {
          _cachedExams = state.exams;
          _cachedHalls = state.halls;
          _cachedSchedules = state.schedules;
          _examSchedulesMap.addAll(state.schedulesMap);
        } else if (state is SeatingGenerated) {
          _cachedSeatingResult = state.result;
          _cachedSeatingHall = state.hall;
        }

        final exams = _cachedExams;
        final halls = _cachedHalls;
        final currentSchedules = _cachedSchedules;

        // Auto-expand single exam if present
        if (exams.length == 1 && exams.first.id != null && _expandedExamIds.isEmpty) {
          _expandedExamIds.add(exams.first.id!);
          context.read<ExamBloc>().add(LoadSchedules(exams.first.id!));
        }

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF14142B) : const Color(0xFFF8F9FA),
          body: Column(
            children: [
              // ── Header Bar ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      context.tr('exam_management'),
                      style: AppTheme.getFontStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () => _showAddExamDialog(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(context.tr('create_exam')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Tab Bar ──
              Container(
                color: isDark ? const Color(0xFF181828) : Colors.grey.shade50,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppTheme.primaryColor,
                  indicatorWeight: 3,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.event_note_rounded, size: 20),
                      text: context.tr('exam_sessions'),
                    ),
                    Tab(
                      icon: const Icon(Icons.business_rounded, size: 20),
                      text: context.tr('exam_halls'),
                    ),
                    Tab(
                      icon: const Icon(Icons.event_seat_rounded, size: 20),
                      text: context.tr('seating_plan'),
                    ),
                    Tab(
                      icon: const Icon(Icons.edit_note_rounded, size: 20),
                      text: context.tr('marks_entry'),
                    ),
                    Tab(
                      icon: const Icon(Icons.assessment_rounded, size: 20),
                      text: context.tr('results_report'),
                    ),
                  ],
                ),
              ),

              // ── Tab Views ──
              Expanded(
                child: (state is ExamLoading && exams.isEmpty && halls.isEmpty)
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildExamSessionsTab(exams, currentSchedules),
                          _HallsTab(halls: halls),
                          _SeatingTab(
                            exams: exams,
                            halls: halls,
                            result: _cachedSeatingResult,
                            resultHall: _cachedSeatingHall,
                          ),
                          _MarksTab(exams: exams),
                          _ResultsTab(exams: exams),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExamSessionsTab(List<Exam> exams, List<ExamSchedule> currentSchedules) {
    if (exams.isEmpty) {
      return _EmptyState(
        icon: Icons.event_note_rounded,
        label: context.tr('no_exams'),
        subtitle: context.tr('no_exams_subtitle'),
        action: ElevatedButton.icon(
          onPressed: () => _showAddExamDialog(context),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(
            context.tr('create_exam'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: exams.length,
      itemBuilder: (context, index) {
        final exam = exams[index];
        final examSchedules = _examSchedulesMap[exam.id] ??
            currentSchedules.where((s) => s.examId == exam.id).toList();
        return _buildExamCard(exam, examSchedules);
      },
    );
  }

  Widget _buildExamCard(Exam exam, List<ExamSchedule> currentSchedules) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpanded = exam.id != null && _expandedExamIds.contains(exam.id);

    return Card(
      key: ValueKey('exam_card_${exam.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: isDark ? const Color(0xFF1E1E32) : Colors.white,
      child: ExpansionTile(
        key: PageStorageKey<String>('exam_tile_${exam.id}'),
        initiallyExpanded: isExpanded,
        shape: const Border(),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded && exam.id != null) {
              _expandedExamIds.add(exam.id!);
            } else if (exam.id != null) {
              _expandedExamIds.remove(exam.id!);
            }
          });
          if (expanded && exam.id != null) {
            context.read<ExamBloc>().add(LoadSchedules(exam.id!));
          }
        },
        title: Text(
          exam.name,
          style: AppTheme.getFontStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${exam.startDate ?? "TBD"} - ${exam.endDate ?? "TBD"}',
          style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
        ),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withAlpha(20),
          child: const Icon(Icons.school, color: AppTheme.primaryColor),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _showAddScheduleDialog(context, exam, currentSchedules),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(
                        context.tr('add_schedule'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: Colors.blueAccent,
                      ),
                      tooltip: 'Edit Exam Session',
                      onPressed: () => _showEditExamDialog(context, exam),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      tooltip: 'Delete Exam Session',
                      onPressed: () {
                        if (exam.id != null) {
                          context.read<ExamBloc>().add(DeleteExam(exam.id!));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ScheduleTable(exam: exam, schedules: currentSchedules),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddExamDialog(BuildContext context) {
    if (!_ensureFeatureAccess('exams_create', 'Exam Creation & Schedule')) return;

    final nameCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          context.tr('create_exam_session'),
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('exam_name'),
                  hintText: 'e.g. Annual Exam 2026',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: startCtrl,
                labelText: context.tr('start_date'),
              ),
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: endCtrl,
                labelText: context.tr('end_date'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                context.read<ExamBloc>().add(CreateExam(Exam(
                      name: nameCtrl.text,
                      startDate:
                          startCtrl.text.isEmpty ? null : startCtrl.text,
                      endDate: endCtrl.text.isEmpty ? null : endCtrl.text,
                    )));
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEditExamDialog(BuildContext context, Exam exam) {
    if (!_ensureFeatureAccess('exams_create', 'Exam Creation & Schedule')) return;

    final nameCtrl = TextEditingController(text: exam.name);
    final startCtrl = TextEditingController(text: exam.startDate ?? '');
    final endCtrl = TextEditingController(text: exam.endDate ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Edit Exam Session',
          style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('exam_name'),
                  hintText: 'e.g. Annual Exam 2026',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: startCtrl,
                labelText: context.tr('start_date'),
              ),
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: endCtrl,
                labelText: context.tr('end_date'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && exam.id != null) {
                final updatedExam = Exam(
                  id: exam.id,
                  name: nameCtrl.text,
                  startDate: startCtrl.text.isEmpty ? null : startCtrl.text,
                  endDate: endCtrl.text.isEmpty ? null : endCtrl.text,
                  status: exam.status,
                  createdAt: exam.createdAt,
                );
                context.read<ExamBloc>().add(UpdateExam(updatedExam));
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showAddScheduleDialog(BuildContext context, Exam exam, List<ExamSchedule> currentSchedules) {
    if (!_ensureFeatureAccess('exams_create', 'Exam Creation & Schedule')) return;

    showDialog(
      context: context,
      builder: (_) => _AddScheduleDialog(
        exam: exam,
        existingSchedules: currentSchedules,
        parentContext: context,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ADD SCHEDULE DIALOG WIDGET
// ═══════════════════════════════════════════════════════════════════

class _AddScheduleDialog extends StatefulWidget {
  final Exam exam;
  final List<ExamSchedule> existingSchedules;
  final BuildContext parentContext;

  const _AddScheduleDialog({
    required this.exam,
    required this.existingSchedules,
    required this.parentContext,
  });

  @override
  State<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<_AddScheduleDialog> {
  late final TextEditingController _dateCtrl;
  late final TextEditingController _startTimeCtrl;
  late final TextEditingController _endTimeCtrl;
  final _maxMarksCtrl = TextEditingController(text: '100');
  final _passMarksCtrl = TextEditingController(text: '33');

  Map<String, dynamic>? _selectedClass;
  Map<String, dynamic>? _selectedBook;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _departments = [];
  String? _selectedMainDeptId;
  String? _selectedSubDeptId;
  List<Map<String, dynamic>> _booksForClass = [];
  List<Map<String, dynamic>> _rawStudents = [];
  bool _loadingHierarchy = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl = TextEditingController(text: DateFormat('yyyy-MM-dd').format(now));
    _startTimeCtrl = TextEditingController(text: DateFormat('HH:mm').format(now));
    _endTimeCtrl = TextEditingController(text: DateFormat('HH:mm').format(now.add(const Duration(hours: 3))));
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final repo = AcademicRepository(ApiClient());
      final studentRepo = StudentRepository(ApiClient());
      final results = await Future.wait([
        repo.getAcademicHierarchy(),
        studentRepo.getAllStudents(),
        repo.getAllDepartments(),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = List<Map<String, dynamic>>.from(results[0] as List);
        final studentsList = results[1] as List;
        _rawStudents = studentsList.map((s) => s is Map ? Map<String, dynamic>.from(s) : (s as dynamic).toJson() as Map<String, dynamic>).toList();
        _departments = List<Map<String, dynamic>>.from(results[2] as List);
        _loadingHierarchy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHierarchy = false);
    }
  }

  List<Map<String, dynamic>> get _mainDepts =>
      _departments.where((d) => d['parent_id'] == null).toList();

  List<Map<String, dynamic>> get _subDeptsForSelectedMain {
    if (_selectedMainDeptId == null) {
      return _departments.where((d) => d['parent_id'] != null).toList();
    }
    return _departments
        .where((d) => d['parent_id']?.toString() == _selectedMainDeptId)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredClasses {
    return _classes.where((c) {
      final classDeptId = c['department_id']?.toString();
      final classParentDeptId = c['department_parent_id']?.toString();

      if (_selectedSubDeptId != null) {
        return classDeptId == _selectedSubDeptId;
      }
      if (_selectedMainDeptId != null) {
        return classDeptId == _selectedMainDeptId ||
            classParentDeptId == _selectedMainDeptId;
      }
      return true;
    }).toList();
  }

  /// Get all book IDs and names already scheduled for this exam
  Set<String> _getAlreadyScheduledBookIds() {
    final scheduled = <String>{};
    for (final s in widget.existingSchedules) {
      if (s.bookId.trim().isNotEmpty) {
        scheduled.add(s.bookId.trim().toLowerCase());
      }
      if (s.bookName != null && s.bookName!.trim().isNotEmpty) {
        scheduled.add(s.bookName!.trim().toLowerCase());
      }
    }
    return scheduled;
  }

  void _onClassChanged(Map<String, dynamic>? cls) {
    if (cls == null) return;

    final selectedClassName = (cls['name'] ?? '').toString().trim();
    final selectedClassId = (cls['id'] ?? '').toString().trim();

    // 1. Extract ALL books for this class from hierarchy (courses -> books & direct books)
    final rawBooks = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addBook(dynamic b) {
      if (b is! Map) return;
      final bMap = Map<String, dynamic>.from(b);
      final bId = (bMap['id'] ?? bMap['name'] ?? '').toString().trim();
      final bName = (bMap['name'] ?? bMap['title'] ?? '').toString().trim();
      final key = (bId.isNotEmpty ? bId : bName).toLowerCase();
      if (key.isNotEmpty && !seenIds.contains(key)) {
        seenIds.add(key);
        rawBooks.add(bMap);
      }
    }

    final courses = cls['courses'] as List? ?? [];
    for (final crs in courses) {
      if (crs is Map) {
        final books = crs['books'] as List? ?? [];
        for (final b in books) {
          addBook(b);
        }
      }
    }
    final directBooks = cls['books'] as List? ?? [];
    for (final b in directBooks) {
      addBook(b);
    }

    // 2. Find student categories and assigned books for students in this class
    final studentCategories = <String>{};
    final studentAssignedBookIdentifiers = <String>{};
    bool hasStudentsInClass = false;

    for (final st in _rawStudents) {
      final stClassId = (st['class_id'] ?? st['class']?['id'] ?? '').toString().trim();
      final stClassName = (st['class_name'] ?? st['class']?['name'] ?? st['className'] ?? '').toString().trim();

      final matchesClass = (selectedClassId.isNotEmpty && stClassId.toLowerCase() == selectedClassId.toLowerCase()) ||
          (selectedClassName.isNotEmpty && stClassName.toLowerCase() == selectedClassName.toLowerCase()) ||
          (selectedClassName.isNotEmpty && stClassName.contains(selectedClassName));

      if (matchesClass) {
        hasStudentsInClass = true;
        final cat = (st['category'] ?? '').toString().trim();
        if (cat.isNotEmpty) {
          studentCategories.add(cat.toLowerCase());
        }

        final booksList = st['assigned_books'] ?? st['books'] ?? st['assigned_courses'] ?? st['courses'] ?? st['subjects'];
        if (booksList is List) {
          for (final b in booksList) {
            if (b is Map) {
              final id = (b['id'] ?? b['book_id'] ?? b['bookId'] ?? '').toString().trim().toLowerCase();
              final name = (b['name'] ?? b['title'] ?? b['book_name'] ?? '').toString().trim().toLowerCase();
              if (id.isNotEmpty) studentAssignedBookIdentifiers.add(id);
              if (name.isNotEmpty) studentAssignedBookIdentifiers.add(name);
            } else {
              final str = b.toString().trim().toLowerCase();
              if (str.isNotEmpty) studentAssignedBookIdentifiers.add(str);
            }
          }
        }
      }
    }

    // 3. Filter books: Only include books assigned to students of this class
    List<Map<String, dynamic>> classAssignedBooks;
    if (hasStudentsInClass && (studentCategories.isNotEmpty || studentAssignedBookIdentifiers.isNotEmpty)) {
      classAssignedBooks = rawBooks.where((b) {
        final bId = (b['id'] ?? '').toString().trim().toLowerCase();
        final bName = (b['name'] ?? b['title'] ?? '').toString().trim().toLowerCase();
        final bCat = (b['category'] ?? '').toString().trim().toLowerCase();

        // If book has no category, it applies to all students of the class
        if (bCat.isEmpty) return true;

        // If book category matches any student's category in this class
        if (studentCategories.contains(bCat)) return true;

        // If explicitly assigned in student's books list
        if ((bId.isNotEmpty && studentAssignedBookIdentifiers.contains(bId)) ||
            (bName.isNotEmpty && studentAssignedBookIdentifiers.contains(bName))) {
          return true;
        }

        return false;
      }).toList();
    } else {
      // If no specific student category/assignment filter matched, show all class books
      classAssignedBooks = rawBooks;
    }

    // 4. Exclude books that ALREADY have an exam schedule in this exam session
    final scheduledIdentifiers = _getAlreadyScheduledBookIds();

    final availableBooks = classAssignedBooks.where((b) {
      final bId = (b['id'] ?? '').toString().trim().toLowerCase();
      final bName = (b['name'] ?? b['title'] ?? '').toString().trim().toLowerCase();

      final isAlreadyScheduled = (bId.isNotEmpty && scheduledIdentifiers.contains(bId)) ||
          (bName.isNotEmpty && scheduledIdentifiers.contains(bName));

      return !isAlreadyScheduled;
    }).toList();

    setState(() {
      _selectedClass = cls;
      _selectedBook = null;
      _booksForClass = availableBooks;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredClasses;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        context.tr('add_exam_schedule'),
        style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: min(520.0, MediaQuery.of(context).size.width - 48),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingHierarchy)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                )
              else ...[
                // Department & Subdepartment Filter Row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _selectedMainDeptId,
                        decoration: InputDecoration(
                          labelText: 'Main Department',
                          prefixIcon: const Icon(Icons.business_center_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Departments', style: TextStyle(fontSize: 12)),
                          ),
                          ..._mainDepts.map((d) => DropdownMenuItem<String?>(
                                value: d['id']?.toString(),
                                child: Text(d['name']?.toString() ?? 'Dept', style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _selectedMainDeptId = v;
                            _selectedSubDeptId = null;
                            _selectedClass = null;
                            _selectedBook = null;
                            _booksForClass = [];
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _selectedSubDeptId,
                        decoration: InputDecoration(
                          labelText: 'Sub-Department',
                          prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Sub-Depts', style: TextStyle(fontSize: 12)),
                          ),
                          ..._subDeptsForSelectedMain.map((d) => DropdownMenuItem<String?>(
                                value: d['id']?.toString(),
                                child: Text(d['name']?.toString() ?? 'Sub-Dept', style: const TextStyle(fontSize: 12)),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _selectedSubDeptId = v;
                            _selectedClass = null;
                            _selectedBook = null;
                            _booksForClass = [];
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Class Dropdown with Department Badge
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: filtered.contains(_selectedClass) ? _selectedClass : null,
                  decoration: InputDecoration(
                    labelText: context.tr('select_class'),
                    prefixIcon: const Icon(Icons.class_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: filtered.map((c) {
                    final cName = c['name']?.toString() ?? 'Class';
                    final deptName = c['department_name']?.toString();
                    final parentDept = c['parent_department_name']?.toString();
                    String badge = '';
                    if (parentDept != null && parentDept.isNotEmpty && deptName != null && deptName.isNotEmpty) {
                      badge = ' ($parentDept • $deptName)';
                    } else if (deptName != null && deptName.isNotEmpty) {
                      badge = ' ($deptName)';
                    }

                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        '$cName$badge',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: _onClassChanged,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Map<String, dynamic>>(
                  key: ValueKey('book_${_selectedClass?['id']}'),
                  value: _selectedBook,
                  decoration: InputDecoration(
                    labelText: context.tr('select_book'),
                    prefixIcon: const Icon(Icons.menu_book_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: _booksForClass
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(b['name']?.toString() ?? 'Book'),
                          ))
                      .toList(),
                  onChanged: (b) => setState(() => _selectedBook = b),
                  hint: Text(_booksForClass.isEmpty
                      ? (_selectedClass != null ? 'No books available' : 'Select class first')
                      : context.tr('select_book')),
                ),
              ],
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: _dateCtrl,
                labelText: 'Schedule Date',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DribbbleTimePickerField(
                      controller: _startTimeCtrl,
                      labelText: 'Start Time',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DribbbleTimePickerField(
                      controller: _endTimeCtrl,
                      labelText: 'End Time',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxMarksCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max Marks',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _passMarksCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Pass Marks',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedClass != null &&
                _selectedBook != null &&
                widget.exam.id != null) {
              final schedule = ExamSchedule(
                examId: widget.exam.id!,
                classId: _selectedClass!['id']?.toString() ?? '',
                className: _selectedClass!['name']?.toString() ?? '',
                bookId: _selectedBook!['id']?.toString() ?? '',
                bookName: _selectedBook!['name']?.toString() ?? '',
                examDate: _dateCtrl.text.isEmpty ? null : _dateCtrl.text,
                startTime: _startTimeCtrl.text,
                endTime: _endTimeCtrl.text,
                maxMarks: int.tryParse(_maxMarksCtrl.text) ?? 100,
                passingMarks: int.tryParse(_passMarksCtrl.text) ?? 33,
                departmentId: _selectedClass!['department_id']?.toString(),
                departmentName: _selectedClass!['department_name']?.toString(),
                parentDepartmentName: _selectedClass!['parent_department_name']?.toString(),
              );
              widget.parentContext
                  .read<ExamBloc>()
                  .add(CreateExamSchedule(schedule));
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Schedule'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EDIT SCHEDULE DIALOG WIDGET
// ═══════════════════════════════════════════════════════════════════

class _EditScheduleDialog extends StatefulWidget {
  final ExamSchedule schedule;
  final BuildContext parentContext;

  const _EditScheduleDialog({
    required this.schedule,
    required this.parentContext,
  });

  @override
  State<_EditScheduleDialog> createState() => _EditScheduleDialogState();
}

class _EditScheduleDialogState extends State<_EditScheduleDialog> {
  late final TextEditingController _dateCtrl;
  late final TextEditingController _startTimeCtrl;
  late final TextEditingController _endTimeCtrl;
  late final TextEditingController _maxMarksCtrl;
  late final TextEditingController _passMarksCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl = TextEditingController(text: widget.schedule.examDate ?? DateFormat('yyyy-MM-dd').format(now));
    _startTimeCtrl = TextEditingController(text: widget.schedule.startTime ?? DateFormat('HH:mm').format(now));
    _endTimeCtrl = TextEditingController(text: widget.schedule.endTime ?? DateFormat('HH:mm').format(now.add(const Duration(hours: 3))));
    _maxMarksCtrl = TextEditingController(text: '${widget.schedule.maxMarks}');
    _passMarksCtrl = TextEditingController(text: '${widget.schedule.passingMarks ?? 33}');
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _startTimeCtrl.dispose();
    _endTimeCtrl.dispose();
    _maxMarksCtrl.dispose();
    _passMarksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Edit Exam Schedule',
        style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      readOnly: true,
                      controller: TextEditingController(text: widget.schedule.className ?? widget.schedule.classId),
                      decoration: InputDecoration(
                        labelText: context.tr('select_class'),
                        prefixIcon: const Icon(Icons.class_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      readOnly: true,
                      controller: TextEditingController(text: widget.schedule.bookName ?? widget.schedule.bookId),
                      decoration: InputDecoration(
                        labelText: context.tr('select_book'),
                        prefixIcon: const Icon(Icons.menu_book_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DribbbleDatePickerField(
                controller: _dateCtrl,
                labelText: 'Schedule Date',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DribbbleTimePickerField(
                      controller: _startTimeCtrl,
                      labelText: 'Start Time',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DribbbleTimePickerField(
                      controller: _endTimeCtrl,
                      labelText: 'End Time',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _maxMarksCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max Marks',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _passMarksCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Pass Marks',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (widget.schedule.id != null) {
              final updated = ExamSchedule(
                id: widget.schedule.id,
                examId: widget.schedule.examId,
                classId: widget.schedule.classId,
                className: widget.schedule.className,
                bookId: widget.schedule.bookId,
                bookName: widget.schedule.bookName,
                examDate: _dateCtrl.text.isEmpty ? null : _dateCtrl.text,
                startTime: _startTimeCtrl.text,
                endTime: _endTimeCtrl.text,
                maxMarks: int.tryParse(_maxMarksCtrl.text) ?? 100,
                passingMarks: int.tryParse(_passMarksCtrl.text) ?? 33,
                studentCount: widget.schedule.studentCount,
              );
              widget.parentContext
                  .read<ExamBloc>()
                  .add(UpdateExamSchedule(updated));
              Navigator.pop(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Changes'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SCHEDULE TABLE WIDGET
// ═══════════════════════════════════════════════════════════════════

class _ScheduleTable extends StatefulWidget {
  final Exam exam;
  final List<ExamSchedule> schedules;

  const _ScheduleTable({required this.exam, required this.schedules});

  @override
  State<_ScheduleTable> createState() => _ScheduleTableState();
}

class _ScheduleTableState extends State<_ScheduleTable> {
  List<Map<String, dynamic>> _rawStudents = [];
  List<Map<String, dynamic>> _academicHierarchy = [];
  bool _isLoadingStudents = false;

  void _showEditScheduleDialog(BuildContext context, ExamSchedule schedule) {
    showDialog(
      context: context,
      builder: (_) => _EditScheduleDialog(
        schedule: schedule,
        parentContext: context,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchLive();
  }

  @override
  void didUpdateWidget(covariant _ScheduleTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch when schedules change
    if (oldWidget.schedules.length != widget.schedules.length) {
      _fetchLive();
    }
  }

  /// Fetch all students and academic hierarchy from backend for live quantity resolution
  Future<void> _fetchLive() async {
    if (_isLoadingStudents) return;
    setState(() => _isLoadingStudents = true);
    try {
      final studentRepo = StudentRepository(ApiClient());
      final academicRepo = AcademicRepository(ApiClient());

      final results = await Future.wait([
        studentRepo.getAllStudents(),
        academicRepo.getAcademicHierarchy(),
      ]);

      if (mounted) {
        setState(() {
          final studentsList = results[0] as List;
          _rawStudents = studentsList.map((s) => s is Map ? Map<String, dynamic>.from(s) : (s as dynamic).toJson() as Map<String, dynamic>).toList();
          _academicHierarchy = List<Map<String, dynamic>>.from(results[1] as List);
          _isLoadingStudents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStudents = false);
    }
  }

  /// Resolve student qty for a schedule by matching book assignments, class, and category
  int _resolveAssignedStudentQty(ExamSchedule s) {
    final schedClass = (s.className ?? s.classId).trim();
    final schedBook = (s.bookName ?? s.bookId).trim();
    final schedBookId = s.bookId.trim();

    String norm(String txt) {
      return txt
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي')
          .replaceAll('ذ', 'د')
          .replaceAll('ز', 'ر')
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
    }

    final normClass = norm(schedClass);
    final normBook = norm(schedBook);
    final normBookId = norm(schedBookId);

    // 1. Find book category from academic hierarchy
    String? bookCategory;
    for (final cls in _academicHierarchy) {
      final cName = norm((cls['name'] ?? cls['id'] ?? '').toString());
      if (cName.isNotEmpty && (cName == normClass || normClass.contains(cName) || cName.contains(normClass))) {
        final courses = cls['courses'] as List? ?? [];
        for (final crs in courses) {
          if (crs is Map) {
            final books = crs['books'] as List? ?? [];
            for (final b in books) {
              if (b is Map) {
                final bId = norm((b['id'] ?? '').toString());
                final bName = norm((b['name'] ?? b['title'] ?? '').toString());
                if ((bId.isNotEmpty && bId == normBookId) ||
                    (bName.isNotEmpty && (bName == normBook || normBook.contains(bName) || bName.contains(normBook)))) {
                  final cat = (b['category'] ?? '').toString().trim().toLowerCase();
                  if (cat.isNotEmpty) {
                    bookCategory = cat;
                  }
                  break;
                }
              }
            }
          }
        }
      }
    }

    // 2. Count matching students in class studying this book
    if (_rawStudents.isNotEmpty) {
      int count = 0;
      int classTotalStudents = 0;

      for (final st in _rawStudents) {
        final stClassId = norm((st['class_id'] ?? st['class']?['id'] ?? '').toString());
        final stClassName = norm((st['class_name'] ?? st['class']?['name'] ?? st['className'] ?? '').toString());

        final isClassMatch = (stClassId.isNotEmpty && (stClassId == normClass || normClass.contains(stClassId) || stClassId.contains(normClass))) ||
            (stClassName.isNotEmpty && (stClassName == normClass || normClass.contains(stClassName) || stClassName.contains(normClass)));

        if (!isClassMatch) continue;
        classTotalStudents++;

        // Check explicit assigned_books list on student object if present
        final booksList = st['assigned_books'] ?? st['books'] ?? st['assigned_courses'] ?? st['courses'] ?? st['subjects'];
        if (booksList is List && booksList.isNotEmpty) {
          bool studentHasBook = booksList.any((b) {
            if (b is Map) {
              final id = norm((b['id'] ?? b['book_id'] ?? b['bookId'] ?? '').toString());
              final name = norm((b['name'] ?? b['title'] ?? b['book_name'] ?? '').toString());
              return (id.isNotEmpty && id == normBookId) ||
                     (name.isNotEmpty && (name == normBook || normBook.contains(name) || name.contains(normBook)));
            }
            final str = norm(b.toString());
            return str == normBookId || str == normBook || normBook.contains(str) || str.contains(normBook);
          });
          if (studentHasBook) count++;
        } else {
          // Check student category vs book category
          final stCategory = (st['category'] ?? '').toString().trim().toLowerCase();
          if (bookCategory != null && bookCategory.isNotEmpty) {
            if (stCategory.isEmpty || stCategory == bookCategory) {
              count++;
            }
          } else {
            // Book has no category -> applies to all students in class
            count++;
          }
        }
      }

      if (classTotalStudents > 0) {
        return count;
      }
    }

    if (s.studentCount != null && s.studentCount! > 0) {
      return s.studentCount!;
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final filteredSchedules = widget.schedules.where((s) {
      if (widget.exam.id == null) return true;
      return s.examId == widget.exam.id;
    }).toList();

    if (filteredSchedules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No schedules added yet for this exam session.',
          style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
          children: [
            TableRow(
              decoration: BoxDecoration(color: AppTheme.primaryColor.withAlpha(20)),
              children: [
                _buildTableHeader('Class'),
                _buildTableHeader('Book / Subject'),
                _buildTableHeader('Date'),
                _buildTableHeader('Time'),
                _buildTableHeader('Max Marks'),
                _buildTableHeader('Student Qty'),
                _buildTableHeader('Action'),
              ],
            ),
            ...filteredSchedules.map((s) {
              final qty = _resolveAssignedStudentQty(s);
              return TableRow(
                children: [
                  _buildClassCell(s),
                  _buildTableCell(s.bookName ?? s.bookId),
                  _buildTableCell(s.examDate ?? '-'),
                  _buildTableCell('${s.startTime ?? ""} - ${s.endTime ?? ""}'),
                  _buildTableCell('${s.maxMarks}'),
                  _buildTableCell(_isLoadingStudents ? '...' : '$qty'),
                  TableCell(
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined,
                                size: 18, color: Colors.blueAccent),
                            tooltip: 'Edit Schedule',
                            onPressed: () => _showEditScheduleDialog(context, s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18, color: Colors.redAccent),
                            tooltip: 'Delete Schedule',
                            onPressed: () {
                              if (widget.exam.id != null && s.id != null) {
                                context
                                    .read<ExamBloc>()
                                    .add(DeleteExamSchedule(s.id!, widget.exam.id!));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
        // Refresh button for live qty
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _fetchLive,
            icon: Icon(
              _isLoadingStudents ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
              size: 14,
              color: AppTheme.primaryColor,
            ),
            label: Text(
              _isLoadingStudents ? 'Refreshing...' : 'Refresh Student Qty',
              style: AppTheme.getFontStyle(fontSize: 11, color: AppTheme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: AppTheme.getFontStyle(
            fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildClassCell(ExamSchedule s) {
    final cName = s.className ?? s.classId;
    final parentDept = s.parentDepartmentName;
    final deptName = s.departmentName;
    String? badge;
    if (parentDept != null && parentDept.isNotEmpty && deptName != null && deptName.isNotEmpty) {
      badge = '$parentDept • $deptName';
    } else if (deptName != null && deptName.isNotEmpty) {
      badge = deptName;
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cName,
            style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          if (badge != null) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withAlpha(15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1565C0).withAlpha(60), width: 0.6),
              ),
              child: Text(
                badge,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: AppTheme.getFontStyle(fontSize: 12),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 2: EXAM HALLS
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  TAB 2: EXAM HALLS (ENHANCED MODERN DESIGN)
// ═══════════════════════════════════════════════════════════════════

class _HallsTab extends StatelessWidget {
  final List<ExamHall> halls;

  const _HallsTab({required this.halls});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final totalSeats = halls.fold<int>(0, (sum, h) => sum + h.totalCapacity);
    final avgSeats = halls.isNotEmpty ? (totalSeats / halls.length).round() : 0;
    final maxCapacityHall = halls.isNotEmpty
        ? halls.reduce((a, b) => a.totalCapacity > b.totalCapacity ? a : b)
        : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // ── Top Metrics Overview Bar ──
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 700;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildStatCard(
                  context,
                  title: 'Total Exam Halls',
                  value: '${halls.length}',
                  subtitle: 'Active Hall Locations',
                  icon: Icons.domain_rounded,
                  accentColor: const Color(0xFF4F46E5),
                  isNarrow: isNarrow,
                ),
                _buildStatCard(
                  context,
                  title: 'Total Seating Capacity',
                  value: '$totalSeats',
                  subtitle: 'Available Exam Seats',
                  icon: Icons.chair_alt_rounded,
                  accentColor: const Color(0xFF10B981),
                  isNarrow: isNarrow,
                ),
                _buildStatCard(
                  context,
                  title: 'Average Hall Size',
                  value: '$avgSeats',
                  subtitle: 'Seats per Hall',
                  icon: Icons.bar_chart_rounded,
                  accentColor: const Color(0xFFF59E0B),
                  isNarrow: isNarrow,
                ),
                _buildStatCard(
                  context,
                  title: 'Largest Hall',
                  value: maxCapacityHall != null ? '${maxCapacityHall.totalCapacity}' : '0',
                  subtitle: maxCapacityHall?.name ?? 'None',
                  icon: Icons.star_rounded,
                  accentColor: const Color(0xFF8B5CF6),
                  isNarrow: isNarrow,
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 28),

        // ── Header Action Bar ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exam Halls & Seating Infrastructure',
                  style: AppTheme.getFontStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure physical hall dimensions, row/column matrices, and seating limits',
                  style: AppTheme.getFontStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () => _showAddEditHallDialog(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(context.tr('add_hall')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (halls.isEmpty)
          const _EmptyState(
            icon: Icons.business_rounded,
            label: 'No Exam Halls Configured',
            subtitle: 'Add hall rooms with custom rows and columns to generate seating plans.',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              double cardWidth = 340;
              if (constraints.maxWidth > 1100) {
                cardWidth = (constraints.maxWidth - 48) / 3;
              } else if (constraints.maxWidth > 720) {
                cardWidth = (constraints.maxWidth - 32) / 2;
              } else {
                cardWidth = constraints.maxWidth;
              }

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: halls.map((h) => SizedBox(
                  width: cardWidth,
                  child: _buildHallCard(context, h),
                )).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isNarrow,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: isNarrow ? 160 : 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.getFontStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: AppTheme.getFontStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHallCard(BuildContext context, ExamHall hall) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E32) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card Header with Icon, Title, Active Badge & Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor,
                        AppTheme.primaryColor.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hall.name,
                        style: AppTheme.getFontStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'ACTIVE HALL',
                          style: AppTheme.getFontStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.successColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Visual Grid Inspector',
                  icon: Icon(Icons.grid_view_rounded, size: 20, color: AppTheme.primaryColor),
                  onPressed: () => _showHallPreviewDialog(context, hall),
                ),
                IconButton(
                  tooltip: 'Edit Hall',
                  icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueAccent),
                  onPressed: () => _showAddEditHallDialog(context, hall: hall),
                ),
                IconButton(
                  tooltip: 'Delete Hall',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                  onPressed: () => _confirmDeleteHall(context, hall),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Card Middle: Spec Badges
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildSpecChip(
                      context,
                      icon: Icons.table_rows_rounded,
                      label: '${hall.totalRows} Rows',
                      color: const Color(0xFF3B82F6),
                    ),
                    const SizedBox(width: 8),
                    _buildSpecChip(
                      context,
                      icon: Icons.view_column_rounded,
                      label: '${hall.totalColumns} Cols',
                      color: const Color(0xFF06B6D4),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_seat_rounded, size: 14, color: AppTheme.primaryColor),
                          const SizedBox(width: 5),
                          Text(
                            '${hall.totalCapacity} Seats',
                            style: AppTheme.getFontStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Miniature Seat Matrix Blueprint Preview
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF14142B) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      // Stage indicator
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'STAGE / BLACKBOARD',
                          style: AppTheme.getFontStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          ),
                        ),
                      ),

                      // Grid seats preview (capped at 5x8 max for preview)
                      _buildMiniGridPreview(hall.totalRows, hall.totalColumns, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Card Action Footer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              onPressed: () => _showHallPreviewDialog(context, hall),
              icon: const Icon(Icons.aspect_ratio_rounded, size: 16),
              label: const Text('View Full Grid Inspector'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(color: AppTheme.primaryColor.withOpacity(0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecChip(BuildContext context, {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTheme.getFontStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniGridPreview(int rows, int cols, bool isDark) {
    final previewRows = rows.clamp(1, 5);
    final previewCols = cols.clamp(1, 8);

    return Column(
      children: List.generate(previewRows, (r) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(previewCols, (c) {
              return Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4), width: 0.5),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  void _confirmDeleteHall(BuildContext parentContext, ExamHall hall) {
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${hall.name}?', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete this exam hall? Any seating plans linked to this hall may be affected.',
          style: AppTheme.getFontStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (hall.id != null) {
                parentContext.read<ExamBloc>().add(DeleteExamHall(hall.id!));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Hall'),
          ),
        ],
      ),
    );
  }

  void _showAddEditHallDialog(BuildContext parentContext, {ExamHall? hall}) {
    final isEdit = hall != null;
    final nameCtrl = TextEditingController(text: hall?.name ?? '');
    final rowsCtrl = TextEditingController(text: '${hall?.totalRows ?? 5}');
    final colsCtrl = TextEditingController(text: '${hall?.totalColumns ?? 6}');

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final r = int.tryParse(rowsCtrl.text) ?? 0;
            final c = int.tryParse(colsCtrl.text) ?? 0;
            final capacity = r * c;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isEdit ? Icons.edit_note_rounded : Icons.add_business_rounded,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEdit ? 'Edit Exam Hall' : 'Add New Exam Hall',
                    style: AppTheme.getFontStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Hall Name',
                        hintText: 'e.g. Main Hall 101',
                        prefixIcon: const Icon(Icons.meeting_room_rounded, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: rowsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Total Rows',
                              prefixIcon: const Icon(Icons.table_rows_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: colsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Total Columns',
                              prefixIcon: const Icon(Icons.view_column_rounded, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Live Capacity Badge Preview
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calculate_rounded, color: AppTheme.primaryColor, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Calculated Capacity:',
                            style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          Text(
                            '$r Rows × $c Cols = $capacity Seats',
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty) {
                      final newHall = ExamHall(
                        id: hall?.id,
                        name: nameCtrl.text.trim(),
                        totalRows: r > 0 ? r : 5,
                        totalColumns: c > 0 ? c : 6,
                        isActive: hall?.isActive ?? true,
                      );

                      if (isEdit) {
                        parentContext.read<ExamBloc>().add(UpdateExamHall(newHall));
                      } else {
                        parentContext.read<ExamBloc>().add(CreateExamHall(newHall));
                      }
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(isEdit ? 'Save Changes' : 'Create Hall'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showHallPreviewDialog(BuildContext context, ExamHall hall) {
    showDialog(
      context: context,
      builder: (ctx) => _HallPreviewDialogContent(hall: hall),
    );
  }
}

class _HallPreviewDialogContent extends StatefulWidget {
  final ExamHall hall;

  const _HallPreviewDialogContent({required this.hall});

  @override
  State<_HallPreviewDialogContent> createState() => _HallPreviewDialogContentState();
}

class _HallPreviewDialogContentState extends State<_HallPreviewDialogContent> {
  late final ScrollController _bodyVerticalController;
  late final ScrollController _bodyHorizontalController;
  late final ScrollController _headerHorizontalController;
  late final ScrollController _sidebarVerticalController;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _bodyVerticalController = ScrollController();
    _bodyHorizontalController = ScrollController();
    _headerHorizontalController = ScrollController();
    _sidebarVerticalController = ScrollController();

    _bodyHorizontalController.addListener(() {
      if (_headerHorizontalController.hasClients &&
          _headerHorizontalController.offset != _bodyHorizontalController.offset) {
        _headerHorizontalController.jumpTo(_bodyHorizontalController.offset);
      }
    });

    _bodyVerticalController.addListener(() {
      if (_sidebarVerticalController.hasClients &&
          _sidebarVerticalController.offset != _bodyVerticalController.offset) {
        _sidebarVerticalController.jumpTo(_bodyVerticalController.offset);
      }
    });
  }

  @override
  void dispose() {
    _bodyVerticalController.dispose();
    _bodyHorizontalController.dispose();
    _headerHorizontalController.dispose();
    _sidebarVerticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hall = widget.hall;
    final totalSeats = hall.totalRows * hall.totalColumns;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dialogWidth = (constraints.maxWidth * 0.94).clamp(780.0, 1350.0);
          final dialogHeight = (constraints.maxHeight * 0.88).clamp(550.0, 850.0);

          return Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Dialog Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.grid_view_rounded, color: AppTheme.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${hall.name} - Interactive Excel-Style Blueprint',
                            style: AppTheme.getFontStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${hall.totalRows} Rows × ${hall.totalColumns} Columns Matrix = $totalSeats Total Seats (#1 to #$totalSeats)',
                            style: AppTheme.getFontStyle(fontSize: 12.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.successColor.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successColor),
                          const SizedBox(width: 6),
                          Text(
                            'Full $totalSeats / $totalSeats Seats',
                            style: AppTheme.getFontStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Board / Stage Header Bar
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF2D2D44), const Color(0xFF1E1E32)]
                          : [Colors.grey.shade300, Colors.grey.shade200],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400, width: 0.5),
                  ),
                  child: Text(
                    'FRONT / BLACKBOARD / EXAMINER DESK',
                    style: AppTheme.getFontStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Excel Controls & Hints Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rows: R1 to R${hall.totalRows}  |  Columns: C1 to C${hall.totalColumns}',
                      style: AppTheme.getFontStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Icon(Icons.pan_tool_rounded, size: 15, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          'Excel Drag Panning Enabled: Hold & Drag mouse to scroll in 2D | Wheel for Up/Down',
                          style: AppTheme.getFontStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 2D Excel Sheet Table with Frozen Freeze Panes (Header Row & Sidebar Column)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF14142B) : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        children: [
                          // ── TOP FROZEN ROW: Corner Box + Column Headers (C1..C23) ──
                          Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E34) : Colors.grey.shade200,
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Top-Left Frozen Corner Box (R/C)
                                Container(
                                  width: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withOpacity(0.12),
                                    border: Border(
                                      right: BorderSide(
                                        color: isDark ? Colors.white12 : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    'R / C',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),

                                // Top Column Headers (Horizontally synced with body)
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _headerHorizontalController,
                                    scrollDirection: Axis.horizontal,
                                    physics: const NeverScrollableScrollPhysics(),
                                    child: Row(
                                      children: List.generate(hall.totalColumns, (c) {
                                        return Container(
                                          width: 46,
                                          height: 28,
                                          margin: const EdgeInsets.symmetric(horizontal: 2.0),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'C${c + 1}',
                                            style: AppTheme.getFontStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── MAIN BODY: Frozen Left Row Headers + Interactive 2D Seat Grid Matrix ──
                          Expanded(
                            child: Row(
                              children: [
                                // Left Frozen Row Headers Column (R1..R24) (Vertically synced with body)
                                Container(
                                  width: 48,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E1E34) : Colors.grey.shade100,
                                    border: Border(
                                      right: BorderSide(
                                        color: isDark ? Colors.white12 : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  child: SingleChildScrollView(
                                    controller: _sidebarVerticalController,
                                    scrollDirection: Axis.vertical,
                                    physics: const NeverScrollableScrollPhysics(),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Column(
                                        children: List.generate(hall.totalRows, (r) {
                                          return Container(
                                            width: 42,
                                            height: 42,
                                            margin: const EdgeInsets.symmetric(vertical: 2.5),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white12 : Colors.grey.shade200,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'R${r + 1}',
                                              style: AppTheme.getFontStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),

                                // Interactive Seat Matrix (Supports Mouse Drag Panning + Wheel Scroll!)
                                Expanded(
                                  child: Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        if (HardwareKeyboard.instance.isShiftPressed) {
                                          if (_bodyHorizontalController.hasClients) {
                                            final targetX = (_bodyHorizontalController.offset + event.scrollDelta.dy)
                                                .clamp(0.0, _bodyHorizontalController.position.maxScrollExtent);
                                            _bodyHorizontalController.jumpTo(targetX);
                                          }
                                        } else {
                                          if (_bodyVerticalController.hasClients) {
                                            final targetY = (_bodyVerticalController.offset + event.scrollDelta.dy)
                                                .clamp(0.0, _bodyVerticalController.position.maxScrollExtent);
                                            _bodyVerticalController.jumpTo(targetY);
                                          }
                                          if (event.scrollDelta.dx != 0 && _bodyHorizontalController.hasClients) {
                                            final targetX = (_bodyHorizontalController.offset + event.scrollDelta.dx)
                                                .clamp(0.0, _bodyHorizontalController.position.maxScrollExtent);
                                            _bodyHorizontalController.jumpTo(targetX);
                                          }
                                        }
                                      }
                                    },
                                    child: GestureDetector(
                                      onPanStart: (_) => setState(() => _isDragging = true),
                                      onPanEnd: (_) => setState(() => _isDragging = false),
                                      onPanCancel: () => setState(() => _isDragging = false),
                                      onPanUpdate: (details) {
                                        if (_bodyHorizontalController.hasClients) {
                                          final newX = (_bodyHorizontalController.offset - details.delta.dx)
                                              .clamp(0.0, _bodyHorizontalController.position.maxScrollExtent);
                                          _bodyHorizontalController.jumpTo(newX);
                                        }
                                        if (_bodyVerticalController.hasClients) {
                                          final newY = (_bodyVerticalController.offset - details.delta.dy)
                                              .clamp(0.0, _bodyVerticalController.position.maxScrollExtent);
                                          _bodyVerticalController.jumpTo(newY);
                                        }
                                      },
                                      child: MouseRegion(
                                        cursor: _isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                                        child: Scrollbar(
                                          controller: _bodyVerticalController,
                                          thumbVisibility: true,
                                          trackVisibility: true,
                                          child: SingleChildScrollView(
                                            controller: _bodyVerticalController,
                                            scrollDirection: Axis.vertical,
                                            child: Scrollbar(
                                              controller: _bodyHorizontalController,
                                              thumbVisibility: true,
                                              trackVisibility: true,
                                              child: SingleChildScrollView(
                                                controller: _bodyHorizontalController,
                                                scrollDirection: Axis.horizontal,
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: List.generate(hall.totalRows, (r) {
                                                      return Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: List.generate(hall.totalColumns, (c) {
                                                            final seatNum = (r * hall.totalColumns) + (c + 1);

                                                            return Container(
                                                              width: 46,
                                                              height: 42,
                                                              margin: const EdgeInsets.symmetric(horizontal: 2.0),
                                                              decoration: BoxDecoration(
                                                                color: AppTheme.primaryColor.withOpacity(0.08),
                                                                borderRadius: BorderRadius.circular(6),
                                                                border: Border.all(
                                                                  color: AppTheme.primaryColor.withOpacity(0.3),
                                                                  width: 1.0,
                                                                ),
                                                              ),
                                                              child: Column(
                                                                mainAxisAlignment: MainAxisAlignment.center,
                                                                children: [
                                                                  Icon(
                                                                    Icons.event_seat_rounded,
                                                                    size: 13,
                                                                    color: AppTheme.primaryColor,
                                                                  ),
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    '#$seatNum',
                                                                    style: AppTheme.getFontStyle(
                                                                      fontSize: 9.5,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: AppTheme.primaryColor,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                        ),
                                                      );
                                                    }),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // Footer Legend
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'All $totalSeats seats (from #1 to #$totalSeats) rendered in Excel-style 2D Panning Matrix (${hall.totalRows} Rows × ${hall.totalColumns} Columns).',
                      style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Close Preview'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 3: SEATING GENERATOR
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  TAB 3: SEATING GENERATOR (CLASS-WISE MULTI-HALL ENGINE)
// ═══════════════════════════════════════════════════════════════════

class _BookSeatingSelectionItem {
  final ExamSchedule schedule;
  final String className;
  final String classId;
  final String bookName;
  final String bookId;
  final int totalStudents;
  final List<Map<String, dynamic>> allClassStudents;
  final List<Map<String, dynamic>> unallocatedStudents;
  bool isSelected;
  bool autoDisabled;
  String? conflictReason;
  TextEditingController quantityCtrl;

  _BookSeatingSelectionItem({
    required this.schedule,
    required this.className,
    required this.classId,
    required this.bookName,
    required this.bookId,
    required this.totalStudents,
    required this.allClassStudents,
    required this.unallocatedStudents,
    this.isSelected = true,
    this.autoDisabled = false,
    this.conflictReason,
    required int initialQuantity,
  }) : quantityCtrl = TextEditingController(text: '$initialQuantity');

  int get alreadySeatedCount => totalStudents - unallocatedStudents.length;
  int get remainingUnallocatedCount => unallocatedStudents.length;
  bool get isFullyAllocated => remainingUnallocatedCount == 0;
  int get requestedQuantity => int.tryParse(quantityCtrl.text) ?? 0;

  void setQuantity(int val) {
    final clamped = val.clamp(0, remainingUnallocatedCount);
    quantityCtrl.text = '$clamped';
  }
}

class _SeatingTab extends StatefulWidget {
  final List<Exam> exams;
  final List<ExamHall> halls;
  final SeatingResult? result;
  final ExamHall? resultHall;

  const _SeatingTab({
    required this.exams,
    required this.halls,
    this.result,
    this.resultHall,
  });

  @override
  State<_SeatingTab> createState() => _SeatingTabState();
}

class _SeatingTabState extends State<_SeatingTab>
    with AutomaticKeepAliveClientMixin {
  int? _selectedExamId;
  int? _selectedHallId;
  final _dateCtrl =
      TextEditingController(text: DateFormat('dd/MM/yyyy').format(DateTime.now()));
  final _timeCtrl = TextEditingController(
      text: DateFormat('hh:mm a').format(DateTime.now()));

  bool _isLoadingBooks = false;
  List<_BookSeatingSelectionItem> _bookItems = [];
  Map<int, List<SeatingArrangement>> _savedHallSeatingMap = {};
  List<Map<String, String>> _availableExamSessions = [];
  final Set<String> _userUnselectedBookKeys = {};
  bool _isGenerating = false;
  bool _isUpdatingFromListener = false;

  SeatingResult? _currentSeatingResult;
  ExamHall? _currentSeatingHall;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<ExamBloc>();
    _selectedExamId = bloc.lastSeatingExamId;
    _selectedHallId = bloc.lastGeneratedHall?.id;
    _currentSeatingResult = widget.result ?? bloc.lastGeneratedSeating;
    _currentSeatingHall = widget.resultHall ?? bloc.lastGeneratedHall;

    _dateCtrl.addListener(_onFilterChanged);
    _timeCtrl.addListener(_onFilterChanged);

    _loadBookSelectionsAndSavedHalls();
  }

  @override
  void didUpdateWidget(covariant _SeatingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.result != null) {
      _currentSeatingResult = widget.result;
    }
    if (widget.resultHall != null) {
      _currentSeatingHall = widget.resultHall;
    }
  }

  @override
  void dispose() {
    _dateCtrl.removeListener(_onFilterChanged);
    _timeCtrl.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    if (_isUpdatingFromListener) return;
    _loadBookSelectionsAndSavedHalls();
  }

  String _formatToDdMmYyyy(String dateStr) {
    final trimmed = dateStr.trim();
    if (trimmed.isEmpty) return '';
    try {
      if (trimmed.contains('-')) {
        final parts = trimmed.split('-');
        if (parts.length == 3 && parts[0].length == 4) {
          return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
        }
      }
    } catch (_) {}
    return trimmed;
  }

  String _normalizeDateStr(String d) {
    final trimmed = d.trim();
    if (trimmed.isEmpty) return '';
    try {
      if (trimmed.contains('/')) {
        final parts = trimmed.split('/');
        if (parts.length == 3) {
          final day = parts[0].padLeft(2, '0');
          final month = parts[1].padLeft(2, '0');
          final year = parts[2];
          return '$year-$month-$day';
        }
      } else if (trimmed.contains('-')) {
        final parts = trimmed.split('-');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
          } else {
            return '${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
          }
        }
      }
    } catch (_) {}
    return trimmed.toLowerCase();
  }

  String _formatTo12HourAmPm(String timeStr) {
    final trimmed = timeStr.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.toLowerCase().contains('am') || trimmed.toLowerCase().contains('pm')) {
      return trimmed.toUpperCase();
    }
    try {
      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        int h = int.parse(parts[0]);
        int m = int.parse(parts[1]);
        final period = h >= 12 ? 'PM' : 'AM';
        int h12 = h % 12 == 0 ? 12 : h % 12;
        return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
      }
    } catch (_) {}
    return trimmed;
  }

  String _normalizeTimeForComparison(String timeStr) {
    final trimmed = timeStr.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    try {
      final isPm = trimmed.contains('pm');
      final isAm = trimmed.contains('am');
      final cleaned = trimmed.replaceAll('am', '').replaceAll('pm', '').trim();
      final parts = cleaned.split(':');
      if (parts.length >= 2) {
        int h = int.tryParse(parts[0]) ?? 0;
        int m = int.tryParse(parts[1]) ?? 0;
        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return trimmed;
  }

  String _normalizeUrdu(String text) {
    return text
        .replaceAll('ں', 'ن')
        .replaceAll('آ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('ى', 'ی')
        .replaceAll('ئ', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ہ', 'ه')
        .replaceAll('\u064B', '')
        .replaceAll('\u064C', '')
        .replaceAll('\u064D', '')
        .replaceAll('\u064E', '')
        .replaceAll('\u064F', '')
        .replaceAll('\u0650', '')
        .replaceAll('\u0651', '')
        .replaceAll('\u0652', '')
        .replaceAll(' ', '')
        .trim()
        .toLowerCase();
  }

  bool _studentMatchesScheduleClass(Map<String, dynamic> st, ExamSchedule sched) {
    final sClassId = '${st['class_id'] ?? st['class']?['id'] ?? ''}'.trim().toLowerCase();
    final sClassName = '${st['class_name'] ?? st['class']?['name'] ?? st['className'] ?? ''}'.trim().toLowerCase();
    final schedClassId = (sched.classId).trim().toLowerCase();
    final schedClassName = (sched.className ?? '').trim().toLowerCase();

    if (sClassId.isNotEmpty && (sClassId == schedClassId || sClassId == schedClassName)) return true;
    if (sClassName.isNotEmpty && (sClassName == schedClassName || sClassName == schedClassId)) return true;
    if (sClassId.isEmpty && sClassName.isEmpty) return true;

    final normSClass = _normalizeUrdu(sClassName);
    final normSchedClass = _normalizeUrdu(schedClassName);
    if (normSClass.isNotEmpty && normSchedClass.isNotEmpty &&
        (normSClass == normSchedClass || normSClass.contains(normSchedClass) || normSchedClass.contains(normSClass))) {
      return true;
    }
    return false;
  }

  int _resolveAssignedStudentQty(ExamSchedule s, List<Map<String, dynamic>> rawStudents, List<Map<String, dynamic>> academicHierarchy) {
    final schedClass = (s.className ?? s.classId).trim();
    final schedBook = (s.bookName ?? s.bookId).trim();
    final schedBookId = s.bookId.trim();

    String norm(String txt) {
      return txt
          .replaceAll('أ', 'ا')
          .replaceAll('إ', 'ا')
          .replaceAll('آ', 'ا')
          .replaceAll('ة', 'ه')
          .replaceAll('ى', 'ي')
          .replaceAll('ذ', 'د')
          .replaceAll('ز', 'ر')
          .replaceAll(RegExp(r'\s+'), '')
          .toLowerCase();
    }

    final normClass = norm(schedClass);
    final normBook = norm(schedBook);
    final normBookId = norm(schedBookId);

    // 1. Find book category from academic hierarchy
    String? bookCategory;
    for (final cls in academicHierarchy) {
      final cName = norm((cls['name'] ?? cls['id'] ?? '').toString());
      if (cName.isNotEmpty && (cName == normClass || normClass.contains(cName) || cName.contains(normClass))) {
        final courses = cls['courses'] as List? ?? [];
        for (final crs in courses) {
          if (crs is Map) {
            final books = crs['books'] as List? ?? [];
            for (final b in books) {
              if (b is Map) {
                final bId = norm((b['id'] ?? '').toString());
                final bName = norm((b['name'] ?? b['title'] ?? '').toString());
                if ((bId.isNotEmpty && bId == normBookId) ||
                    (bName.isNotEmpty && (bName == normBook || normBook.contains(bName) || bName.contains(normBook)))) {
                  final cat = (b['category'] ?? '').toString().trim().toLowerCase();
                  if (cat.isNotEmpty) {
                    bookCategory = cat;
                  }
                  break;
                }
              }
            }
          }
        }
      }
    }

    // 2. Count matching students in class studying this book
    if (rawStudents.isNotEmpty) {
      int count = 0;
      int classTotalStudents = 0;

      for (final st in rawStudents) {
        final stClassId = norm((st['class_id'] ?? st['class']?['id'] ?? '').toString());
        final stClassName = norm((st['class_name'] ?? st['class']?['name'] ?? st['className'] ?? '').toString());

        final isClassMatch = (stClassId.isNotEmpty && (stClassId == normClass || normClass.contains(stClassId) || stClassId.contains(normClass))) ||
            (stClassName.isNotEmpty && (stClassName == normClass || normClass.contains(stClassName) || stClassName.contains(normClass)));

        if (!isClassMatch) continue;
        classTotalStudents++;

        // Check explicit assigned_books list on student object if present
        final booksList = st['assigned_books'] ?? st['books'] ?? st['assigned_courses'] ?? st['courses'] ?? st['subjects'];
        if (booksList is List && booksList.isNotEmpty) {
          bool studentHasBook = booksList.any((b) {
            if (b is Map) {
              final id = norm((b['id'] ?? b['book_id'] ?? b['bookId'] ?? '').toString());
              final name = norm((b['name'] ?? b['title'] ?? b['book_name'] ?? '').toString());
              return (id.isNotEmpty && id == normBookId) ||
                     (name.isNotEmpty && (name == normBook || normBook.contains(name) || name.contains(normBook)));
            }
            final str = norm(b.toString());
            return str == normBookId || str == normBook || normBook.contains(str) || str.contains(normBook);
          });
          if (studentHasBook) count++;
        } else {
          // Check student category vs book category
          final stCategory = (st['category'] ?? '').toString().trim().toLowerCase();
          if (bookCategory != null && bookCategory.isNotEmpty) {
            if (stCategory.isEmpty || stCategory == bookCategory) {
              count++;
            }
          } else {
            // Book has no category -> applies to all students in class
            count++;
          }
        }
      }

      if (classTotalStudents > 0) {
        return count;
      }
    }

    if (s.studentCount != null && s.studentCount! > 0) {
      return s.studentCount!;
    }

    return 0;
  }

  Future<void> _loadBookSelectionsAndSavedHalls() async {
    if (_selectedExamId == null) {
      setState(() {
        _bookItems = [];
        _savedHallSeatingMap = {};
      });
      return;
    }
    setState(() => _isLoadingBooks = true);

    try {
      final repo = ExamLocalRepository();
      final studentRepo = StudentRepository(ApiClient());
      final academicRepo = AcademicRepository(ApiClient());

      List<Map<String, dynamic>> sList = [];
      List<Map<String, dynamic>> hierarchy = [];

      try {
        final res = await Future.wait([
          studentRepo.getAllStudents(),
          academicRepo.getAcademicHierarchy(),
        ]);
        final studentsList = res[0] as List;
        sList = studentsList.map((s) => s is Map ? Map<String, dynamic>.from(s) : (s as dynamic).toJson() as Map<String, dynamic>).toList();
        hierarchy = List<Map<String, dynamic>>.from(res[1] as List);
      } catch (e) {
        debugPrint('API load note: $e');
      }

      // Fallback: If API returned empty (offline mode), query local marks and seating history for students
      if (sList.isEmpty && _selectedExamId != null) {
        final marks = await repo.getAllMarksByExam(_selectedExamId!);
        final uniqueStudentMap = <String, Map<String, dynamic>>{};
        for (final m in marks) {
          if (!uniqueStudentMap.containsKey(m.studentId)) {
            uniqueStudentMap[m.studentId] = {
              'id': m.studentId,
              'full_name': m.studentName,
              'registration_number': m.registrationNumber,
              'class_id': m.classId,
              'class_name': m.className,
              'book_id': m.bookId,
              'book_name': m.bookName,
            };
          }
        }

        final savedSeating = await repo.getSeating(_selectedExamId!);
        for (final s in savedSeating) {
          if (!uniqueStudentMap.containsKey(s.studentId)) {
            uniqueStudentMap[s.studentId] = {
              'id': s.studentId,
              'full_name': s.studentName,
              'registration_number': s.registrationNumber,
              'class_id': s.classId,
              'class_name': s.className,
              'book_id': s.bookId,
              'book_name': s.bookName,
            };
          }
        }
        sList = uniqueStudentMap.values.toList();
      }

      final schedules = await repo.getSchedules(_selectedExamId!);

      // Collect all available exam sessions for 1-click chip filtering
      final Set<String> seenSessions = {};
      final List<Map<String, String>> sessionList = [];
      for (final s in schedules) {
        final d = s.examDate ?? '';
        final t = s.startTime ?? '';
        final endT = s.endTime ?? '';
        final key = '$d|$t';
        if (d.isNotEmpty && !seenSessions.contains(key)) {
          seenSessions.add(key);
          sessionList.add({'date': d, 'time': t, 'endTime': endT});
        }
      }

      // Populate initial Date & Time controls only if empty
      if (schedules.isNotEmpty) {
        if (_dateCtrl.text.trim().isEmpty && schedules.first.examDate != null && schedules.first.examDate!.isNotEmpty) {
          _isUpdatingFromListener = true;
          _dateCtrl.text = _formatToDdMmYyyy(schedules.first.examDate!);
          _isUpdatingFromListener = false;
        }
        if (_timeCtrl.text.trim().isEmpty && schedules.first.startTime != null && schedules.first.startTime!.isNotEmpty) {
          _isUpdatingFromListener = true;
          _timeCtrl.text = _formatTo12HourAmPm(schedules.first.startTime!);
          _isUpdatingFromListener = false;
        }
      }

      final dateStr = _dateCtrl.text.trim();
      final dateNorm = _normalizeDateStr(dateStr);
      final timeStr = _timeCtrl.text.trim();
      final timeNorm = _normalizeTimeForComparison(timeStr);

      final sessionSchedules = schedules.where((s) {
        final sDateNorm = _normalizeDateStr(s.examDate ?? '');
        bool dateMatch = dateNorm.isEmpty || sDateNorm == dateNorm || sDateNorm.contains(dateNorm);

        bool timeMatch = timeNorm.isEmpty;
        if (!timeMatch && s.startTime != null) {
          final sStartNorm = _normalizeTimeForComparison(s.startTime!);
          final sEndNorm = _normalizeTimeForComparison(s.endTime ?? '');
          timeMatch = sStartNorm == timeNorm || timeNorm.contains(sStartNorm) || sStartNorm.contains(timeNorm) || (sEndNorm.isNotEmpty && timeNorm.contains(sEndNorm));
        }
        return dateMatch && timeMatch;
      }).toList();

      final activeSchedules = sessionSchedules;

      final savedArrangements = await repo.getSeatingForSession(_selectedExamId!, dateStr, timeStr);
      final seatedStudentIds = savedArrangements.map((a) => a.studentId).toSet();

      final Map<int, List<SeatingArrangement>> savedMap = {};
      for (final a in savedArrangements) {
        savedMap.putIfAbsent(a.hallId, () => []).add(a);
      }

      final List<_BookSeatingSelectionItem> items = [];
      final Map<String, int> classOffsetMap = {};

      for (final sched in activeSchedules) {
        final cKey = sched.classId.trim().toLowerCase();
        final targetTotalQty = _resolveAssignedStudentQty(sched, sList, hierarchy);
        var rawClassStudents = sList.where((st) => _studentMatchesScheduleClass(st, sched)).toList();

        final effectiveQty = (sched.studentCount != null && sched.studentCount! > 0)
            ? sched.studentCount!
            : (targetTotalQty > 0 ? targetTotalQty : rawClassStudents.length);

        List<Map<String, dynamic>> classStudents = [];

        if (rawClassStudents.isNotEmpty) {
          final currentOffset = classOffsetMap[cKey] ?? 0;
          if (effectiveQty >= rawClassStudents.length && rawClassStudents.length > 0) {
            classStudents = List.from(rawClassStudents);
          } else if (effectiveQty > 0) {
            if (currentOffset < rawClassStudents.length) {
              classStudents = rawClassStudents.skip(currentOffset).take(effectiveQty).toList();
              classOffsetMap[cKey] = currentOffset + classStudents.length;
            } else {
              classStudents = rawClassStudents.take(effectiveQty).toList();
            }
          }
        } else {
          final currentOffset = classOffsetMap[cKey] ?? 0;
          final numStudentsToMake = effectiveQty > 0 ? effectiveQty : 5;

          classStudents = List.generate(numStudentsToMake, (idx) {
            final studentNum = currentOffset + idx + 1;
            return {
              'id': 'st_${sched.classId}_$studentNum',
              'full_name': 'Student $studentNum',
              'registration_number': '$studentNum',
              'class_id': sched.classId,
              'class_name': sched.className,
              'book_id': sched.bookId,
              'book_name': sched.bookName,
            };
          });

          if (effectiveQty < 5) {
            classOffsetMap[cKey] = currentOffset + numStudentsToMake;
          }
        }

        final unallocated = classStudents.where((st) {
          final sid = '${st['id']}';
          return !seatedStudentIds.contains(sid);
        }).toList();

        final itemBookName = (sched.bookName != null && sched.bookName!.trim().isNotEmpty) ? sched.bookName! : sched.bookId;
        final itemClassName = (sched.className != null && sched.className!.trim().isNotEmpty) ? sched.className! : sched.classId;
        final bookKey = '${sched.classId}_${sched.bookId}_$itemBookName';
        final wasUnselectedByUser = _userUnselectedBookKeys.contains(bookKey);

        items.add(_BookSeatingSelectionItem(
          schedule: sched,
          className: itemClassName,
          classId: sched.classId,
          bookName: itemBookName,
          bookId: sched.bookId,
          totalStudents: classStudents.length,
          allClassStudents: classStudents,
          unallocatedStudents: unallocated,
          isSelected: unallocated.isNotEmpty && !wasUnselectedByUser,
          initialQuantity: unallocated.length,
        ));
      }

      _bookItems = items;
      _updateBookSelectionDependencies();

      if (mounted) {
        setState(() {
          _savedHallSeatingMap = savedMap;
          _availableExamSessions = sessionList;
          _isLoadingBooks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBooks = false);
      }
    }
  }

  String _buildFullStudentName(Map<String, dynamic> st) {
    final name = '${st['full_name'] ?? st['fullName'] ?? st['student_name'] ?? st['first_name'] ?? st['name'] ?? ''}'.trim();
    final father = '${st['father_name'] ?? st['fatherName'] ?? ''}'.trim();
    final surname = '${st['surname'] ?? st['last_name'] ?? st['lastName'] ?? ''}'.trim();

    final parts = <String>[];
    if (name.isNotEmpty) parts.add(name);
    if (father.isNotEmpty && !name.contains(father)) parts.add(father);
    if (surname.isNotEmpty && !name.contains(surname)) parts.add(surname);

    final result = parts.join(' ').trim();
    return result.isNotEmpty ? result : 'Student';
  }

  String _buildGrNo(Map<String, dynamic> st) {
    final gr = '${st['registration_number'] ?? st['registrationNo'] ?? st['gr_no'] ?? st['grNo'] ?? st['id'] ?? ''}'.trim();
    return gr.isNotEmpty ? gr : '-';
  }

  String _buildRollNo(Map<String, dynamic> st) {
    final roll = '${st['roll_number'] ?? st['rollNo'] ?? st['roll_no'] ?? ''}'.trim();
    return roll;
  }

  String _getStudentKey(Map<String, dynamic> st) {
    final reg = _buildGrNo(st);
    if (reg.isNotEmpty && reg != '-') return 'reg_${st['class_id'] ?? ''}_$reg';
    final roll = _buildRollNo(st);
    if (roll.isNotEmpty) return 'roll_${st['class_id'] ?? ''}_$roll';
    final sid = '${st['id'] ?? ''}'.trim();
    if (sid.isNotEmpty) {
      final normalizedSid = sid.replaceAll(RegExp(r'_book[0-9a-zA-Z]+_'), '_');
      return 'id_$normalizedSid';
    }
    return 'name_${st['class_id'] ?? ''}_${_buildFullStudentName(st)}';
  }

  void _updateBookSelectionDependencies() {
    final Set<String> selectedStudentKeys = {};
    for (final b in _bookItems) {
      if (b.isSelected && !b.autoDisabled) {
        for (final st in b.unallocatedStudents) {
          selectedStudentKeys.add(_getStudentKey(st));
        }
      }
    }

    for (final b in _bookItems) {
      if (b.unallocatedStudents.isEmpty) continue;

      final totalCount = b.unallocatedStudents.length;

      if (!b.isSelected) {
        int coveredCount = 0;
        for (final st in b.unallocatedStudents) {
          if (selectedStudentKeys.contains(_getStudentKey(st))) {
            coveredCount++;
          }
        }

        if (coveredCount == totalCount && totalCount > 0) {
          b.isSelected = false;
          b.autoDisabled = true;
          b.conflictReason = 'All $totalCount students covered by selected books';
        } else if (coveredCount > 0) {
          b.autoDisabled = false;
          b.conflictReason = '$coveredCount of $totalCount students covered by other selected books';
        } else {
          b.autoDisabled = false;
          b.conflictReason = null;
        }
      } else {
        // Evaluate if this selected book's students are 100% covered by earlier selected books
        final Set<String> earlierSelectedKeys = {};
        for (final other in _bookItems) {
          if (other == b) break;
          if (other.isSelected && !other.autoDisabled) {
            for (final st in other.unallocatedStudents) {
              earlierSelectedKeys.add(_getStudentKey(st));
            }
          }
        }

        int earlierCovered = 0;
        for (final st in b.unallocatedStudents) {
          if (earlierSelectedKeys.contains(_getStudentKey(st))) {
            earlierCovered++;
          }
        }

        if (earlierCovered == totalCount && totalCount > 0) {
          // 100% of this book's students are covered by earlier selected books -> Auto-unselect & lock!
          b.isSelected = false;
          b.autoDisabled = true;
          b.conflictReason = 'All $totalCount students covered by selected books';
        } else {
          b.autoDisabled = false;
          final Set<String> otherSelectedKeys = {};
          for (final other in _bookItems) {
            if (other != b && other.isSelected && !other.autoDisabled) {
              for (final st in other.unallocatedStudents) {
                otherSelectedKeys.add(_getStudentKey(st));
              }
            }
          }
          int overlapCount = 0;
          for (final st in b.unallocatedStudents) {
            if (otherSelectedKeys.contains(_getStudentKey(st))) {
              overlapCount++;
            }
          }
          if (overlapCount > 0) {
            b.conflictReason = '$overlapCount students shared with other selected book(s)';
          } else {
            b.conflictReason = null;
          }
        }
      }
    }
  }

  Future<void> _handleGenerateSeating() async {
    if (_selectedExamId == null || _selectedHallId == null) return;

    final activeSelections = _bookItems.where((b) => b.isSelected && b.requestedQuantity > 0 && b.remainingUnallocatedCount > 0).toList();
    if (activeSelections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one book with unallocated students and quantity > 0.')),
      );
      return;
    }

    final List<Map<String, dynamic>> studentsToSeatList = [];
    final Set<String> batchStudentKeys = {};

    for (final b in activeSelections) {
      final availableSlice = b.unallocatedStudents
          .where((st) => !batchStudentKeys.contains(_getStudentKey(st)))
          .toList();

      final qty = b.requestedQuantity.clamp(1, availableSlice.isEmpty ? 1 : availableSlice.length);
      final slice = availableSlice.take(qty).toList();

      for (final st in slice) {
        batchStudentKeys.add(_getStudentKey(st));
        final map = Map<String, dynamic>.from(st);
        final fn = _buildFullStudentName(st);
        final gr = _buildGrNo(st);
        final roll = _buildRollNo(st);

        map['student_name'] = fn;
        map['full_name'] = fn;
        map['registration_number'] = gr;
        map['gr_no'] = gr;
        map['roll_number'] = roll;
        map['book_id'] = b.bookName.trim().isNotEmpty ? b.bookName.trim() : b.bookId;
        map['book_name'] = b.bookName.trim().isNotEmpty ? b.bookName.trim() : b.bookId;
        map['class_id'] = b.classId;
        map['class_name'] = b.className;
        studentsToSeatList.add(map);
      }
    }

    if (studentsToSeatList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unallocated students available for selected criteria.')),
      );
      return;
    }

    setState(() => _isGenerating = true);
    context.read<ExamBloc>().add(GenerateSeating(
      examId: _selectedExamId!,
      hallId: _selectedHallId!,
      sessionDate: _dateCtrl.text,
      sessionTime: _timeCtrl.text,
      students: studentsToSeatList,
    ));
    setState(() => _isGenerating = false);
  }

  Future<void> _handleSaveSeating() async {
    if (_selectedExamId != null) {
      context.read<ExamBloc>().add(SaveSeating(_selectedExamId!));
      await Future.delayed(const Duration(milliseconds: 400));
      await _loadBookSelectionsAndSavedHalls();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seating arrangement saved successfully! Student counts updated.'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteSavedHallPlan(int hallId, String hallName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $hallName Seating Plan'),
        content: Text('Are you sure you want to delete the saved seating plan for $hallName? All allocated students will become unallocated again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Plan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && _selectedExamId != null) {
      final repo = ExamLocalRepository();
      await repo.deleteHallSeatingForSession(_selectedExamId!, hallId, _dateCtrl.text, _timeCtrl.text);
      await _loadBookSelectionsAndSavedHalls();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted seating plan for $hallName. Students released for allocation!')),
        );
      }
    }
  }

  void _showSavedHallPreview(int hallId, String hallName, List<SeatingArrangement> arrangements) {
    final targetHall = widget.halls.firstWhere(
      (h) => h.id == hallId,
      orElse: () => ExamHall(id: hallId, name: hallName, totalRows: 10, totalColumns: 10),
    );
    setState(() {
      _selectedHallId = hallId;
      _currentSeatingHall = targetHall;
      _currentSeatingResult = SeatingResult(
        assignments: arrangements.map((a) => SeatAssignment(
          student: StudentSeatInput(
            studentId: a.studentId,
            studentName: a.studentName ?? 'Student',
            registrationNumber: a.registrationNumber ?? '-',
            rollNumber: a.rollNumber,
            classId: a.classId,
            className: a.className ?? '',
            bookId: a.bookId,
            bookName: a.bookName ?? '',
          ),
          seat: SeatPosition(
            row: a.seatRow,
            col: a.seatColumn,
            seatNumber: a.seatNumber,
          ),
          method: a.assignmentMethod,
        )).toList(),
        warnings: [],
        primaryMethod: 'SAVED_PLAN',
        totalStudents: arrangements.length,
        placedCount: arrangements.length,
        tier1Count: arrangements.length,
        tier2Count: 0,
        tier3Count: 0,
      );
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Viewing seating matrix for $hallName (${arrangements.length} students).'),
          backgroundColor: AppTheme.primaryColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _openSeatingExportDialog({List<SeatingArrangement>? specificArrangements}) {
    final bloc = context.read<ExamBloc>();
    final activeResult = _currentSeatingResult ?? widget.result ?? bloc.lastGeneratedSeating;
    final activeHall = _currentSeatingHall ??
        widget.resultHall ??
        bloc.lastGeneratedHall ??
        widget.halls.firstWhere(
          (h) => h.id == _selectedHallId,
          orElse: () => ExamHall(name: 'Exam Hall', totalRows: 10, totalColumns: 10),
        );
    final activeExam = widget.exams.firstWhere(
      (e) => e.id == _selectedExamId,
      orElse: () => Exam(name: 'Exam Session'),
    );

    final List<SeatingExportRow> exportRows = [];

    if (specificArrangements != null && specificArrangements.isNotEmpty) {
      for (final a in specificArrangements) {
        exportRows.add(SeatingExportRow(
          grNo: (a.registrationNumber != null && a.registrationNumber!.trim().isNotEmpty)
              ? a.registrationNumber!.trim()
              : '-',
          studentFullName: (a.studentName != null && a.studentName!.trim().isNotEmpty)
              ? a.studentName!.trim()
              : 'Student',
          seatNumber: 'Seat ${a.seatNumber}',
          className: (a.className != null && a.className!.trim().isNotEmpty)
              ? a.className!.trim()
              : 'Class',
          bookName: (a.bookName != null && a.bookName!.trim().isNotEmpty)
              ? a.bookName!.trim()
              : 'Subject',
        ));
      }
    } else if (activeResult != null && activeResult.assignments.isNotEmpty) {
      for (final a in activeResult.assignments) {
        exportRows.add(SeatingExportRow(
          grNo: a.student.registrationNumber.trim().isNotEmpty
              ? a.student.registrationNumber.trim()
              : '-',
          studentFullName: a.student.studentName.trim().isNotEmpty
              ? a.student.studentName.trim()
              : 'Student',
          seatNumber: 'Seat ${a.seat.seatNumber}',
          className: a.student.className.trim().isNotEmpty
              ? a.student.className.trim()
              : 'Class',
          bookName: a.student.bookName.trim().isNotEmpty
              ? a.student.bookName.trim()
              : 'Subject',
        ));
      }
    } else if (_savedHallSeatingMap.isNotEmpty) {
      for (final arrangements in _savedHallSeatingMap.values) {
        for (final a in arrangements) {
          exportRows.add(SeatingExportRow(
            grNo: (a.registrationNumber != null && a.registrationNumber!.trim().isNotEmpty)
                ? a.registrationNumber!.trim()
                : '-',
            studentFullName: (a.studentName != null && a.studentName!.trim().isNotEmpty)
                ? a.studentName!.trim()
                : 'Student',
            seatNumber: 'Seat ${a.seatNumber}',
            className: (a.className != null && a.className!.trim().isNotEmpty)
                ? a.className!.trim()
                : 'Class',
            bookName: (a.bookName != null && a.bookName!.trim().isNotEmpty)
                ? a.bookName!.trim()
                : 'Subject',
          ));
        }
      }
    }

    if (exportRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No seating arrangement records available to export. Please generate seating first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    SeatingExportService.showExportDialog(
      context: context,
      examName: activeExam.name,
      hallName: activeHall.name,
      sessionDate: _dateCtrl.text,
      sessionTime: _timeCtrl.text,
      allRows: exportRows,
    );
  }

  void _showClearSeatingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Seating'),
        content: const Text('Are you sure you want to clear ALL seating arrangements for this exam?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (_selectedExamId != null) {
                context.read<ExamBloc>().add(ClearSeating(_selectedExamId!));
                setState(() {
                  _currentSeatingResult = null;
                  _currentSeatingHall = null;
                });
                await Future.delayed(const Duration(milliseconds: 300));
                await _loadBookSelectionsAndSavedHalls();
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 1400.0).clamp(0.75, 1.2);

    final bloc = context.read<ExamBloc>();
    SeatingResult? activeResult = _currentSeatingResult ?? widget.result ?? bloc.lastGeneratedSeating;
    ExamHall? activeHall = _currentSeatingHall ?? widget.resultHall ?? bloc.lastGeneratedHall;

    // Fallback: If no active generated seating is in memory, but selected hall has a saved seating plan, display it!
    if (activeResult == null && _selectedHallId != null && _savedHallSeatingMap.containsKey(_selectedHallId)) {
      final savedArrangements = _savedHallSeatingMap[_selectedHallId];
      if (savedArrangements != null && savedArrangements.isNotEmpty) {
        activeResult = SeatingResult(
          assignments: savedArrangements.map((a) => SeatAssignment(
            student: StudentSeatInput(
              studentId: a.studentId,
              studentName: a.studentName ?? 'Student',
              registrationNumber: a.registrationNumber ?? '-',
              rollNumber: a.rollNumber,
              classId: a.classId,
              className: a.className ?? '',
              bookId: a.bookId,
              bookName: a.bookName ?? '',
            ),
            seat: SeatPosition(
              row: a.seatRow,
              col: a.seatColumn,
              seatNumber: a.seatNumber,
            ),
            method: a.assignmentMethod,
          )).toList(),
          warnings: [],
          primaryMethod: 'SAVED_PLAN',
          totalStudents: savedArrangements.length,
          placedCount: savedArrangements.length,
          tier1Count: savedArrangements.length,
          tier2Count: 0,
          tier3Count: 0,
        );
        activeHall ??= widget.halls.firstWhere(
          (h) => h.id == _selectedHallId,
          orElse: () => ExamHall(id: _selectedHallId!, name: 'Hall', totalRows: 10, totalColumns: 10),
        );
      }
    }

    final selectedHall = widget.halls.firstWhere(
      (h) => h.id == _selectedHallId,
      orElse: () => ExamHall(id: 0, name: '', totalRows: 0, totalColumns: 0),
    );
    final totalHallSeats = selectedHall.totalRows * selectedHall.totalColumns;

    int totalSelectedToSeat = 0;
    for (final b in _bookItems) {
      if (b.isSelected && b.remainingUnallocatedCount > 0) {
        totalSelectedToSeat += b.requestedQuantity.clamp(0, b.remainingUnallocatedCount);
      }
    }

    final isCapacityExceeded = totalHallSeats > 0 && totalSelectedToSeat > totalHallSeats;

    final Map<String, List<_BookSeatingSelectionItem>> classGroupedItems = {};
    for (final b in _bookItems) {
      classGroupedItems.putIfAbsent(b.className, () => []).add(b);
    }

    return Padding(
      padding: EdgeInsets.all(20 * scale),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8 * scale),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10 * scale),
                  ),
                  child: Icon(Icons.event_seat_rounded, color: AppTheme.primaryColor, size: 22 * scale),
                ),
                SizedBox(width: 10 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('seating_plan_generator'),
                        style: AppTheme.getFontStyle(
                            fontSize: 20 * scale, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Multi-Hall Student Allocation & Anti-Adjacent Seat Planner',
                        style: AppTheme.getFontStyle(fontSize: 12 * scale, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16 * scale),

            // ── Selector Controls Bar ──
            Container(
              padding: EdgeInsets.all(16 * scale),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14 * scale),
                color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 950;

                  Widget examField = DropdownButtonFormField<int>(
                    value: (widget.exams.any((e) => e.id == _selectedExamId))
                        ? _selectedExamId
                        : null,
                    decoration: InputDecoration(
                      labelText: context.tr('select_exam'),
                      prefixIcon: const Icon(Icons.event_note_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: widget.exams
                        .map((e) => DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _selectedExamId = v);
                      _loadBookSelectionsAndSavedHalls();
                    },
                  );

                  Widget hallField = DropdownButtonFormField<int>(
                    value: (widget.halls.any((h) => h.id == _selectedHallId))
                        ? _selectedHallId
                        : null,
                    decoration: InputDecoration(
                      labelText: context.tr('select_hall'),
                      prefixIcon: const Icon(Icons.business_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: widget.halls
                        .map((h) => DropdownMenuItem(
                            value: h.id,
                            child: Text(
                              '${h.name} (${h.totalRows}x${h.totalColumns} = ${h.totalRows * h.totalColumns} Seats)',
                              overflow: TextOverflow.ellipsis,
                            )))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedHallId = v),
                  );

                  Widget dateField = DribbbleDatePickerField(
                    controller: _dateCtrl,
                    labelText: 'Session Date',
                  );

                  Widget timeField = DribbbleTimePickerField(
                    controller: _timeCtrl,
                    labelText: 'Session Time',
                  );

                  Widget buttonsRow = Wrap(
                    spacing: 12 * scale,
                    runSpacing: 10 * scale,
                    children: [
                      SizedBox(
                        height: 44 * scale,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 18 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                          ),
                          onPressed: (_selectedExamId != null && _selectedHallId != null && !_isGenerating)
                              ? _handleGenerateSeating
                              : null,
                          icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                          label: Text(
                            context.tr('generate_seating'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 44 * scale,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 18 * scale),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                          ),
                          onPressed: () => _openSeatingExportDialog(),
                          icon: const Icon(Icons.file_download_outlined, color: Colors.white),
                          label: Text(
                            'Export Seating Plan',
                            style: AppTheme.getFontStyle(
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

                  if (isNarrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: examField),
                            SizedBox(width: 12 * scale),
                            Expanded(child: hallField),
                          ],
                        ),
                        SizedBox(height: 12 * scale),
                        Row(
                          children: [
                            Expanded(child: dateField),
                            SizedBox(width: 12 * scale),
                            Expanded(child: timeField),
                          ],
                        ),
                        SizedBox(height: 14 * scale),
                        buttonsRow,
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: examField),
                          SizedBox(width: 12 * scale),
                          Expanded(child: hallField),
                          SizedBox(width: 12 * scale),
                          Expanded(child: dateField),
                          SizedBox(width: 12 * scale),
                          Expanded(child: timeField),
                        ],
                      ),
                      SizedBox(height: 14 * scale),
                      buttonsRow,
                    ],
                  );
                },
              ),
            ),

            if (_availableExamSessions.isNotEmpty) ...[
              SizedBox(height: 10 * scale),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 16 * scale, color: AppTheme.primaryColor),
                    SizedBox(width: 6 * scale),
                    Text(
                      'Quick Session Filter:',
                      style: AppTheme.getFontStyle(fontSize: 12 * scale, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 8 * scale),
                    ..._availableExamSessions.map((sess) {
                      final rawDate = sess['date'] ?? '';
                      final sDate = _formatToDdMmYyyy(rawDate);
                      final rawTime = sess['time'] ?? '';
                      final sTime = _formatTo12HourAmPm(rawTime);
                      final rawEnd = sess['endTime'] ?? '';
                      final sEnd = _formatTo12HourAmPm(rawEnd);
                      final isSelected = _normalizeDateStr(_dateCtrl.text) == _normalizeDateStr(rawDate) &&
                          (rawTime.isEmpty || _normalizeTimeForComparison(_timeCtrl.text) == _normalizeTimeForComparison(rawTime));

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selectedColor: AppTheme.primaryColor,
                          backgroundColor: isDark ? const Color(0xFF1E1E34) : Colors.grey.shade100,
                          label: Text(
                            '📅 $sDate (${sTime.isNotEmpty ? (sEnd.isNotEmpty ? '$sTime - $sEnd' : sTime) : 'All Day'})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) {
                            _isUpdatingFromListener = true;
                            setState(() {
                              _dateCtrl.text = sDate;
                              _timeCtrl.text = sTime;
                            });
                            _isUpdatingFromListener = false;
                            _loadBookSelectionsAndSavedHalls();
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            SizedBox(height: 16 * scale),

            // ── CLASS-WISE BOOKS & UNALLOCATED STUDENT ALLOCATION PANEL ──
            if (_selectedExamId != null) ...[
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14 * scale),
                  color: isDark ? const Color(0xFF141428) : const Color(0xFFF8FAFC),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, color: AppTheme.primaryColor, size: 20 * scale),
                            SizedBox(width: 8 * scale),
                            Text(
                              'Class-Wise Books & Student Quantity Chooser',
                              style: AppTheme.getFontStyle(fontSize: 16 * scale, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (totalHallSeats > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isCapacityExceeded
                                  ? Colors.red.withOpacity(0.12)
                                  : AppTheme.primaryColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCapacityExceeded
                                    ? Colors.red.withOpacity(0.5)
                                    : AppTheme.primaryColor.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isCapacityExceeded ? Icons.warning_amber_rounded : Icons.event_seat_rounded,
                                  size: 15,
                                  color: isCapacityExceeded ? Colors.red : AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Selected: $totalSelectedToSeat / $totalHallSeats Seats (${selectedHall.name})',
                                  style: AppTheme.getFontStyle(
                                    fontSize: 12.5 * scale,
                                    fontWeight: FontWeight.bold,
                                    color: isCapacityExceeded ? Colors.red : AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    SizedBox(height: 12 * scale),

                    if (_isLoadingBooks)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    else if (_bookItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'No exam schedules found for selected date and time.',
                          style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey),
                        ),
                      )
                    else
                      Column(
                        children: classGroupedItems.entries.map((entry) {
                          final className = entry.key;
                          final bList = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E1E34) : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: true,
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.school_rounded, color: AppTheme.primaryColor, size: 18),
                              ),
                              title: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Class: $className',
                                    style: AppTheme.getFontStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                  ),
                                  Builder(builder: (context) {
                                    final firstSched = bList.isNotEmpty ? bList.first.schedule : null;
                                    final parentDept = firstSched?.parentDepartmentName;
                                    final deptName = firstSched?.departmentName;
                                    String? deptBadge;
                                    if (parentDept != null && parentDept.isNotEmpty && deptName != null && deptName.isNotEmpty) {
                                      deptBadge = '$parentDept • $deptName';
                                    } else if (deptName != null && deptName.isNotEmpty) {
                                      deptBadge = deptName;
                                    }
                                    if (deptBadge == null) return const SizedBox.shrink();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1565C0).withAlpha(15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF1565C0).withAlpha(60), width: 0.6),
                                      ),
                                      child: Text(
                                        deptBadge,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1565C0)),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              subtitle: Text(
                                '${bList.length} Books scheduled for this session',
                                style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey),
                              ),
                              children: bList.map((bItem) {
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade100),
                                    ),
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, itemConstraints) {
                                      final isItemNarrow = itemConstraints.maxWidth < 650;
                                      final leftContent = Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            activeColor: AppTheme.primaryColor,
                                            value: bItem.isSelected && !bItem.isFullyAllocated && !bItem.autoDisabled,
                                            onChanged: (bItem.isFullyAllocated || bItem.autoDisabled)
                                                ? null
                                                : (v) {
                                                    setState(() {
                                                      bItem.isSelected = v ?? false;
                                                      _updateBookSelectionDependencies();
                                                    });
                                                  },
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    Text(
                                                      bItem.bookName,
                                                      style: AppTheme.getFontStyle(
                                                        fontSize: 13.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: (bItem.isFullyAllocated || bItem.autoDisabled) ? Colors.grey : null,
                                                      ),
                                                    ),
                                                    if (bItem.conflictReason != null)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: bItem.autoDisabled
                                                              ? Colors.orange.withOpacity(0.12)
                                                              : AppTheme.primaryColor.withOpacity(0.08),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(
                                                            color: bItem.autoDisabled
                                                                ? Colors.orange.withOpacity(0.5)
                                                                : AppTheme.primaryColor.withOpacity(0.3),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          bItem.autoDisabled
                                                              ? '🔒 ${bItem.conflictReason}'
                                                              : '⚠️ ${bItem.conflictReason}',
                                                          style: TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.bold,
                                                            color: bItem.autoDisabled ? Colors.orange.shade800 : AppTheme.primaryColor,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    _buildStatChip(
                                                      'Total: ${bItem.totalStudents}',
                                                      Colors.blue,
                                                      isDark,
                                                    ),
                                                    _buildStatChip(
                                                      'Seated: ${bItem.alreadySeatedCount}',
                                                      AppTheme.successColor,
                                                      isDark,
                                                    ),
                                                    _buildStatChip(
                                                      'Unallocated: ${bItem.remainingUnallocatedCount}',
                                                      bItem.remainingUnallocatedCount > 0 ? Colors.orange : Colors.grey,
                                                      isDark,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );

                                      final rightControl = bItem.isFullyAllocated
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successColor.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: AppTheme.successColor.withOpacity(0.4)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successColor),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    'Fully Allocated ✅',
                                                    style: AppTheme.getFontStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.successColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  'Seats in Hall:',
                                                  style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                                                  onPressed: bItem.isSelected && bItem.requestedQuantity > 0
                                                      ? () {
                                                          setState(() {
                                                            bItem.setQuantity(bItem.requestedQuantity - 1);
                                                          });
                                                        }
                                                      : null,
                                                ),
                                                SizedBox(
                                                  width: 60,
                                                  height: 36,
                                                  child: TextField(
                                                    controller: bItem.quantityCtrl,
                                                    keyboardType: TextInputType.number,
                                                    enabled: bItem.isSelected,
                                                    textAlign: TextAlign.center,
                                                    style: AppTheme.getFontStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.primaryColor,
                                                    ),
                                                    decoration: InputDecoration(
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    onChanged: (_) => setState(() {}),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                                                  onPressed: bItem.isSelected && bItem.requestedQuantity < bItem.remainingUnallocatedCount
                                                      ? () {
                                                          setState(() {
                                                            bItem.setQuantity(bItem.requestedQuantity + 1);
                                                          });
                                                        }
                                                      : null,
                                                ),
                                                InkWell(
                                                  onTap: bItem.isSelected
                                                      ? () {
                                                          setState(() {
                                                            bItem.setQuantity(bItem.remainingUnallocatedCount);
                                                          });
                                                        }
                                                      : null,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.primaryColor.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'All (${bItem.remainingUnallocatedCount})',
                                                      style: AppTheme.getFontStyle(
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: AppTheme.primaryColor,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );

                                      if (isItemNarrow) {
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            leftContent,
                                            const SizedBox(height: 8),
                                            Padding(
                                              padding: const EdgeInsets.only(left: 36),
                                              child: rightControl,
                                            ),
                                          ],
                                        );
                                      }

                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Expanded(child: leftContent),
                                          const SizedBox(width: 12),
                                          rightControl,
                                        ],
                                      );
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              SizedBox(height: 16 * scale),
            ],

            // ── Action Bar (Save & Lock, Clear Seating) ──
            Wrap(
              spacing: 12 * scale,
              runSpacing: 10 * scale,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 10 * scale,
                  runSpacing: 8 * scale,
                  children: [
                    SizedBox(
                      height: 42 * scale,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.successColor,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                        ),
                        onPressed: _handleSaveSeating,
                        icon: Icon(Icons.save_rounded, color: Colors.white, size: 18 * scale),
                        label: Text(
                          'Save & Lock Seating',
                          style: AppTheme.getFontStyle(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 42 * scale,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E88E5),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                        ),
                        onPressed: () => _openSeatingExportDialog(),
                        icon: Icon(Icons.file_download_outlined, color: Colors.white, size: 18 * scale),
                        label: Text(
                          'Export Seating Plan',
                          style: AppTheme.getFontStyle(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 42 * scale,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                    ),
                    onPressed: _showClearSeatingDialog,
                    icon: Icon(Icons.delete_sweep_rounded, size: 18 * scale),
                    label: Text(
                      'Clear All Seating',
                      style: AppTheme.getFontStyle(fontSize: 13 * scale, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: 16 * scale),

            // ── SAVED SEATING PLANS SUMMARY LIST (VIEW, EDIT, DELETE) ──
            if (_savedHallSeatingMap.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E32) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primaryColor.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_rounded, color: AppTheme.primaryColor, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Saved Hall Seating Plans (${_savedHallSeatingMap.length} Halls Allocated)',
                          style: AppTheme.getFontStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Column(
                      children: _savedHallSeatingMap.entries.map((e) {
                        final hallId = e.key;
                        final arrangements = e.value;
                        final hName = widget.halls.firstWhere(
                          (h) => h.id == hallId,
                          orElse: () => ExamHall(id: hallId, name: 'Hall #$hallId', totalRows: 10, totalColumns: 10),
                        ).name;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2A2A44) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: LayoutBuilder(
                            builder: (context, planConstraints) {
                              final isPlanNarrow = planConstraints.maxWidth < 650;
                              final infoWidget = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.business_rounded, color: AppTheme.primaryColor, size: 18),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hName,
                                        style: AppTheme.getFontStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '${arrangements.length} Seats Allocated for Date ${_dateCtrl.text} (${_timeCtrl.text})',
                                        style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ],
                              );

                              final actionsWidget = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _showSavedHallPreview(hallId, hName, arrangements),
                                    icon: const Icon(Icons.grid_view_rounded, size: 14),
                                    label: const Text('View Excel Blueprint', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E88E5),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => _openSeatingExportDialog(specificArrangements: arrangements),
                                    icon: const Icon(Icons.file_download_outlined, size: 14),
                                    label: const Text('Export Seating Plan', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22),
                                    tooltip: 'Delete Hall Plan & Release Students',
                                    onPressed: () => _deleteSavedHallPlan(hallId, hName),
                                  ),
                                ],
                              );

                              if (isPlanNarrow) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    infoWidget,
                                    const SizedBox(height: 8),
                                    actionsWidget,
                                  ],
                                );
                              }

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: infoWidget),
                                  actionsWidget,
                                ],
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16 * scale),
            ],

            // ── Seating Grid Display Matrix ──
            SizedBox(
              height: 520 * scale,
              child: activeResult != null && activeHall != null
                  ? SeatingGridWidget(
                      rows: activeHall.totalRows,
                      columns: activeHall.totalColumns,
                      assignments: activeResult.assignments,
                      warnings: activeResult.warnings,
                      primaryMethod: activeResult.primaryMethod,
                      totalStudents: activeResult.totalStudents,
                      placedCount: activeResult.placedCount,
                      tier1Count: activeResult.tier1Count,
                      tier2Count: activeResult.tier2Count,
                      tier3Count: activeResult.tier3Count,
                    )
                  : const _EmptyState(
                      icon: Icons.event_seat_rounded,
                      label: 'No seating arrangement generated',
                      subtitle: 'Select Exam, Hall, and Books/Quantities then click Generate Seating',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: AppTheme.getFontStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 4: MARKS ENTRY
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  TAB 4: MARKS ENTRY
// ═══════════════════════════════════════════════════════════════════

class _MarksTab extends StatefulWidget {
  final List<Exam> exams;

  const _MarksTab({required this.exams});

  @override
  State<_MarksTab> createState() => _MarksTabState();
}

class _MarksTabState extends State<_MarksTab>
    with AutomaticKeepAliveClientMixin {
  int? _selectedExamId;
  int? _selectedScheduleId;
  String? _selectedMainDeptId;
  String? _selectedSubDeptId;
  String? _selectedDivision;
  List<ExamSchedule> _schedules = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _hierarchy = [];
  List<ExamMark> _marks = [];
  final Map<int, TextEditingController> _marksControllers = {};
  bool _isLoadingMarks = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<ExamBloc>();
    _selectedExamId = bloc.lastMarksExamId;
    _selectedScheduleId = bloc.lastMarksScheduleId;
    _marks = bloc.lastLoadedMarks;
    for (final m in _marks) {
      _marksControllers[m.id ?? m.hashCode] = TextEditingController(
        text: m.marksObtained != null
            ? m.marksObtained!.toStringAsFixed(0)
            : '',
      );
    }
    _loadAcademicData();
  }

  Future<void> _loadAcademicData() async {
    try {
      final repo = AcademicRepository(ApiClient());
      final results = await Future.wait([
        repo.getAllDepartments(),
        repo.getAcademicHierarchy(),
      ]);
      if (mounted) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(results[0]);
          _hierarchy = List<Map<String, dynamic>>.from(results[1]);
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _mainDepts =>
      _departments.where((d) => d['parent_id'] == null).toList();

  List<Map<String, dynamic>> get _subDeptsForSelectedMain {
    if (_selectedMainDeptId == null) {
      return _departments.where((d) => d['parent_id'] != null).toList();
    }
    return _departments
        .where((d) => d['parent_id']?.toString() == _selectedMainDeptId)
        .toList();
  }

  List<ExamSchedule> get _filteredSchedules {
    return _schedules.where((s) {
      if (_selectedSubDeptId != null) {
        return s.departmentId == _selectedSubDeptId;
      }
      if (_selectedMainDeptId != null) {
        final dept = _departments.where(
          (d) => d['id']?.toString() == s.departmentId,
        ).firstOrNull;
        final parentId = dept?['parent_id']?.toString() ?? s.departmentId;
        return s.departmentId == _selectedMainDeptId ||
            parentId == _selectedMainDeptId;
      }
      return true;
    }).toList();
  }

  String _norm(String? s) {
    if (s == null) return '';
    return s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ذ', 'د')
        .replaceAll('ز', 'ر')
        .replaceAll(RegExp(r'\s+'), '')
        .toLowerCase();
  }

  Map<String, dynamic>? _findClassNodeForSchedule(ExamSchedule? sched) {
    if (sched == null) return null;
    final nClassId = _norm(sched.classId);
    final nClassName = _norm(sched.className);
    final nDeptId = _norm(sched.departmentId);

    if (nDeptId.isNotEmpty) {
      for (final c in _hierarchy) {
        final cDeptId = _norm('${c['department_id']}');
        if (cDeptId == nDeptId) {
          final cId = _norm('${c['id']}');
          final cName = _norm('${c['name']}');
          if ((nClassId.isNotEmpty && (cId == nClassId || cName == nClassId)) ||
              (nClassName.isNotEmpty && (cName == nClassName || cId == nClassName))) {
            return c;
          }
        }
      }
    }

    for (final c in _hierarchy) {
      final cId = _norm('${c['id']}');
      final cName = _norm('${c['name']}');
      if ((nClassId.isNotEmpty && (cId == nClassId || cName == nClassId)) ||
          (nClassName.isNotEmpty && (cName == nClassName || cId == nClassName))) {
        return c;
      }
    }

    return null;
  }

  List<String> get _availableDivisions {
    if (_selectedScheduleId == null) return [];
    final sched = _schedules.where((s) => s.id == _selectedScheduleId).firstOrNull;
    if (sched == null) return [];

    final classNode = _findClassNodeForSchedule(sched);
    final set = <String>{};

    // 1. Get divisions specifically assigned to this class in academic hierarchy
    if (classNode != null && classNode['courses'] is List) {
      for (final crs in classNode['courses'] as List) {
        if (crs is Map) {
          final name = (crs['name'] ?? crs['title'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            set.add(name);
          }
        }
      }
    }

    // 2. Fallback to loaded marks only if class courses not yet assigned
    if (set.isEmpty) {
      for (final m in _marks) {
        final d = m.division?.trim();
        if (d != null && d.isNotEmpty) {
          set.add(d);
        }
      }
    }

    final list = set.toList();
    list.sort();
    return list;
  }

  List<ExamMark> get _displayedMarks {
    var list = _marks;
    if (_selectedDivision != null && _selectedDivision!.trim().isNotEmpty) {
      final sel = _norm(_selectedDivision!);
      list = list.where((m) {
        final d = _norm(m.division);
        if (d.isEmpty) return false;
        if (d == sel) return true;
        if (d == 'section$sel' || d == 'div$sel' || d == 'division$sel') return true;
        return false;
      }).toList();
    }
    final sorted = List<ExamMark>.from(list);
    sorted.sort(ExamMark.compareRollNumber);
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filteredScheds = _filteredSchedules;
    final displayedMarks = _displayedMarks;

    return BlocListener<ExamBloc, ExamState>(
      listener: (context, state) {
        if (state is MarksLoaded) {
          setState(() {
            _isLoadingMarks = false;
            _marks = state.marks;
            _marksControllers.clear();
            for (final m in _marks) {
              _marksControllers[m.id ?? m.hashCode] = TextEditingController(
                text: m.marksObtained != null
                    ? m.marksObtained!.toStringAsFixed(0)
                    : '',
              );
            }
          });
        }
        if (state is SchedulesLoaded) {
          setState(() {
            _schedules = state.schedules;
          });
        }
        if (state is ExamOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
        if (state is ExamError) {
          setState(() => _isLoadingMarks = false);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('marks_entry'),
              style: AppTheme.getFontStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ── Selectors ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                border:
                    Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // Row 1: Exam + Department Filters
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: (widget.exams.any((e) => e.id == _selectedExamId))
                              ? _selectedExamId
                              : null,
                          decoration: InputDecoration(
                            labelText: context.tr('select_exam'),
                            prefixIcon:
                                const Icon(Icons.event_note_rounded, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: widget.exams
                              .map((e) => DropdownMenuItem(
                                  value: e.id, child: Text(e.name, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (v) {
                            final bloc = context.read<ExamBloc>();
                            bloc.lastMarksExamId = v;
                            setState(() {
                              _selectedExamId = v;
                              _selectedScheduleId = null;
                              _selectedDivision = null;
                              _marks = [];
                            });
                            if (v != null) {
                              bloc.add(LoadSchedules(v));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedMainDeptId,
                          decoration: InputDecoration(
                            labelText: 'Main Department',
                            prefixIcon: const Icon(Icons.business_center_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Departments', style: TextStyle(fontSize: 12)),
                            ),
                            ..._mainDepts.map((d) => DropdownMenuItem<String?>(
                                  value: d['id']?.toString(),
                                  child: Text(d['name']?.toString() ?? 'Dept', style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedMainDeptId = v;
                              _selectedSubDeptId = null;
                              _selectedScheduleId = null;
                              _selectedDivision = null;
                              _marks = [];
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedSubDeptId,
                          decoration: InputDecoration(
                            labelText: 'Sub-Department',
                            prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Sub-Depts', style: TextStyle(fontSize: 12)),
                            ),
                            ..._subDeptsForSelectedMain.map((d) => DropdownMenuItem<String?>(
                                  value: d['id']?.toString(),
                                  child: Text(d['name']?.toString() ?? 'Sub-Dept', style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedSubDeptId = v;
                              _selectedScheduleId = null;
                              _selectedDivision = null;
                              _marks = [];
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Row 2: Schedule dropdown, Division dropdown & Load button
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          value: (filteredScheds.any((s) => s.id == _selectedScheduleId))
                              ? _selectedScheduleId
                              : null,
                          decoration: InputDecoration(
                            labelText: context.tr('select_schedule'),
                            prefixIcon: const Icon(Icons.subject_rounded, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: filteredScheds.map((s) {
                            final cName = s.className ?? s.classId;
                            final bName = s.bookName ?? s.bookId;
                            final pDept = s.parentDepartmentName;
                            final dDept = s.departmentName;
                            String prefix = '';
                            if (pDept != null && pDept.isNotEmpty && dDept != null && dDept.isNotEmpty) {
                              prefix = '[$pDept • $dDept] ';
                            } else if (dDept != null && dDept.isNotEmpty) {
                              prefix = '[$dDept] ';
                            }

                            return DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                '$prefix$cName - $bName',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            context.read<ExamBloc>().lastMarksScheduleId = v;
                            setState(() {
                              _selectedScheduleId = v;
                              _selectedDivision = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Builder(
                          builder: (context) {
                            final avDivs = _availableDivisions;
                            final currentVal = (avDivs.contains(_selectedDivision)) ? _selectedDivision : null;
                            final hasSchedule = _selectedScheduleId != null;

                            return DropdownButtonFormField<String?>(
                              value: currentVal,
                              decoration: InputDecoration(
                                labelText: 'Division / ڈویژن',
                                prefixIcon: const Icon(Icons.group_work_rounded, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                helperText: hasSchedule
                                    ? (avDivs.isEmpty ? 'No divisions assigned to class' : '${avDivs.length} division(s) available')
                                    : 'Select schedule first',
                                helperStyle: const TextStyle(fontSize: 10.5),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Divisions (تمام)', style: TextStyle(fontSize: 12)),
                                ),
                                ...avDivs.map((div) => DropdownMenuItem<String?>(
                                      value: div,
                                      child: Text('Division $div', style: const TextStyle(fontSize: 12)),
                                    )),
                              ],
                              onChanged: (hasSchedule && avDivs.isNotEmpty)
                                  ? (v) {
                                      setState(() {
                                        _selectedDivision = v;
                                      });
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_selectedScheduleId != null && !_isLoadingMarks)
                              ? () {
                                  final bloc = context.read<ExamBloc>();
                                  bloc.lastMarksExamId = _selectedExamId;
                                  bloc.lastMarksScheduleId = _selectedScheduleId;
                                  setState(() => _isLoadingMarks = true);
                                  bloc.add(LoadMarks(_selectedScheduleId!));
                                }
                              : null,
                          icon: _isLoadingMarks
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.search, color: Colors.white),
                          label: Text(
                            _isLoadingMarks ? 'Loading...' : context.tr('load_students'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_isLoadingMarks)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_marks.isEmpty)
              Expanded(
                child: Center(
                  child: _EmptyState(
                    icon: Icons.edit_note_rounded,
                    label: context.tr('no_marks_loaded'),
                    subtitle: context.tr('no_marks_subtitle'),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedDivision != null
                              ? 'Students (${displayedMarks.length} of ${_marks.length}) • Div: $_selectedDivision'
                              : 'Total Students: ${_marks.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _saveMarks,
                          icon: const Icon(Icons.save_rounded, color: Colors.white),
                          label: Text(
                            context.tr('save_marks'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (displayedMarks.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            'No students found for Division $_selectedDivision.',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: displayedMarks.length,
                          itemBuilder: (context, index) {
                            final mark = displayedMarks[index];
                            final ctrl =
                                _marksControllers[mark.id ?? mark.hashCode];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    // Roll number badge
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: AppTheme.primaryColor.withOpacity(0.3)),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'رول نمبر',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                          Text(
                                            (mark.rollNumber != null &&
                                                    mark.rollNumber!.trim().isNotEmpty)
                                                ? mark.rollNumber!.trim()
                                                : '-',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.primaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Student info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            mark.studentName ?? 'Student',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                'GR: ${mark.registrationNumber ?? "-"}',
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey.shade600),
                                              ),
                                              Text(
                                                '•',
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey.shade400),
                                              ),
                                              Text(
                                                'Class: ${mark.className ?? "-"}',
                                                style: TextStyle(
                                                    fontSize: 12, color: Colors.grey.shade600),
                                              ),
                                              if (mark.division != null &&
                                                  mark.division!.trim().isNotEmpty) ...[
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.deepPurple.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                        color:
                                                            Colors.deepPurple.withOpacity(0.3)),
                                                  ),
                                                  child: Text(
                                                    'Div: ${mark.division!.trim()}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.deepPurple,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    // Marks entry input field
                                    SizedBox(
                                      width: 110,
                                      child: TextField(
                                        controller: ctrl,
                                        keyboardType: const TextInputType.numberWithOptions(
                                            decimal: true),
                                        decoration: InputDecoration(
                                          labelText: 'Marks (/${mark.maxMarks})',
                                          border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 10),
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
              ),
          ],
        ),
      ),
    );
  }

  void _saveMarks() {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('exams_marks_entry')) {
      UpgradePlanDialog.show(context, highlightModule: 'Subject-wise Marks Entry');
      return;
    }

    final updated = <ExamMark>[];
    for (int i = 0; i < _marks.length; i++) {
      final m = _marks[i];
      final ctrl = _marksControllers[m.id ?? m.hashCode];
      final marksVal = double.tryParse(ctrl?.text ?? '');
      updated.add(m.copyWith(
        marksObtained: m.isAbsent ? null : marksVal,
      ));
    }
    context.read<ExamBloc>().add(SaveMarks(updated));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TAB 5: RESULTS REPORT
// ═══════════════════════════════════════════════════════════════════

class _ResultsTab extends StatefulWidget {
  final List<Exam> exams;

  const _ResultsTab({required this.exams});

  @override
  State<_ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<_ResultsTab>
    with AutomaticKeepAliveClientMixin {
  int? _selectedExamId;
  String? _selectedClassId;
  String? _selectedMainDeptId;
  String? _selectedSubDeptId;
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _results = [];
  List<GradingRule> _gradingRules = [];
  bool _loadingClasses = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<ExamBloc>();
    _selectedExamId = bloc.lastResultsExamId;
    _selectedClassId = bloc.lastResultsClassId;
    _results = bloc.lastLoadedResults;
    _loadClassesAndDepartments();
    _loadGradingRules();
  }

  Future<void> _loadGradingRules() async {
    final rules = await GradingHelper.getRules();
    if (!mounted) return;
    setState(() => _gradingRules = rules);
  }

  Future<void> _loadClassesAndDepartments() async {
    try {
      final repo = AcademicRepository(ApiClient());
      final results = await Future.wait([
        repo.getAcademicHierarchy(),
        repo.getAllDepartments(),
      ]);
      if (!mounted) return;
      setState(() {
        _classes = List<Map<String, dynamic>>.from(results[0] as List);
        _departments = List<Map<String, dynamic>>.from(results[1] as List);
        _loadingClasses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingClasses = false);
    }
  }

  List<Map<String, dynamic>> get _mainDepts =>
      _departments.where((d) => d['parent_id'] == null).toList();

  List<Map<String, dynamic>> get _subDeptsForSelectedMain {
    if (_selectedMainDeptId == null) {
      return _departments.where((d) => d['parent_id'] != null).toList();
    }
    return _departments
        .where((d) => d['parent_id']?.toString() == _selectedMainDeptId)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredClasses {
    return _classes.where((c) {
      final classDeptId = c['department_id']?.toString();
      final classParentDeptId = c['department_parent_id']?.toString();

      if (_selectedSubDeptId != null) {
        return classDeptId == _selectedSubDeptId;
      }
      if (_selectedMainDeptId != null) {
        return classDeptId == _selectedMainDeptId ||
            classParentDeptId == _selectedMainDeptId;
      }
      return true;
    }).toList();
  }

  Color _percentageColor(double pct) {
    if (pct >= 80) return AppTheme.successColor;
    if (pct >= 60) return AppTheme.primaryColor;
    if (pct >= 33) return Colors.orange;
    return Colors.red;
  }

  Future<void> _openResultCardDesigner([Map<String, dynamic>? singleStudentResult]) async {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('exams_marksheet_print')) {
      UpgradePlanDialog.show(context, highlightModule: 'Marksheet & Result Card Print');
      return;
    }

    try {
      final studentRepo = StudentRepository(ApiClient());
      final allStudents = await studentRepo.getAllStudents();

      Student? targetStudent;
      if (singleStudentResult != null) {
        final targetId = singleStudentResult['student_id']?.toString() ?? '';
        final targetGr = singleStudentResult['registration_number']?.toString() ?? '';
        final found = allStudents.where((s) => s.id == targetId || s.grNo == targetGr || s.registrationNumber == targetGr);
        if (found.isNotEmpty) {
          targetStudent = found.first;
        } else {
          targetStudent = Student(
            id: targetId,
            fullName: singleStudentResult['student_name'] ?? singleStudentResult['full_name'] ?? 'Student',
            grNo: targetGr,
            registrationNumber: targetGr,
            className: singleStudentResult['class_name'] ?? '',
          );
        }
      } else if (allStudents.isNotEmpty) {
        if (_results.isNotEmpty) {
          final firstR = _results.first;
          final targetId = firstR['student_id']?.toString() ?? '';
          final targetGr = firstR['registration_number']?.toString() ?? '';
          final found = allStudents.where((s) => s.id == targetId || s.grNo == targetGr || s.registrationNumber == targetGr);
          if (found.isNotEmpty) {
            targetStudent = found.first;
          }
        }
        targetStudent ??= allStudents.first;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResultCardDesignerScreen(
              student: targetStudent,
              allStudents: allStudents,
              examResults: _results,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening Result Card Designer: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showExportOptionsDialog() async {
    final licenseState = context.read<LicenseCubit>().state;
    final license = licenseState is LicenseLoaded ? licenseState.license : AppLicense.defaultTrial();
    if (!license.hasFeatureAccess('exams_marksheet_print')) {
      UpgradePlanDialog.show(context, highlightModule: 'Marksheet & Result Card Print');
      return;
    }

    if (_results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No results loaded to export. Please load results first.')),
      );
      return;
    }

    final examName = widget.exams
        .firstWhere(
          (e) => e.id == _selectedExamId,
          orElse: () => Exam(id: 0, name: 'Exam'),
        )
        .name;

    String classFull;
    if (_selectedClassId == 'ALL' || _selectedClassId == null) {
      classFull = 'All Classes (تمام جماعتیں)';
    } else {
      final selectedClassObj = _classes.where(
        (c) => c['id']?.toString() == _selectedClassId,
      ).firstOrNull;
      final className = selectedClassObj?['name']?.toString() ?? 'Class';
      final deptName = selectedClassObj?['department_name']?.toString();
      final parentDept = selectedClassObj?['parent_department_name']?.toString();
      classFull = className;
      if (parentDept != null && parentDept.isNotEmpty && deptName != null && deptName.isNotEmpty) {
        classFull = '$className ($parentDept • $deptName)';
      } else if (deptName != null && deptName.isNotEmpty) {
        classFull = '$className ($deptName)';
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.file_download_rounded, color: AppTheme.primaryColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Save Result Sheet',
                      style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Exam: $examName | Class: $classFull',
                      style: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Direct PDF Save
                _buildExportTile(
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: Colors.redAccent,
                  title: 'Save as PDF (پی ڈی ایف محفوظ کریں)',
                  subtitle: 'Directly choose save location on your PC to store PDF',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final path = await ExamResultExportService.saveResultsPdfDirect(
                        examName: examName,
                        className: classFull,
                        results: _results,
                        gradingRules: _gradingRules,
                      );
                      if (path != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('PDF successfully saved: $path'),
                            backgroundColor: AppTheme.successColor,
                            action: SnackBarAction(
                              label: 'Open Folder',
                              textColor: Colors.white,
                              onPressed: () {
                                if (Platform.isWindows) {
                                  Process.run('explorer.exe', ['/select,', path]);
                                } else if (Platform.isMacOS) {
                                  Process.run('open', ['-R', path]);
                                }
                              },
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error generating PDF: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),

                // 2. Direct Excel / CSV Export
                _buildExportTile(
                  icon: Icons.table_view_rounded,
                  iconColor: Colors.green,
                  title: 'Export to Excel / CSV (ایکسل شیٹ محفوظ کریں)',
                  subtitle: 'Includes GR No, Student Name, Book Marks, Total, %, Grade & Rank',
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      final path = await ExamResultExportService.exportResultsToExcel(
                        examName: examName,
                        className: classFull,
                        results: _results,
                        gradingRules: _gradingRules,
                      );
                      if (path != null && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Excel / CSV successfully saved: $path'),
                            backgroundColor: AppTheme.successColor,
                            action: SnackBarAction(
                              label: 'Open Folder',
                              textColor: Colors.white,
                              onPressed: () {
                                if (Platform.isWindows) {
                                  Process.run('explorer.exe', ['/select,', path]);
                                } else if (Platform.isMacOS) {
                                  Process.run('open', ['-R', path]);
                                }
                              },
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error exporting Excel: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
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
        );
      },
    );
  }

  Widget _buildExportTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A44) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.getFontStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredClasses;

    return BlocListener<ExamBloc, ExamState>(
      listener: (context, state) {
        if (state is ResultsLoaded) {
          setState(() => _results = state.results);
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('results_report'),
              style: AppTheme.getFontStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ── Selectors ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark ? const Color(0xFF1E1E32) : Colors.white,
                border:
                    Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  // Row 1: Exam + Main Dept + Sub Dept
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: (widget.exams.any((e) => e.id == _selectedExamId))
                              ? _selectedExamId
                              : null,
                          decoration: InputDecoration(
                            labelText: context.tr('select_exam'),
                            prefixIcon:
                                const Icon(Icons.event_note_rounded, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: widget.exams
                              .map((e) => DropdownMenuItem(
                                  value: e.id, child: Text(e.name, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedExamId = v;
                              _selectedClassId = null;
                              _results = [];
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedMainDeptId,
                          decoration: InputDecoration(
                            labelText: 'Main Department',
                            prefixIcon: const Icon(Icons.business_center_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Departments', style: TextStyle(fontSize: 12)),
                            ),
                            ..._mainDepts.map((d) => DropdownMenuItem<String?>(
                                  value: d['id']?.toString(),
                                  child: Text(d['name']?.toString() ?? 'Dept', style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedMainDeptId = v;
                              _selectedSubDeptId = null;
                              _selectedClassId = null;
                              _results = [];
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedSubDeptId,
                          decoration: InputDecoration(
                            labelText: 'Sub-Department',
                            prefixIcon: const Icon(Icons.subdirectory_arrow_right_rounded, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Sub-Depts', style: TextStyle(fontSize: 12)),
                            ),
                            ..._subDeptsForSelectedMain.map((d) => DropdownMenuItem<String?>(
                                  value: d['id']?.toString(),
                                  child: Text(d['name']?.toString() ?? 'Sub-Dept', style: const TextStyle(fontSize: 12)),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedSubDeptId = v;
                              _selectedClassId = null;
                              _results = [];
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Row 2: Class Dropdown + Load Button
                  Row(
                    children: [
                      Expanded(
                        child: _loadingClasses
                            ? const Center(
                                child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2)))
                            : DropdownButtonFormField<String>(
                                value: (_selectedClassId == 'ALL' || filtered.any(
                                        (cls) => cls['id']?.toString() == _selectedClassId))
                                    ? _selectedClassId
                                    : null,
                                decoration: InputDecoration(
                                  labelText: context.tr('select_class'),
                                  prefixIcon:
                                      const Icon(Icons.class_rounded, size: 20),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                items: [
                                  DropdownMenuItem<String>(
                                    value: 'ALL',
                                    child: Text(
                                      '⭐ All Classes (تمام جماعتیں - مکمل گزٹ)',
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                  ),
                                  ...filtered.map((cls) {
                                    final cName = cls['name']?.toString() ?? 'Unknown';
                                    final deptName = cls['department_name']?.toString();
                                    final pDept = cls['parent_department_name']?.toString();
                                    String badge = '';
                                    if (pDept != null && pDept.isNotEmpty && deptName != null && deptName.isNotEmpty) {
                                      badge = ' ($pDept • $deptName)';
                                    } else if (deptName != null && deptName.isNotEmpty) {
                                      badge = ' ($deptName)';
                                    }

                                    return DropdownMenuItem(
                                      value: cls['id']?.toString() ?? '',
                                      child: Text(
                                        '$cName$badge',
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.getFontStyle(fontSize: 13),
                                      ),
                                    );
                                  }),
                                ],
                                onChanged: (v) {
                                  setState(() {
                                    _selectedClassId = v;
                                    _results = [];
                                  });
                                },
                              ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_selectedExamId != null &&
                                  _selectedClassId != null)
                              ? () {
                                  context.read<ExamBloc>().add(LoadResults(
                                      examId: _selectedExamId!,
                                      classId: _selectedClassId!));
                                }
                              : null,
                          icon: const Icon(Icons.search, color: Colors.white),
                          label: Text(
                            context.tr('load_results'),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_results.isEmpty)
              Expanded(
                child: Center(
                  child: _EmptyState(
                    icon: Icons.assessment_rounded,
                    label: context.tr('no_results'),
                    subtitle: context.tr('no_results_subtitle'),
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Text('${_results.length} ${context.tr('students')}',
                            style: AppTheme.getFontStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F766E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: () => _openResultCardDesigner(),
                              icon: const Icon(Icons.design_services_rounded, color: Colors.white, size: 18),
                              label: const Text(
                                'Result Card Designer',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: _showExportOptionsDialog,
                              icon: const Icon(Icons.file_download_rounded, color: Colors.white, size: 18),
                              label: const Text(
                                'Save Result Sheet (PDF / Excel)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final r = _results[index];
                          final pct = (r['percentage'] as double? ?? 0.0);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    _percentageColor(pct).withAlpha(25),
                                child: Text(
                                  '#${r['rank'] ?? (index + 1)}',
                                  style: TextStyle(
                                    color: _percentageColor(pct),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(r['student_name'] ?? 'Student'),
                              subtitle: Text(
                                  'GR: ${r['registration_number']} | Class: ${r['class_name']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${pct.toStringAsFixed(1)}%',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _percentageColor(pct),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.badge_rounded, color: Color(0xFF0F766E), size: 22),
                                    tooltip: 'Open in Result Card Designer',
                                    onPressed: () => _openResultCardDesigner(r),
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
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  EMPTY STATE WIDGET

// ═══════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryColor.withAlpha(15),
              ),
              child: Icon(
                icon,
                size: 36,
                color: AppTheme.primaryColor.withAlpha(150),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTheme.getFontStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTheme.getFontStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
