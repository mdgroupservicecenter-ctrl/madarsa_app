import '../../../../core/network/api_client.dart';

class DashboardRepository {
  final ApiClient _apiClient;

  DashboardRepository(this._apiClient);

  Future<Map<String, dynamic>> getDashboardSummary() async {
    try {
      final response = await _apiClient.get('/dashboard/summary');
      return response.data;
    } catch (e) {
      throw Exception('Failed to load dashboard summary: $e');
    }
  }
}
