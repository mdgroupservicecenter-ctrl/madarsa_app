import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class UsersRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _apiClient.get(ApiConstants.users);
    final users = (response.data['users'] as List? ?? const []);
    return users.map((user) => Map<String, dynamic>.from(user as Map)).toList();
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    final response = await _apiClient.post(ApiConstants.users, data: userData);
    return Map<String, dynamic>.from(response.data['user'] as Map);
  }

  Future<void> updateUser(String id, Map<String, dynamic> userData) async {
    await _apiClient.put('${ApiConstants.users}/$id', data: userData);
  }

  Future<void> resetUserPassword(String id, String newPassword) async {
    await _apiClient.put(
      '${ApiConstants.users}/$id/reset-password',
      data: {'newPassword': newPassword},
    );
  }

  Future<List<Map<String, dynamic>>> getRoles() async {
    final response = await _apiClient.get(ApiConstants.roles);
    final roles = (response.data['roles'] as List? ?? const []);
    return roles
        .map((role) => Map<String, dynamic>.from(role as Map))
        .where((role) => role['is_active'] == 1)
        .toList();
  }
}
