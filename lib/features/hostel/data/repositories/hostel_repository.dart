import '../../../../core/network/api_client.dart';
import '../models/hostel_models.dart';

class HostelRepository {
  final ApiClient _apiClient;

  HostelRepository(this._apiClient);

  // ─── HOSTELS ────────────────────────────────────────────────────────
  Future<List<Hostel>> getHostels() async {
    try {
      final response = await _apiClient.get('/hostel/hostels');
      final List data = response.data ?? [];
      return data.map((json) => Hostel.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<Hostel> createHostel({
    required String name,
    String? description,
  }) async {
    try {
      final response = await _apiClient.post(
        '/hostel/hostels',
        data: {
          'name': name,
          if (description != null) 'description': description,
        },
      );
      return Hostel.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<Hostel> updateHostel(
    String id, {
    String? name,
    String? description,
  }) async {
    try {
      final response = await _apiClient.put(
        '/hostel/hostels/$id',
        data: {
          if (name != null) 'name': name,
          'description': description,
        },
      );
      return Hostel.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteHostel(String id) async {
    try {
      await _apiClient.delete('/hostel/hostels/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── ROOMS ──────────────────────────────────────────────────────────
  Future<List<HostelRoom>> getRooms({String? hostelId}) async {
    try {
      final response = await _apiClient.get(
        '/hostel/rooms',
        queryParams: {
          if (hostelId != null) 'hostel_id': hostelId,
        },
      );
      final List data = response.data ?? [];
      return data.map((json) => HostelRoom.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<HostelRoom> createRoom({
    required String hostelId,
    required String roomNumber,
    String? description,
  }) async {
    try {
      final response = await _apiClient.post(
        '/hostel/rooms',
        data: {
          'hostel_id': hostelId,
          'room_number': roomNumber,
          if (description != null) 'description': description,
        },
      );
      return HostelRoom.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<HostelRoom> updateRoom(
    String id, {
    String? roomNumber,
    String? description,
  }) async {
    try {
      final response = await _apiClient.put(
        '/hostel/rooms/$id',
        data: {
          if (roomNumber != null) 'room_number': roomNumber,
          'description': description,
        },
      );
      return HostelRoom.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteRoom(String id) async {
    try {
      await _apiClient.delete('/hostel/rooms/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── BEDS ───────────────────────────────────────────────────────────
  Future<List<HostelBed>> getBeds(String roomId) async {
    try {
      final response = await _apiClient.get(
        '/hostel/beds',
        queryParams: {'room_id': roomId},
      );
      final List data = response.data ?? [];
      return data.map((json) => HostelBed.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<HostelBed> createBed({
    required String roomId,
    required String bedNumber,
    String? description,
  }) async {
    try {
      final response = await _apiClient.post(
        '/hostel/beds',
        data: {
          'room_id': roomId,
          'bed_number': bedNumber,
          if (description != null) 'description': description,
        },
      );
      return HostelBed.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteBed(String id) async {
    try {
      await _apiClient.delete('/hostel/beds/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── ALLOCATIONS / STAY RECORDS ─────────────────────────────────────
  Future<List<HostelAllocation>> getAllocations({
    String? roomId,
    String? status,
    String? search,
  }) async {
    try {
      final response = await _apiClient.get(
        '/hostel/allocations',
        queryParams: {
          if (roomId != null) 'room_id': roomId,
          if (status != null) 'status': status,
          if (search != null) 'search': search,
        },
      );
      final List data = response.data ?? [];
      return data.map((json) => HostelAllocation.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<HostelAllocation> allocateRoom({
    required String bedId,
    required String studentId,
    required String allocationDate,
  }) async {
    try {
      final response = await _apiClient.post(
        '/hostel/allocations',
        data: {
          'bed_id': bedId,
          'student_id': studentId,
          'allocation_date': allocationDate,
        },
      );
      return HostelAllocation.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> bulkAllocateRoom({
    required String roomId,
    required List<String> studentIds,
    required String allocationDate,
  }) async {
    try {
      final response = await _apiClient.post(
        '/hostel/allocations/bulk',
        data: {
          'room_id': roomId,
          'student_ids': studentIds,
          'allocation_date': allocationDate,
        },
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<HostelAllocation> vacateRoom(
    String id, {
    required String vacateDate,
  }) async {
    try {
      final response = await _apiClient.put(
        '/hostel/allocations/$id/vacate',
        data: {
          'vacate_date': vacateDate,
        },
      );
      return HostelAllocation.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteAllocation(String id) async {
    try {
      await _apiClient.delete('/hostel/allocations/$id');
    } catch (e) {
      rethrow;
    }
  }
}
