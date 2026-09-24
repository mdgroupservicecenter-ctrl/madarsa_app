import 'package:flutter_bloc/flutter_bloc.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';
import '../../data/repositories/dashboard_repository.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository repository;

  DashboardBloc({required this.repository}) : super(DashboardInitial()) {
    on<LoadDashboardData>(_onLoadDashboardData);
  }

  Future<void> _onLoadDashboardData(LoadDashboardData event, Emitter<DashboardState> emit) async {
    emit(DashboardLoading());
    try {
      final summary = await repository.getDashboardSummary();
      emit(DashboardLoaded(
        totalStudents: summary['totalStudents'] ?? 0,
        totalStaff: summary['totalStaff'] ?? 0,
        attendancePercentage: summary['attendancePercentage']?.toString() ?? '0%',
        pendingFees: summary['pendingFees'] ?? 0,
        totalDonations: summary['totalDonations'] ?? 0,
        activeClasses: summary['activeClasses'] ?? 0,
        hostelOccupiedBeds: summary['hostelOccupiedBeds'] ?? 0,
        hostelTotalBeds: summary['hostelTotalBeds'] ?? 0,
        kitchenLowStock: summary['kitchenLowStock'] ?? 0,
        generalLowStock: summary['generalLowStock'] ?? 0,
        totalPurchases: summary['totalPurchases'] ?? 0,
        totalSales: summary['totalSales'] ?? 0,
        totalBooks: summary['totalBooks'] ?? 0,
        issuedBooks: summary['issuedBooks'] ?? 0,
        totalExams: summary['totalExams'] ?? 0,
        totalCourses: summary['totalCourses'] ?? 0,
        totalUsers: summary['totalUsers'] ?? 0,
        newAdmissionsThisMonth: summary['newAdmissionsThisMonth'] ?? 0,
        recentActivity: summary['recentActivity'] ?? [],
      ));
    } catch (e) {
      emit(DashboardError(e.toString()));
    }
  }
}
