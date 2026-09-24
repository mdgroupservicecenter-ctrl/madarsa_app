import 'package:equatable/equatable.dart';
import '../../data/models/exam_models.dart';
import '../../data/algorithm/seating_models.dart';

abstract class ExamState extends Equatable {
  const ExamState();
  @override
  List<Object?> get props => [];
}

class ExamInitial extends ExamState {}

class ExamLoading extends ExamState {}

class ExamLoaded extends ExamState {
  final List<Exam> exams;
  final List<ExamHall> halls;
  final Map<int, List<ExamSchedule>> schedulesMap;

  const ExamLoaded(this.exams, this.halls, {this.schedulesMap = const {}});
  @override
  List<Object?> get props => [exams, halls, schedulesMap];
}

class SchedulesLoaded extends ExamState {
  final int examId;
  final List<ExamSchedule> schedules;
  final List<Exam> exams;
  final List<ExamHall> halls;
  final Map<int, List<ExamSchedule>> schedulesMap;

  const SchedulesLoaded({
    required this.examId,
    required this.schedules,
    required this.exams,
    required this.halls,
    this.schedulesMap = const {},
  });
  @override
  List<Object?> get props => [examId, schedules, exams, halls, schedulesMap];
}

class ExamOperationSuccess extends ExamState {
  final String message;
  const ExamOperationSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class SeatingGenerated extends ExamState {
  final SeatingResult result;
  final ExamHall hall;
  final int examId;
  final String sessionDate;
  final String sessionTime;

  const SeatingGenerated({
    required this.result,
    required this.hall,
    required this.examId,
    required this.sessionDate,
    required this.sessionTime,
  });
  @override
  List<Object?> get props => [result, hall, examId, sessionDate, sessionTime];
}

class SeatingLoaded extends ExamState {
  final List<SeatingArrangement> seating;
  final int examId;
  const SeatingLoaded(this.seating, {required this.examId});
  @override
  List<Object?> get props => [seating, examId];
}

class SavedSeatingLoaded extends ExamState {
  final List<SeatingArrangement> savedSeating;
  final int examId;
  final int? hallId;
  const SavedSeatingLoaded(this.savedSeating, {required this.examId, this.hallId});
  @override
  List<Object?> get props => [savedSeating, examId, hallId];
}

class MarksLoaded extends ExamState {
  final List<ExamMark> marks;
  final int scheduleId;
  const MarksLoaded(this.marks, {required this.scheduleId});
  @override
  List<Object?> get props => [marks, scheduleId];
}

class ResultsLoaded extends ExamState {
  final List<Map<String, dynamic>> results;
  final int examId;
  final String classId;
  const ResultsLoaded(this.results, {required this.examId, required this.classId});
  @override
  List<Object?> get props => [results, examId, classId];
}

class ExamError extends ExamState {
  final String message;
  const ExamError(this.message);
  @override
  List<Object?> get props => [message];
}
