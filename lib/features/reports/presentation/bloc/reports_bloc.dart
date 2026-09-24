import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/reports_repository.dart';
import '../../data/models/report_models.dart';

// Events
abstract class ReportsEvent {}

class FetchAttendanceReport extends ReportsEvent {
  final String? startDate;
  final String? endDate;
  final String? className;
  FetchAttendanceReport({this.startDate, this.endDate, this.className});
}

class FetchFeeReport extends ReportsEvent {
  final String? startDate;
  final String? endDate;
  FetchFeeReport({this.startDate, this.endDate});
}

class FetchStudentStats extends ReportsEvent {}

// States
abstract class ReportsState {}

class ReportsInitial extends ReportsState {}

class ReportsLoading extends ReportsState {}

class AttendanceReportLoaded extends ReportsState {
  final List<AttendanceReport> reports;
  AttendanceReportLoaded(this.reports);
}

class FeeReportLoaded extends ReportsState {
  final FeeSummary summary;
  final List<FeeBreakdown> breakdown;
  FeeReportLoaded(this.summary, this.breakdown);
}

class StudentStatsLoaded extends ReportsState {
  final StudentStats stats;
  StudentStatsLoaded(this.stats);
}

class ReportsError extends ReportsState {
  final String message;
  ReportsError(this.message);
}

// BLoC
class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  final ReportsRepository _repository;

  ReportsBloc(this._repository) : super(ReportsInitial()) {
    on<FetchAttendanceReport>(_onFetchAttendanceReport);
    on<FetchFeeReport>(_onFetchFeeReport);
    on<FetchStudentStats>(_onFetchStudentStats);
  }

  Future<void> _onFetchAttendanceReport(
    FetchAttendanceReport event,
    Emitter<ReportsState> emit,
  ) async {
    emit(ReportsLoading());
    try {
      final reports = await _repository.getAttendanceReport(
        startDate: event.startDate,
        endDate: event.endDate,
        className: event.className,
      );
      emit(AttendanceReportLoaded(reports));
    } catch (e) {
      emit(ReportsError(e.toString()));
    }
  }

  Future<void> _onFetchFeeReport(
    FetchFeeReport event,
    Emitter<ReportsState> emit,
  ) async {
    emit(ReportsLoading());
    try {
      final data = await _repository.getFeeReport(
        startDate: event.startDate,
        endDate: event.endDate,
      );
      emit(FeeReportLoaded(data['summary'], data['breakdown']));
    } catch (e) {
      emit(ReportsError(e.toString()));
    }
  }

  Future<void> _onFetchStudentStats(
    FetchStudentStats event,
    Emitter<ReportsState> emit,
  ) async {
    emit(ReportsLoading());
    try {
      final stats = await _repository.getStudentStats();
      emit(StudentStatsLoaded(stats));
    } catch (e) {
      emit(ReportsError(e.toString()));
    }
  }
}
