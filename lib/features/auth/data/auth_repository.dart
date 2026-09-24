import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();
  final LocalStorage _storage = LocalStorage();

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _apiClient.post(
      ApiConstants.login,
      data: {'username': username, 'password': password},
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    final token = data['token'] as String?;
    final user = Map<String, dynamic>.from(data['user'] as Map);

    if (token == null || token.isEmpty) {
      throw Exception('Login token was not returned by the server.');
    }

    await _storage.saveToken(token);
    await _storage.saveUser(user);

    return user;
  }

  Future<Map<String, dynamic>?> getSavedUser() {
    return _storage.getUser();
  }

  Future<String?> getSavedToken() {
    return _storage.getToken();
  }

  Future<void> logout() {
    return _storage.clearAll();
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _apiClient.put(
      ApiConstants.changePassword,
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }
}
