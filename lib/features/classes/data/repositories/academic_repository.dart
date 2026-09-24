import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';

class AcademicRepository {
  final ApiClient _apiClient;

  AcademicRepository(this._apiClient);

  // --- Departments ---
  Future<List<dynamic>> getAllDepartments() async {
    try {
      final response = await _apiClient.get('/academic/departments');
      return response.data as List<dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createDepartment(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/academic/departments', data: data);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Failed to create department');
      }
      rethrow;
    }
  }

  Future<void> updateDepartment(String id, Map<String, dynamic> data) async {
    try {
      await _apiClient.put('/academic/departments/$id', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteDepartment(String id) async {
    try {
      await _apiClient.delete('/academic/departments/$id');
    } catch (e) {
      rethrow;
    }
  }

  // --- Hierarchy ---
  Future<List<dynamic>> getAcademicHierarchy() async {
    try {
      final response = await _apiClient.get('/academic/hierarchy');
      return response.data as List<dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  // --- Courses ---
  Future<List<dynamic>> getAllCourses() async {
    try {
      final response = await _apiClient.get('/academic/courses');
      return response.data as List<dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCourse(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/academic/courses', data: data);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Failed to create course');
      }
      rethrow;
    }
  }

  Future<void> updateCourse(String id, Map<String, dynamic> data) async {
    try {
      await _apiClient.put('/academic/courses/$id', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCourse(String id) async {
    try {
      await _apiClient.delete('/academic/courses/$id');
    } catch (e) {
      rethrow;
    }
  }

  // --- Books ---
  Future<List<dynamic>> getAllBooks() async {
    try {
      final response = await _apiClient.get('/academic/books');
      return response.data as List<dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createBook(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post('/academic/books', data: data);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Failed to create book');
      }
      rethrow;
    }
  }

  Future<void> updateBook(String id, Map<String, dynamic> data) async {
    try {
      await _apiClient.put('/academic/books/$id', data: data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteBook(String id) async {
    try {
      await _apiClient.delete('/academic/books/$id');
    } catch (e) {
      rethrow;
    }
  }

  // --- Mappings ---
  Future<void> assignCourseToClass(String classId, String courseId) async {
    try {
      await _apiClient.post('/academic/mappings/class-course', data: {
        'class_id': classId,
        'course_id': courseId,
      });
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Failed to assign course');
      }
      rethrow;
    }
  }

  Future<void> removeCourseFromClass(String classCourseId) async {
    try {
      await _apiClient.delete('/academic/mappings/class-course/$classCourseId');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> assignBookToClassCourse(String classCourseId, String bookId) async {
    try {
      await _apiClient.post('/academic/mappings/course-book', data: {
        'class_course_id': classCourseId,
        'book_id': bookId,
      });
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(e.response?.data['error'] ?? 'Failed to assign book');
      }
      rethrow;
    }
  }

  Future<void> removeBookFromClassCourse(String courseBookId) async {
    try {
      await _apiClient.delete('/academic/mappings/course-book/$courseBookId');
    } catch (e) {
      rethrow;
    }
  }
}
