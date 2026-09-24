import 'package:equatable/equatable.dart';
import '../../data/models/exam_models.dart';

abstract class ExamEvent extends Equatable {
  const ExamEvent();
  @override
  List<Object?> get props => [];
}

// ─── Data Loading ──────────────────────────────────────────────
class LoadExamsData extends ExamEvent {}

class LoadSchedules extends ExamEvent {
  final int examId;
  const LoadSchedules(this.examId);
  @override
  List<Object?> get props => [examId];
}

// ─── Exam CRUD ─────────────────────────────────────────────────
class CreateExam extends ExamEvent {
  final Exam exam;
  const CreateExam(this.exam);
  @override
  List<Object?> get props => [exam];
}

class UpdateExam extends ExamEvent {
  final Exam exam;
  const UpdateExam(this.exam);
  @override
  List<Object?> get props => [exam];
}

class DeleteExam extends ExamEvent {
  final int examId;
  const DeleteExam(this.examId);
  @override
  List<Object?> get props => [examId];
}

// ─── Schedule CRUD ─────────────────────────────────────────────
class CreateExamSchedule extends ExamEvent {
  final ExamSchedule schedule;
  const CreateExamSchedule(this.schedule);
  @override
  List<Object?> get props => [schedule];
}

class UpdateExamSchedule extends ExamEvent {
  final ExamSchedule schedule;
  const UpdateExamSchedule(this.schedule);
  @override
  List<Object?> get props => [schedule];
}

class DeleteExamSchedule extends ExamEvent {
  final int scheduleId;
  final int examId;
  const DeleteExamSchedule(this.scheduleId, this.examId);
  @override
  List<Object?> get props => [scheduleId, examId];
}

// ─── Hall CRUD ─────────────────────────────────────────────────
class CreateExamHall extends ExamEvent {
  final ExamHall hall;
  const CreateExamHall(this.hall);
  @override
  List<Object?> get props => [hall];
}

class UpdateExamHall extends ExamEvent {
  final ExamHall hall;
  const UpdateExamHall(this.hall);
  @override
  List<Object?> get props => [hall];
}

class DeleteExamHall extends ExamEvent {
  final int hallId;
  const DeleteExamHall(this.hallId);
  @override
  List<Object?> get props => [hallId];
}

// ─── Seating ───────────────────────────────────────────────────
class GenerateSeating extends ExamEvent {
  final int examId;
  final int hallId;
  final String sessionDate;
  final String sessionTime;
  final List<Map<String, dynamic>> students;
  final List<String>? classIds;
  final List<String>? bookIds;
  /// Per-class student count limits: classId → max count
  final Map<String, int>? classStudentCounts;
  /// Per-book student count limits: bookId → max count
  final Map<String, int>? bookStudentCounts;

  const GenerateSeating({
    required this.examId,
    required this.hallId,
    required this.sessionDate,
    required this.sessionTime,
    required this.students,
    this.classIds,
    this.bookIds,
    this.classStudentCounts,
    this.bookStudentCounts,
  });

  @override
  List<Object?> get props => [
        examId,
        hallId,
        sessionDate,
        sessionTime,
        classIds,
        bookIds,
        classStudentCounts,
        bookStudentCounts,
      ];
}

class SaveSeating extends ExamEvent {
  final int examId;
  const SaveSeating(this.examId);
  @override
  List<Object?> get props => [examId];
}

class LoadSeating extends ExamEvent {
  final int examId;
  final int? hallId;
  final String? sessionDate;
  const LoadSeating(this.examId, {this.hallId, this.sessionDate});
  @override
  List<Object?> get props => [examId, hallId, sessionDate];
}

class ClearSeating extends ExamEvent {
  final int examId;
  final int? hallId;
  final String? sessionDate;
  final String? classId;
  final List<String>? bookIds;
  const ClearSeating(this.examId, {this.hallId, this.sessionDate, this.classId, this.bookIds});
  @override
  List<Object?> get props => [examId, hallId, sessionDate, classId, bookIds];
}

class LoadSavedSeating extends ExamEvent {
  final int examId;
  final int hallId;
  final String? sessionDate;
  const LoadSavedSeating(this.examId, this.hallId, {this.sessionDate});
  @override
  List<Object?> get props => [examId, hallId, sessionDate];
}

// ─── Marks ─────────────────────────────────────────────────────
class LoadMarks extends ExamEvent {
  final int scheduleId;
  const LoadMarks(this.scheduleId);
  @override
  List<Object?> get props => [scheduleId];
}

class InitMarksForSchedule extends ExamEvent {
  final int examId;
  final int scheduleId;
  final ExamSchedule schedule;
  final List<Map<String, dynamic>> students;
  const InitMarksForSchedule({
    required this.examId,
    required this.scheduleId,
    required this.schedule,
    required this.students,
  });
  @override
  List<Object?> get props => [examId, scheduleId];
}

class SaveMarks extends ExamEvent {
  final List<ExamMark> marks;
  const SaveMarks(this.marks);
  @override
  List<Object?> get props => [marks];
}

// ─── Results ───────────────────────────────────────────────────
class LoadResults extends ExamEvent {
  final int examId;
  final String classId;
  const LoadResults({required this.examId, required this.classId});
  @override
  List<Object?> get props => [examId, classId];
}
