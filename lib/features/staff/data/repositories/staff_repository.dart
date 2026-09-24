import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_service.dart';
import '../models/staff_model.dart';

class StaffRepository {
  final ApiClient _apiClient;
  StaffRepository(this._apiClient);

  Future<List<StaffMember>> getAll({String? query, String? staffType}) async {
    try {
      final params = <String, dynamic>{};
      if (query != null && query.isNotEmpty) params['q'] = query;
      if (staffType != null && staffType.isNotEmpty) params['staff_type'] = staffType;

      final response = await _apiClient.get('/staff', queryParams: params);
      final raw = response.data;
      List<dynamic> data;
      if (raw is Map) {
        data = (raw['data'] as List?) ?? [];
      } else if (raw is List) {
        data = raw;
      } else {
        data = [];
      }
      return data.map((e) => StaffMember.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      throw Exception('Failed to load staff: $e');
    }
  }

  Future<StaffMember> getById(String id) async {
    try {
      final response = await _apiClient.get('/staff/$id');
      return StaffMember.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to load staff details: $e');
    }
  }

  Future<String> getNextStaffNo() async {
    try {
      final response = await _apiClient.get('/staff/next-no');
      return response.data['staff_no'] as String? ?? 'S-0001';
    } catch (e) {
      return 'S-0001';
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await _apiClient.get('/staff/stats');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      return {'total': 0, 'active': 0, 'teachers': 0, 'byType': []};
    }
  }

  Future<StaffMember> create(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/staff', data: data);
      final member = StaffMember.fromJson(
          (response.data['data'] ?? response.data) as Map<String, dynamic>);
      FirebaseService.syncStaff(member.toJson());
      return member;
    } catch (e) {
      throw Exception('Failed to create staff: $e');
    }
  }

  Future<StaffMember> update(String id, Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.put('/staff/$id', data: data);
      final member = StaffMember.fromJson(
          (response.data['data'] ?? response.data) as Map<String, dynamic>);
      FirebaseService.syncStaff(member.toJson());
      return member;
    } catch (e) {
      throw Exception('Failed to update staff: $e');
    }
  }

  Future<void> delete(String id) async {
    try {
      await _apiClient.delete('/staff/$id');
      FirebaseService.recordDeletionAndSync('staff', id);
    } catch (e) {
      throw Exception('Failed to delete staff: $e');
    }
  }

  Future<void> assignBooks(String staffId, List<String> courseBookIds) async {
    try {
      await _apiClient.post(
        '/staff/$staffId/books',
        data: {'course_book_ids': courseBookIds},
      );
      try {
        final updatedStaff = await getById(staffId);
        FirebaseService.syncStaff(updatedStaff.toJson());
      } catch (_) {}
    } catch (e) {
      throw Exception('Failed to assign books: $e');
    }
  }

  Future<void> bulkDelete(List<String> staffIds) async {
    try {
      await _apiClient.post(
        '/staff/bulk-delete',
        data: {'staffIds': staffIds},
      );
      for (final id in staffIds) {
        FirebaseService.recordDeletionAndSync('staff', id);
      }
    } catch (e) {
      throw Exception('Failed to bulk delete staff: $e');
    }
  }
}
