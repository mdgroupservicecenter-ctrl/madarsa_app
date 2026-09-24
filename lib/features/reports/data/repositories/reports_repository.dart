import '../../../../core/network/api_client.dart';
import '../models/report_models.dart';

class ReportsRepository {
  final ApiClient _apiClient;

  ReportsRepository(this._apiClient);

  Future<List<AttendanceReport>> getAttendanceReport({String? startDate, String? endDate, String? className}) async {
    final response = await _apiClient.get(
      '/reports/attendance',
      queryParams: {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (className != null) 'class_name': className,
      },
    );

    final List data = response.data['reports'] ?? [];
    return data.map((json) => AttendanceReport.fromJson(json)).toList();
  }

  Future<Map<String, dynamic>> getFeeReport({String? startDate, String? endDate}) async {
    final response = await _apiClient.get(
      '/reports/fees',
      queryParams: {
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      },
    );

    final summary = FeeSummary.fromJson(response.data['summary'] ?? {});
    final List breakdown = response.data['breakdown'] ?? [];
    
    return {
      'summary': summary,
      'breakdown': breakdown.map((json) => FeeBreakdown.fromJson(json)).toList(),
    };
  }

  Future<StudentStats> getStudentStats() async {
    final response = await _apiClient.get('/reports/students');
    return StudentStats.fromJson(response.data);
  }

  Future<List<String>> getClassesList() async {
    try {
      final response = await _apiClient.get('/classes');
      final List data = response.data ?? [];
      return data.map((item) => (item['name'] as String)).toList();
    } catch (e) {
      return [];
    }
  }
}
