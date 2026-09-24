import '../../../../core/network/api_client.dart';
import '../models/contributor_model.dart';

class ContributorRepository {
  final ApiClient _apiClient;

  ContributorRepository(this._apiClient);

  Future<List<Contributor>> getContributors() async {
    try {
      final response = await _apiClient.get('/contributors');
      final list = response.data as List;
      return list.map((json) => Contributor.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<Contributor> getContributorProfile(String id) async {
    try {
      final response = await _apiClient.get('/contributors/$id');
      return Contributor.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createContributor(Map<String, dynamic> data) async {
    try {
      await _apiClient.post('/contributors', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateContributor(String id, Map<String, dynamic> data) async {
    try {
      await _apiClient.put('/contributors/$id', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteContributor(String id) async {
    try {
      await _apiClient.delete('/contributors/$id');
    } catch (e) {
      rethrow;
    }
  }
}
