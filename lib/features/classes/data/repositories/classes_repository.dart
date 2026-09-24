import '../../../../core/network/api_client.dart';

class ClassesRepository {
  final ApiClient _apiClient;

  ClassesRepository(this._apiClient);

  Future<List<dynamic>> getAllClasses() async {
    final response = await _apiClient.get('/classes');
    return response.data;
  }

  Future<void> createClass(Map<String, dynamic> data) async {
    await _apiClient.post('/classes', data: data);
  }

  Future<void> updateClass(String id, Map<String, dynamic> data) async {
    await _apiClient.put('/classes/$id', data: data);
  }

  Future<void> deleteClass(String id) async {
    await _apiClient.delete('/classes/$id');
  }
}
