abstract class DashboardState {}

class DashboardInitial extends DashboardState {}
class DashboardLoading extends DashboardState {}
class DashboardLoaded extends DashboardState {
  final int totalStudents;
  final int totalStaff;
  final String attendancePercentage;
  final num pendingFees;
  final num totalDonations;
  final int activeClasses;
  final int hostelOccupiedBeds;
  final int hostelTotalBeds;
  final int kitchenLowStock;
  final int generalLowStock;
  final num totalPurchases;
  final num totalSales;
  final int totalBooks;
  final int issuedBooks;
  final int totalExams;
  final int totalCourses;
  final int totalUsers;
  final int newAdmissionsThisMonth;
  final List<dynamic> recentActivity;

  DashboardLoaded({
    required this.totalStudents,
    required this.totalStaff,
    required this.attendancePercentage,
    required this.pendingFees,
    required this.totalDonations,
    required this.activeClasses,
    required this.hostelOccupiedBeds,
    required this.hostelTotalBeds,
    required this.kitchenLowStock,
    required this.generalLowStock,
    required this.totalPurchases,
    required this.totalSales,
    this.totalBooks = 0,
    this.issuedBooks = 0,
    this.totalExams = 0,
    this.totalCourses = 0,
    this.totalUsers = 0,
    this.newAdmissionsThisMonth = 0,
    required this.recentActivity,
  });
}
class DashboardError extends DashboardState {
  final String message;
  DashboardError(this.message);
}
