import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';

class SettingsRepository {
  final ApiClient _apiClient;

  SettingsRepository(this._apiClient);

  Future<Map<String, dynamic>> getWebsiteSettings() async {
    final response = await _apiClient.get('/settings/website');
    return response.data;
  }

  Future<void> updateWebsiteSettings(Map<String, dynamic> data) async {
    await _apiClient.put('/settings/website', data: data);
  }

  Future<List<dynamic>> getGallery() async {
    final response = await _apiClient.get('/gallery');
    return response.data;
  }

  Future<void> deleteGalleryImage(String id) async {
    await _apiClient.delete('/gallery/$id');
  }

  Future<void> uploadGalleryImage(String filePath, String title, String category) async {
    final formData = FormData.fromMap({
      'title': title,
      'category': category,
      'image': await MultipartFile.fromFile(filePath),
    });

    await _apiClient.post('/gallery', data: formData);
  }
}
