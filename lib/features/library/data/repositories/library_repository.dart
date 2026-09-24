import '../../../../core/network/api_client.dart';
import '../models/library_models.dart';

class LibraryRepository {
  final ApiClient _apiClient;

  LibraryRepository(this._apiClient);

  // ─── SETTINGS ────────────────────────────────────────────────────────
  Future<LibrarySettings> getSettings() async {
    try {
      final response = await _apiClient.get('/library/settings');
      return LibrarySettings.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSettings(LibrarySettings settings) async {
    try {
      await _apiClient.put('/library/settings', data: settings.toJson());
    } catch (e) {
      rethrow;
    }
  }

  // ─── CATEGORIES ──────────────────────────────────────────────────────
  Future<List<LibraryCategory>> getCategories() async {
    try {
      final response = await _apiClient.get('/library/categories');
      final List data = response.data ?? [];
      return data.map((json) => LibraryCategory.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<LibraryCategory> createCategory(String name, String? description) async {
    try {
      final response = await _apiClient.post(
        '/library/categories',
        data: {
          'name': name,
          if (description != null) 'description': description,
        },
      );
      return LibraryCategory.fromJson(response.data['data']);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateCategory(String id, String name, String? description) async {
    try {
      await _apiClient.put(
        '/library/categories/$id',
        data: {
          'name': name,
          'description': description,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await _apiClient.delete('/library/categories/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── BOOKS ───────────────────────────────────────────────────────────
  Future<List<LibraryBook>> getBooks({
    String? search,
    String? categoryId,
    String? availability,
  }) async {
    try {
      final response = await _apiClient.get(
        '/library/books',
        queryParams: {
          if (search != null && search.isNotEmpty) 'search': search,
          if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
          if (availability != null && availability.isNotEmpty) 'availability': availability,
        },
      );
      final List data = response.data ?? [];
      return data.map((json) => LibraryBook.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createBook(LibraryBook book) async {
    try {
      await _apiClient.post('/library/books', data: book.toJson());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBook(String id, LibraryBook book) async {
    try {
      await _apiClient.put('/library/books/$id', data: book.toJson());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteBook(String id) async {
    try {
      await _apiClient.delete('/library/books/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── TRANSACTIONS ────────────────────────────────────────────────────
  Future<List<LibraryTransaction>> getTransactions({
    String? status,
    String? studentId,
    String? staffId,
    String? bookId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final response = await _apiClient.get(
        '/library/transactions',
        queryParams: {
          if (status != null && status.isNotEmpty) 'status': status,
          if (studentId != null && studentId.isNotEmpty) 'student_id': studentId,
          if (staffId != null && staffId.isNotEmpty) 'staff_id': staffId,
          if (bookId != null && bookId.isNotEmpty) 'book_id': bookId,
          if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
          if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
        },
      );
      final List data = response.data ?? [];
      return data.map((json) => LibraryTransaction.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> issueBook({
    String? transactionId,
    String? studentId,
    String? staffId,
    String? borrowerName,
    String? hostelName,
    String? roomNumber,
    String? bedNumber,
    required String bookId,
    String? dueDate,
  }) async {
    try {
      await _apiClient.post(
        '/library/transactions/issue',
        data: {
          if (transactionId != null) 'id': transactionId,
          if (studentId != null) 'student_id': studentId,
          if (staffId != null) 'staff_id': staffId,
          if (borrowerName != null) 'borrower_name': borrowerName,
          if (hostelName != null) 'hostel_name': hostelName,
          if (roomNumber != null) 'room_number': roomNumber,
          if (bedNumber != null) 'bed_number': bedNumber,
          'book_id': bookId,
          if (dueDate != null && dueDate.isNotEmpty) 'due_date': dueDate,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> returnBook(String transactionId, {String? remarks, double? customFine}) async {
    try {
      await _apiClient.put(
        '/library/transactions/$transactionId/return',
        data: {
          if (remarks != null) 'remarks': remarks,
          if (customFine != null) 'custom_fine': customFine,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markBookLost(String transactionId, String? remarks) async {
    try {
      await _apiClient.put(
        '/library/transactions/$transactionId/lost',
        data: {
          if (remarks != null) 'remarks': remarks,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _apiClient.delete('/library/transactions/$transactionId');
    } catch (e) {
      rethrow;
    }
  }

  // ─── STATS & HISTORY ─────────────────────────────────────────────────
  Future<LibraryStats> getStats() async {
    try {
      final response = await _apiClient.get('/library/stats');
      return LibraryStats.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<LibraryTransaction>> getStudentHistory(String studentId) async {
    try {
      final response = await _apiClient.get('/library/student/$studentId/history');
      final List data = response.data ?? [];
      return data.map((json) => LibraryTransaction.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateTransaction({
    required String transactionId,
    String? dueDate,
    String? remarks,
    String? status,
    double? fineAmount,
  }) async {
    try {
      await _apiClient.put(
        '/library/transactions/$transactionId',
        data: {
          if (dueDate != null) 'due_date': dueDate,
          if (remarks != null) 'remarks': remarks,
          if (status != null) 'status': status,
          if (fineAmount != null) 'fine_amount': fineAmount,
        },
      );
    } catch (e) {
      rethrow;
    }
  }
}
