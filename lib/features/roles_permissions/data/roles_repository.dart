import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class RolesRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<Map<String, dynamic>>> getRoles() async {
    final response = await _apiClient.get(ApiConstants.roles);
    final roles = (response.data['roles'] as List? ?? const []);
    return roles.map((role) => Map<String, dynamic>.from(role as Map)).toList();
  }

  Future<Map<String, dynamic>> getPermissions() async {
    final response = await _apiClient.get(ApiConstants.permissions);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createRole(Map<String, dynamic> roleData) async {
    final response = await _apiClient.post(ApiConstants.roles, data: roleData);
    return Map<String, dynamic>.from(response.data['role'] as Map);
  }

  Future<void> updateRole(String id, Map<String, dynamic> roleData) async {
    await _apiClient.put('${ApiConstants.roles}/$id', data: roleData);
  }

  Future<void> toggleRoleStatus(String id) async {
    await _apiClient.patch('${ApiConstants.roles}/$id/toggle');
  }
}
