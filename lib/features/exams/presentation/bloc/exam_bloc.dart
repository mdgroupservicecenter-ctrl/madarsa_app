import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'exam_event.dart';
import 'exam_state.dart';
import '../../data/repositories/exam_local_repository.dart';
import '../../data/models/exam_models.dart';
import '../../data/algorithm/seating_algorithm.dart';
import '../../data/algorithm/seating_models.dart';
import '../../../students/data/repositories/student_repository.dart';
import '../../../students/data/models/student_model.dart';
import '../../../classes/data/repositories/academic_repository.dart';

class ExamBloc extends Bloc<ExamEvent, ExamState> {
  final ExamLocalRepository _repo;
  final SeatingAlgorithm _algorithm = SeatingAlgorithm();

  // Cached data for tab switches
  List<Exam> _cachedExams = [];
  List<ExamHall> _cachedHalls = [];
  final Map<int, List<ExamSchedule>> _cachedSchedulesMap = {};

  // Cached seating for persistence across tab switches
  SeatingResult? lastGeneratedSeating;
  ExamHall? lastGeneratedHall;
  int? lastSeatingExamId;
  String? lastSeatingDate;
  String? lastSeatingTime;

  // Cached marks entry selections
  int? lastMarksExamId;
  int? lastMarksScheduleId;
  List<ExamMark> lastLoadedMarks = [];

  // Cached results selections
  int? lastResultsExamId;
  String? lastResultsClassId;
  List<Map<String, dynamic>> lastLoadedResults = [];

  // Pending seating for save
  SeatingResult? _pendingSeating;
  int? _pendingExamId;
  int? _pendingHallId;
  String? _pendingSessionDate;
  String? _pendingSessionTime;
  List<String>? _pendingBookIds;

  bool _hasAnyBookTag(Map<String, dynamic> s) {
    final bId = '${s['book_id'] ?? s['bookId'] ?? s['book']?['id'] ?? s['subject_id'] ?? ''}'.trim();
    final bName = '${s['book_name'] ?? s['bookName'] ?? s['book']?['name'] ?? s['subject'] ?? s['subject_name'] ?? s['course'] ?? s['course_name'] ?? ''}'.trim();
    final hasBooksList = s['books'] != null && s['books'] is List && (s['books'] as List).isNotEmpty;
    final hasSubjectsList = s['subjects'] != null && s['subjects'] is List && (s['subjects'] as List).isNotEmpty;
    final cat = '${s['category'] ?? s['student_category'] ?? ''}'.trim();
    return bId.isNotEmpty || bName.isNotEmpty || hasBooksList || hasSubjectsList || cat.isNotEmpty;
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
        .replaceAll('\u0622', 'ا')
        .replaceAll('\u0653', '')
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

  bool _studentMatchesBook(Map<String, dynamic> s, String bookId, String? bookName, [Map<String, Map<String, String>>? classBookCategoryMap]) {
    final sClassId = '${s['class_id'] ?? s['class']?['id'] ?? ''}'.trim().toLowerCase();
    final sClassName = '${s['class_name'] ?? s['class']?['name'] ?? s['className'] ?? ''}'.trim().toLowerCase();

    final bIdLow = bookId.trim().toLowerCase();
    final bNameLow = (bookName ?? '').trim().toLowerCase();
    final normBName = _normalizeUrdu(bNameLow);

    // 1. Explicit book_id / book_name / subject / course check on student object
    final sBookId = '${s['book_id'] ?? s['bookId'] ?? s['book']?['id'] ?? s['subject_id'] ?? ''}'.trim().toLowerCase();
    final sBookName = '${s['book_name'] ?? s['bookName'] ?? s['book']?['name'] ?? s['subject'] ?? s['subject_name'] ?? s['course'] ?? s['course_name'] ?? ''}'.trim().toLowerCase();
    final normSBookName = _normalizeUrdu(sBookName);

    if (bIdLow.isNotEmpty) {
      if (sBookId == bIdLow || sBookName == bIdLow || normSBookName == normBName) return true;
    }
    if (bNameLow.isNotEmpty) {
      if (sBookId == bNameLow || sBookName == bNameLow || normSBookName == normBName) return true;
      if (normSBookName.isNotEmpty && (normSBookName.contains(normBName) || normBName.contains(normSBookName))) return true;
    }

    if (s['books'] != null && s['books'] is List) {
      for (final b in s['books']) {
        final name = '${b['name'] ?? b['book_name'] ?? b['title'] ?? b}'.trim().toLowerCase();
        final id = '${b['id'] ?? b['book_id'] ?? b}'.trim().toLowerCase();
        final normName = _normalizeUrdu(name);
        if (bIdLow.isNotEmpty && (id == bIdLow || name == bIdLow || normName == normBName)) return true;
        if (bNameLow.isNotEmpty && (id == bNameLow || name == bNameLow || normName == normBName || normName.contains(normBName) || normBName.contains(normName))) return true;
      }
    }

    if (s['subjects'] != null && s['subjects'] is List) {
      for (final sub in s['subjects']) {
        final name = '${sub['name'] ?? sub['subject_name'] ?? sub['title'] ?? sub}'.trim().toLowerCase();
        final id = '${sub['id'] ?? sub['subject_id'] ?? sub}'.trim().toLowerCase();
        final normName = _normalizeUrdu(name);
        if (bIdLow.isNotEmpty && (id == bIdLow || name == bIdLow || normName == normBName)) return true;
        if (bNameLow.isNotEmpty && (id == bNameLow || name == bNameLow || normName == normBName || normName.contains(normBName) || normBName.contains(normName))) return true;
      }
    }

    // 2. Academic Hierarchy Class & Category Matching
    if (classBookCategoryMap != null) {
      Map<String, String>? classBooks;
      for (final entry in classBookCategoryMap.entries) {
        final normEntryKey = _normalizeUrdu(entry.key);
        if (normEntryKey == _normalizeUrdu(sClassName) || normEntryKey == _normalizeUrdu(sClassId) || entry.key == sClassName || entry.key == sClassId) {
          classBooks = entry.value;
          break;
        }
      }

      if (classBooks != null) {
        bool hasBookInClass = classBooks.containsKey(bIdLow) || classBooks.containsKey(bNameLow);
        String bookCategory = (classBooks[bIdLow] ?? classBooks[bNameLow] ?? '').trim().toLowerCase();

        if (!hasBookInClass && normBName.isNotEmpty) {
          for (final entry in classBooks.entries) {
            final normKey = _normalizeUrdu(entry.key);
            if (normKey == normBName || normKey.contains(normBName) || normBName.contains(normKey)) {
              hasBookInClass = true;
              bookCategory = entry.value.trim().toLowerCase();
              break;
            }
          }
        }

        if (!hasBookInClass) {
          return false;
        }

        final studentCategory = '${s['category'] ?? s['student_category'] ?? ''}'.trim().toLowerCase();

        if (bookCategory.isEmpty) {
          return true;
        }

        if (studentCategory.isNotEmpty && (studentCategory == bookCategory || _normalizeUrdu(studentCategory) == _normalizeUrdu(bookCategory))) {
          return true;
        }
        return false;
      }
    }

    return false;
  }

  ExamBloc(this._repo) : super(ExamInitial()) {
    on<LoadExamsData>(_onLoadExamsData);
    on<LoadSchedules>(_onLoadSchedules);
    on<CreateExam>(_onCreateExam);
    on<UpdateExam>(_onUpdateExam);
    on<DeleteExam>(_onDeleteExam);
    on<CreateExamSchedule>(_onCreateSchedule);
    on<UpdateExamSchedule>(_onUpdateSchedule);
    on<DeleteExamSchedule>(_onDeleteSchedule);
    on<CreateExamHall>(_onCreateHall);
    on<UpdateExamHall>(_onUpdateHall);
    on<DeleteExamHall>(_onDeleteHall);
    on<GenerateSeating>(_onGenerateSeating);
    on<SaveSeating>(_onSaveSeating);
    on<LoadSeating>(_onLoadSeating);
    on<ClearSeating>(_onClearSeating);
    on<LoadSavedSeating>(_onLoadSavedSeating);
    on<LoadMarks>(_onLoadMarks);
    on<InitMarksForSchedule>(_onInitMarks);
    on<SaveMarks>(_onSaveMarks);
    on<LoadResults>(_onLoadResults);
  }

  // ─── Data Loading ────────────────────────────────────────────

  Future<void> _onLoadExamsData(LoadExamsData event, Emitter<ExamState> emit) async {
    emit(ExamLoading());
    try {
      _cachedExams = await _repo.getExams();
      _cachedHalls = await _repo.getHalls();
      _cachedSchedulesMap.clear();

      for (final exam in _cachedExams) {
        if (exam.id != null) {
          final sList = await _repo.getSchedules(exam.id!);
          _cachedSchedulesMap[exam.id!] = sList;
        }
      }
      
      if (_cachedExams.isNotEmpty && _cachedExams.first.id != null) {
        final firstExamId = _cachedExams.first.id!;
        final schedules = _cachedSchedulesMap[firstExamId] ?? [];
        emit(SchedulesLoaded(
          examId: firstExamId,
          schedules: schedules,
          exams: _cachedExams,
          halls: _cachedHalls,
          schedulesMap: Map.from(_cachedSchedulesMap),
        ));
      } else {
        emit(ExamLoaded(_cachedExams, _cachedHalls, schedulesMap: Map.from(_cachedSchedulesMap)));
      }
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onLoadSchedules(LoadSchedules event, Emitter<ExamState> emit) async {
    try {
      final schedules = await _repo.getSchedules(event.examId);
      _cachedSchedulesMap[event.examId] = schedules;
      emit(SchedulesLoaded(
        examId: event.examId,
        schedules: schedules,
        exams: _cachedExams,
        halls: _cachedHalls,
        schedulesMap: Map.from(_cachedSchedulesMap),
      ));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Exam CRUD ───────────────────────────────────────────────

  Future<void> _onCreateExam(CreateExam event, Emitter<ExamState> emit) async {
    try {
      await _repo.createExam(event.exam);
      emit(const ExamOperationSuccess('Exam created successfully.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onUpdateExam(UpdateExam event, Emitter<ExamState> emit) async {
    try {
      await _repo.updateExam(event.exam);
      emit(const ExamOperationSuccess('Exam updated.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onDeleteExam(DeleteExam event, Emitter<ExamState> emit) async {
    try {
      await _repo.deleteExam(event.examId);
      emit(const ExamOperationSuccess('Exam deleted.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Schedule CRUD ───────────────────────────────────────────

  Future<void> _onCreateSchedule(CreateExamSchedule event, Emitter<ExamState> emit) async {
    try {
      await _repo.createSchedule(event.schedule);
      emit(const ExamOperationSuccess('Schedule added.'));
      final updatedSchedules = await _repo.getSchedules(event.schedule.examId);
      _cachedSchedulesMap[event.schedule.examId] = updatedSchedules;
      emit(SchedulesLoaded(
        examId: event.schedule.examId,
        schedules: updatedSchedules,
        exams: _cachedExams,
        halls: _cachedHalls,
        schedulesMap: Map.from(_cachedSchedulesMap),
      ));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onUpdateSchedule(UpdateExamSchedule event, Emitter<ExamState> emit) async {
    try {
      await _repo.updateSchedule(event.schedule);
      emit(const ExamOperationSuccess('Schedule updated.'));
      final updatedSchedules = await _repo.getSchedules(event.schedule.examId);
      _cachedSchedulesMap[event.schedule.examId] = updatedSchedules;
      emit(SchedulesLoaded(
        examId: event.schedule.examId,
        schedules: updatedSchedules,
        exams: _cachedExams,
        halls: _cachedHalls,
        schedulesMap: Map.from(_cachedSchedulesMap),
      ));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onDeleteSchedule(DeleteExamSchedule event, Emitter<ExamState> emit) async {
    try {
      await _repo.deleteSchedule(event.scheduleId);
      emit(const ExamOperationSuccess('Schedule deleted.'));
      final updatedSchedules = await _repo.getSchedules(event.examId);
      _cachedSchedulesMap[event.examId] = updatedSchedules;
      emit(SchedulesLoaded(
        examId: event.examId,
        schedules: updatedSchedules,
        exams: _cachedExams,
        halls: _cachedHalls,
        schedulesMap: Map.from(_cachedSchedulesMap),
      ));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Hall CRUD ───────────────────────────────────────────────

  Future<void> _onCreateHall(CreateExamHall event, Emitter<ExamState> emit) async {
    try {
      await _repo.createHall(event.hall);
      emit(const ExamOperationSuccess('Hall created.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onUpdateHall(UpdateExamHall event, Emitter<ExamState> emit) async {
    try {
      await _repo.updateHall(event.hall);
      emit(const ExamOperationSuccess('Hall updated.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onDeleteHall(DeleteExamHall event, Emitter<ExamState> emit) async {
    try {
      await _repo.deleteHall(event.hallId);
      emit(const ExamOperationSuccess('Hall deleted.'));
      add(LoadExamsData());
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Seating ─────────────────────────────────────────────────

  Future<void> _onGenerateSeating(GenerateSeating event, Emitter<ExamState> emit) async {
    emit(ExamLoading());
    try {
      final hall = _cachedHalls.firstWhere((h) => h.id == event.hallId);

      // Get schedules for this exam + session date
      var schedules = await _repo.getSchedulesByDate(event.examId, event.sessionDate);

      // Fallback: If no schedules match exact session date, load all schedules for this exam
      if (schedules.isEmpty) {
        schedules = await _repo.getSchedules(event.examId);
      }

      // Filter schedules by classIds and bookIds if specified
      if (event.classIds != null) {
        schedules = schedules.where((s) {
          final sId = s.classId.trim().toLowerCase();
          final sName = (s.className ?? '').trim().toLowerCase();
          return event.classIds!.any((cId) {
            final target = cId.trim().toLowerCase();
            return target == sId || target == sName;
          });
        }).toList();
      }

      if (event.bookIds != null) {
        schedules = schedules.where((s) {
          final bId = s.bookId.trim().toLowerCase();
          final bName = (s.bookName ?? '').trim().toLowerCase();
          return event.bookIds!.any((bIdParam) {
            final target = bIdParam.trim().toLowerCase();
            return target == bId || target == bName;
          });
        }).toList();
      }

      if (schedules.isEmpty) {
        emit(const ExamError('No schedules found matching your selected class/book filters.'));
        return;
      }

      // Query ALL existing saved seating for this exam
      final existingArrangements = await _repo.getSeating(event.examId);

      // Check seats already saved in THIS hall for this session date & time
      final savedInThisHall = existingArrangements.where((a) =>
        a.hallId == event.hallId &&
        (event.sessionDate.isEmpty || a.sessionDate == event.sessionDate) &&
        (event.sessionTime.isEmpty || a.sessionTime == event.sessionTime)
      ).toList();

      final usedSeatsCount = savedInThisHall.length;
      final totalCapacity = hall.totalRows * hall.totalColumns;
      final remainingCapacity = totalCapacity - usedSeatsCount;

      if (remainingCapacity <= 0) {
        emit(ExamError('Hall "${hall.name}" is completely full ($usedSeatsCount/$totalCapacity seats filled). Please select another hall or clear seating.'));
        return;
      }

      // Pre-fill initialGrid with savedInThisHall
      final initialGrid = List<List<SeatAssignment?>>.generate(
        hall.totalRows,
        (_) => List.filled(hall.totalColumns, null),
      );

      for (final arr in savedInThisHall) {
        if (arr.seatRow >= 0 && arr.seatRow < hall.totalRows &&
            arr.seatColumn >= 0 && arr.seatColumn < hall.totalColumns) {
          initialGrid[arr.seatRow][arr.seatColumn] = SeatAssignment(
            student: StudentSeatInput(
              studentId: arr.studentId,
              studentName: arr.studentName ?? 'Student',
              registrationNumber: arr.registrationNumber ?? '',
              rollNumber: arr.rollNumber,
              classId: arr.classId,
              className: arr.className ?? '',
              bookId: arr.bookId,
              bookName: arr.bookName ?? '',
            ),
            seat: SeatPosition(
              row: arr.seatRow,
              col: arr.seatColumn,
              seatNumber: arr.seatNumber,
            ),
            method: 'SAVED_LOCKED',
          );
        }
      }

      // Students already saved in ANY hall for THIS SPECIFIC SESSION DATE & TIME are excluded
      final alreadySavedStudentIds = <String>{};
      for (final arr in existingArrangements) {
        bool sameDate = event.sessionDate.isEmpty || arr.sessionDate == event.sessionDate;
        bool sameTime = event.sessionTime.isEmpty || arr.sessionTime == event.sessionTime;
        if (sameDate && sameTime) {
          alreadySavedStudentIds.add(arr.studentId);
        }
      }

      final classBookCategoryMap = <String, Map<String, String>>{};
      try {
        final res = await ApiClient().get('/academic/hierarchy');
        if (res.data is List) {
          for (var cls in (res.data as List)) {
            final cId = '${cls['id'] ?? ''}'.trim().toLowerCase();
            final cName = '${cls['name'] ?? ''}'.trim().toLowerCase();

            final booksForClass = <String, String>{};
            final courses = cls['courses'] as List? ?? [];
            for (var crs in courses) {
              final crsBooks = crs['books'] as List? ?? [];
              for (var b in crsBooks) {
                final bId = '${b['id'] ?? ''}'.trim().toLowerCase();
                final bName = '${b['name'] ?? ''}'.trim().toLowerCase();
                final bCat = '${b['category'] ?? ''}'.trim();
                if (bId.isNotEmpty) booksForClass[bId] = bCat;
                if (bName.isNotEmpty) booksForClass[bName] = bCat;
              }
            }

            if (cId.isNotEmpty) classBookCategoryMap[cId] = booksForClass;
            if (cName.isNotEmpty) classBookCategoryMap[cName] = booksForClass;
          }
        }
      } catch (e) {
        debugPrint('ExamBloc: Could not fetch academic hierarchy: $e');
      }

      // Per-class counters for classStudentCounts limit
      final perClassCounter = <String, int>{};
      // Per-book counters for bookStudentCounts limit
      final perBookCounter = <String, int>{};

      // Build student inputs from provided students list
      final studentInputs = <StudentSeatInput>[];
      final addedStudentIds = <String>{};

      if (event.students.isNotEmpty) {
        for (final s in event.students) {
          final sId = '${s['id']}';
          if (addedStudentIds.contains(sId)) continue;
          if (alreadySavedStudentIds.contains(sId)) continue;

          final name = '${s['full_name'] ?? s['fullName'] ?? s['student_name'] ?? s['first_name'] ?? s['name'] ?? ''}'.trim();
          final father = '${s['father_name'] ?? s['fatherName'] ?? ''}'.trim();
          final surname = '${s['surname'] ?? s['last_name'] ?? s['lastName'] ?? ''}'.trim();

          final parts = <String>[];
          if (name.isNotEmpty) parts.add(name);
          if (father.isNotEmpty && !name.contains(father)) parts.add(father);
          if (surname.isNotEmpty && !name.contains(surname)) parts.add(surname);

          final fullName = parts.join(' ').trim();
          final grNo = '${s['registration_number'] ?? s['registrationNo'] ?? s['gr_no'] ?? s['grNo'] ?? s['id'] ?? ''}'.trim();
          final rollNo = '${s['roll_number'] ?? s['rollNo'] ?? ''}'.trim();

          addedStudentIds.add(sId);
          studentInputs.add(StudentSeatInput(
            studentId: sId,
            studentName: fullName.isNotEmpty ? fullName : 'Student',
            registrationNumber: grNo.isNotEmpty ? grNo : '-',
            rollNumber: rollNo.isNotEmpty ? rollNo : null,
            classId: '${s['class_id'] ?? s['class_name'] ?? ''}',
            className: s['class_name'] ?? s['class_id'] ?? '',
            bookId: '${s['book_id'] ?? s['book_name'] ?? ''}',
            bookName: s['book_name'] ?? s['book_id'] ?? '',
            meritScore: s['merit_score'] != null ? (s['merit_score'] as num).toDouble() : null,
          ));
        }
      } else {
        for (final schedule in schedules) {
          final schedClassId = (schedule.classId).trim().toLowerCase();
          final schedClassName = (schedule.className ?? '').trim().toLowerCase();

          for (final s in event.students) {
            final sId = '${s['id']}';
            if (addedStudentIds.contains(sId)) continue;
            if (alreadySavedStudentIds.contains(sId)) continue;

            final sClassId = '${s['class_id'] ?? s['class']?['id'] ?? ''}'.trim().toLowerCase();
            final sClassName = '${s['class_name'] ?? s['class']?['name'] ?? s['className'] ?? ''}'.trim().toLowerCase();

            bool studentMatchesScheduleClass = false;
            if (sClassId.isNotEmpty) {
              studentMatchesScheduleClass = (sClassId == schedClassId || sClassId == schedClassName);
            }
            if (sClassName.isNotEmpty) {
              studentMatchesScheduleClass = studentMatchesScheduleClass || (sClassName == schedClassName || sClassName == schedClassId);
            }
            if (sClassId.isEmpty && sClassName.isEmpty) {
              studentMatchesScheduleClass = true;
            }

            if (!studentMatchesScheduleClass) continue;

            if (_hasAnyBookTag(s)) {
              if (!_studentMatchesBook(s, schedule.bookId, schedule.bookName, classBookCategoryMap)) continue;
            }

            addedStudentIds.add(sId);
            studentInputs.add(StudentSeatInput(
              studentId: sId,
              studentName: s['full_name'] ?? s['name'] ?? 'Student',
              registrationNumber: '${s['registration_number'] ?? s['gr_no'] ?? s['grNo'] ?? ''}',
              rollNumber: s['roll_number'] != null ? '${s['roll_number']}' : null,
              classId: schedule.classId,
              className: schedule.className ?? '',
              bookId: schedule.bookId,
              bookName: schedule.bookName ?? '',
              meritScore: s['merit_score'] != null ? (s['merit_score'] as num).toDouble() : null,
            ));
          }
        }
      }

      if (studentInputs.isEmpty) {
        final msg = alreadySavedStudentIds.isNotEmpty
            ? 'All matching students are already saved & locked. To re-generate, click "Clear Seating" first.'
            : 'No matching students found for the selected class/book filters.';
        emit(ExamError(msg));
        return;
      }

      // Bound studentInputs to remaining capacity in this hall
      List<StudentSeatInput> boundedStudentInputs = studentInputs;
      if (boundedStudentInputs.length > remainingCapacity) {
        boundedStudentInputs = boundedStudentInputs.sublist(0, remainingCapacity);
      }

      // Get seat history
      final history = await _repo.getSeatHistory(
        hallId: event.hallId,
        studentIds: boundedStudentInputs.map((s) => s.studentId).toList(),
      );

      // Run algorithm with pre-filled grid
      final result = _algorithm.generate(
        hallRows: hall.totalRows,
        hallColumns: hall.totalColumns,
        students: boundedStudentInputs,
        seatHistory: history,
        hallId: event.hallId,
        initialGrid: initialGrid,
      );

      // Cache for saving
      _pendingSeating = result;
      _pendingExamId = event.examId;
      _pendingHallId = event.hallId;
      _pendingSessionDate = event.sessionDate;
      _pendingSessionTime = event.sessionTime;
      _pendingBookIds = event.bookIds;

      // Cache for persistence across tab/page switches
      lastGeneratedSeating = result;
      lastGeneratedHall = hall;
      lastSeatingExamId = event.examId;
      lastSeatingDate = event.sessionDate;
      lastSeatingTime = event.sessionTime;

      emit(SeatingGenerated(
        result: result,
        hall: hall,
        examId: event.examId,
        sessionDate: event.sessionDate,
        sessionTime: event.sessionTime,
      ));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onSaveSeating(SaveSeating event, Emitter<ExamState> emit) async {
    if (_pendingSeating == null) {
      emit(const ExamError('No seating to save. Generate first.'));
      return;
    }
    emit(ExamLoading());
    try {
      // Filter out pre-existing SAVED_LOCKED assignments so only NEW seats are saved
      final newAssignments = _pendingSeating!.assignments
          .where((a) => a.method != 'SAVED_LOCKED')
          .toList();

      if (newAssignments.isEmpty) {
        emit(const ExamError('No new seating to save. All seats are already saved.'));
        return;
      }

      final arrangements = newAssignments.map((a) {
        return SeatingArrangement(
          examId: _pendingExamId!,
          hallId: _pendingHallId!,
          studentId: a.student.studentId,
          studentName: a.student.studentName,
          registrationNumber: a.student.registrationNumber,
          bookId: a.student.bookId,
          bookName: a.student.bookName,
          classId: a.student.classId,
          className: a.student.className,
          seatRow: a.seat.row,
          seatColumn: a.seat.col,
          seatNumber: a.seat.seatNumber,
          sessionDate: _pendingSessionDate,
          sessionTime: _pendingSessionTime,
          assignmentMethod: a.method,
        );
      }).toList();

      await _repo.saveSeatingBatch(arrangements);
      await _repo.saveSeatHistory(arrangements, _pendingExamId!);

      // Clear pending & generated cache
      _pendingSeating = null;
      lastGeneratedSeating = null;
      lastGeneratedHall = null;

      emit(const ExamOperationSuccess('Seating saved and locked successfully.'));
      // Load saved seating for dropdown viewer
      if (_pendingHallId != null) {
        add(LoadSavedSeating(event.examId, _pendingHallId!));
      } else {
        add(LoadSeating(event.examId));
      }
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onLoadSeating(LoadSeating event, Emitter<ExamState> emit) async {
    emit(ExamLoading());
    try {
      final seating = await _repo.getSeating(
        event.examId,
        hallId: event.hallId,
        sessionDate: event.sessionDate,
      );
      emit(SeatingLoaded(seating, examId: event.examId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onClearSeating(ClearSeating event, Emitter<ExamState> emit) async {
    try {
      await _repo.clearSeating(
        event.examId,
        hallId: event.hallId,
        sessionDate: event.sessionDate,
        classId: event.classId,
        bookIds: event.bookIds,
      );
      _pendingSeating = null;
      lastGeneratedSeating = null;
      lastGeneratedHall = null;

      final msg = (event.bookIds != null && event.bookIds!.isNotEmpty)
          ? 'Seating cleared for selected book.'
          : (event.classId != null && event.classId!.isNotEmpty)
              ? 'Seating cleared for selected class.'
              : 'Seating cleared successfully.';

      final remainingSaved = await _repo.getSeating(
        event.examId,
        hallId: event.hallId,
      );

      emit(ExamOperationSuccess(msg));
      emit(SavedSeatingLoaded(remainingSaved, examId: event.examId, hallId: event.hallId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onLoadSavedSeating(LoadSavedSeating event, Emitter<ExamState> emit) async {
    try {
      final saved = await _repo.getSeating(
        event.examId,
        hallId: event.hallId,
        sessionDate: event.sessionDate,
      );
      emit(SavedSeatingLoaded(saved, examId: event.examId, hallId: event.hallId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Marks ───────────────────────────────────────────────────

  Future<void> _onLoadMarks(LoadMarks event, Emitter<ExamState> emit) async {
    try {
      var marks = await _repo.getMarks(event.scheduleId);
      if (marks.isEmpty) {
        ExamSchedule? schedule;
        for (final list in _cachedSchedulesMap.values) {
          final found = list.where((s) => s.id == event.scheduleId);
          if (found.isNotEmpty) {
            schedule = found.first;
            break;
          }
        }

        if (schedule != null) {
          try {
            final studentRepo = StudentRepository(ApiClient());
            final academicRepo = AcademicRepository(ApiClient());
            final results = await Future.wait([
              studentRepo.getAllStudents(),
              academicRepo.getAcademicHierarchy(),
            ]);

            final rawStudents = (results[0] as List).map((s) => s is Map ? Map<String, dynamic>.from(s) : (s as dynamic).toJson() as Map<String, dynamic>).toList();
            final hierarchy = List<Map<String, dynamic>>.from(results[1] as List);

            final schedClass = (schedule.className ?? schedule.classId).trim();
            final schedClassId = schedule.classId.trim();
            final schedBook = (schedule.bookName ?? schedule.bookId).trim();
            final schedBookId = schedule.bookId.trim();

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
            final normClassId = norm(schedClassId);
            final normBook = norm(schedBook);
            final normBookId = norm(schedBookId);

            // Find book category from hierarchy
            String? bookCategory;
            for (final c in hierarchy) {
              final cName = norm((c['name'] ?? '').toString());
              final cId = norm((c['id'] ?? '').toString());
              if (cName == normClass || cId == normClassId) {
                final courses = c['courses'] as List? ?? [];
                for (final crs in courses) {
                  final books = crs['books'] as List? ?? [];
                  for (final b in books) {
                    final bName = norm((b['name'] ?? b['title'] ?? '').toString());
                    final bId = norm((b['id'] ?? '').toString());
                    if (bName == normBook || bId == normBookId) {
                      bookCategory = (b['category'] ?? '').toString().trim().toLowerCase();
                      break;
                    }
                  }
                }
              }
            }

            final matchingStudents = rawStudents.where((st) {
              final stClassId = norm((st['class_id'] ?? st['class']?['id'] ?? '').toString());
              final stClassName = norm((st['class_name'] ?? st['class']?['name'] ?? st['className'] ?? '').toString());

              final isClassMatch = (stClassId.isNotEmpty && (stClassId == normClass || stClassId == normClassId || normClass.contains(stClassId) || stClassId.contains(normClass))) ||
                  (stClassName.isNotEmpty && (stClassName == normClass || stClassName == normClassId || normClass.contains(stClassName) || stClassName.contains(normClass)));

              if (!isClassMatch) return false;

              final booksList = st['assigned_books'] ?? st['books'] ?? st['assigned_courses'] ?? st['courses'] ?? st['subjects'];
              if (booksList is List && booksList.isNotEmpty) {
                return booksList.any((b) {
                  if (b is Map) {
                    final id = norm((b['id'] ?? b['book_id'] ?? b['bookId'] ?? '').toString());
                    final name = norm((b['name'] ?? b['title'] ?? b['book_name'] ?? '').toString());
                    return (id.isNotEmpty && id == normBookId) ||
                        (name.isNotEmpty && (name == normBook || normBook.contains(name) || name.contains(normBook)));
                  }
                  final str = norm(b.toString());
                  return str == normBookId || str == normBook || normBook.contains(str) || str.contains(normBook);
                });
              }

              final stCategory = (st['category'] ?? '').toString().trim().toLowerCase();
              if (bookCategory != null && bookCategory.isNotEmpty) {
                return stCategory.isEmpty || stCategory == bookCategory;
              }

              return true;
            }).toList();

            if (matchingStudents.isNotEmpty) {
              await _repo.initMarksForSchedule(schedule.examId, event.scheduleId, schedule, matchingStudents);
              marks = await _repo.getMarks(event.scheduleId);
            }
          } catch (e) {
            debugPrint('Auto-init marks error: $e');
          }
        }
      }

      // If marks are missing roll_number or division, enrich them from student data
      final hasMissingDetails = marks.any((m) => m.rollNumber == null || m.division == null);
      if (hasMissingDetails) {
        try {
          final studentRepo = StudentRepository(ApiClient());
          final rawStudents = await studentRepo.getAllStudents();
          final studentMap = <String, Student>{};
          for (final st in rawStudents) {
            studentMap[st.id] = st;
          }

          ExamSchedule? schedule;
          for (final list in _cachedSchedulesMap.values) {
            final found = list.where((s) => s.id == event.scheduleId);
            if (found.isNotEmpty) {
              schedule = found.first;
              break;
            }
          }

          final updatedMarks = <ExamMark>[];
          for (final m in marks) {
            final st = studentMap[m.studentId];
            String? rollNo = m.rollNumber;
            String? div = m.division;

            if (st != null) {
              if (rollNo == null || rollNo.isEmpty) {
                if (schedule?.departmentId != null && st.subDepartments != null) {
                  for (final sd in st.subDepartments!) {
                    if (sd.subDepartmentId == schedule!.departmentId && sd.rollNumber != null && sd.rollNumber!.isNotEmpty) {
                      rollNo = sd.rollNumber;
                      div ??= sd.division;
                      break;
                    }
                  }
                }
                if ((rollNo == null || rollNo.isEmpty) && st.subDepartments != null && st.subDepartments!.isNotEmpty) {
                  for (final sd in st.subDepartments!) {
                    if (sd.rollNumber != null && sd.rollNumber!.isNotEmpty) {
                      rollNo = sd.rollNumber;
                      div ??= sd.division;
                      break;
                    }
                  }
                }
                rollNo ??= st.rollNumber;
                div ??= st.division;
              }
            }

            if (rollNo != m.rollNumber || div != m.division) {
              final newM = m.copyWith(rollNumber: rollNo, division: div);
              updatedMarks.add(newM);
            } else {
              updatedMarks.add(m);
            }
          }
          marks = updatedMarks;
          marks.sort(ExamMark.compareRollNumber);
          await _repo.saveMarksBatch(marks);
        } catch (e) {
          debugPrint('Error enriching marks with roll number / division: $e');
        }
      }

      lastLoadedMarks = marks;
      lastMarksScheduleId = event.scheduleId;
      emit(MarksLoaded(marks, scheduleId: event.scheduleId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onInitMarks(InitMarksForSchedule event, Emitter<ExamState> emit) async {
    emit(ExamLoading());
    try {
      await _repo.initMarksForSchedule(
        event.examId,
        event.scheduleId,
        event.schedule,
        event.students,
      );
      final marks = await _repo.getMarks(event.scheduleId);
      lastLoadedMarks = marks;
      lastMarksScheduleId = event.scheduleId;
      lastMarksExamId = event.examId;
      emit(MarksLoaded(marks, scheduleId: event.scheduleId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  Future<void> _onSaveMarks(SaveMarks event, Emitter<ExamState> emit) async {
    try {
      await _repo.saveMarksBatch(event.marks);
      emit(const ExamOperationSuccess('Marks saved successfully.'));
      if (event.marks.isNotEmpty) {
        add(LoadMarks(event.marks.first.scheduleId));
      }
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }

  // ─── Results ─────────────────────────────────────────────────

  Future<void> _onLoadResults(LoadResults event, Emitter<ExamState> emit) async {
    emit(ExamLoading());
    try {
      final results = await _repo.getStudentResults(event.examId, event.classId);
      lastLoadedResults = results;
      lastResultsExamId = event.examId;
      lastResultsClassId = event.classId;
      emit(ResultsLoaded(results, examId: event.examId, classId: event.classId));
    } catch (e) {
      emit(ExamError(e.toString()));
    }
  }
}
