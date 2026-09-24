import 'package:dio/dio.dart';
import '../../../../core/network/api_client.dart';
import '../models/exam_models.dart';

class ExamRepository {
  final ApiClient _apiClient = ApiClient();

  // Exams
  Future<List<Exam>> getExams() async {
    final response = await _apiClient.get('/exams');
    final data = response.data['data'] as List;
    return data.map((json) => Exam.fromJson(json)).toList();
  }

  Future<Exam> createExam(Exam exam) async {
    final response = await _apiClient.post('/exams', data: exam.toJson());
    return Exam.fromJson(response.data['data']);
  }

  // Schedules
  Future<List<ExamSchedule>> getExamSchedules(String examId) async {
    final response = await _apiClient.get('/exams/$examId/schedules');
    final data = response.data['data'] as List;
    return data.map((json) => ExamSchedule.fromJson(json)).toList();
  }

  Future<ExamSchedule> createExamSchedule(ExamSchedule schedule) async {
    final response = await _apiClient.post('/exams/schedules', data: schedule.toJson());
    return ExamSchedule.fromJson(response.data['data']);
  }

  // Halls
  Future<List<ExamHall>> getHalls() async {
    final response = await _apiClient.get('/exams/halls');
    final data = response.data['data'] as List;
    return data.map((json) => ExamHall.fromJson(json)).toList();
  }

  Future<ExamHall> createHall(ExamHall hall) async {
    final response = await _apiClient.post('/exams/halls', data: hall.toJson());
    return ExamHall.fromJson(response.data['data']);
  }

  // Seating
  Future<Map<String, dynamic>> generateSeating({
    required String examId,
    required String sessionDate,
    required String sessionTime,
    required List<String> hallIds,
  }) async {
    try {
      final response = await _apiClient.post('/exams/seating/generate', data: {
        'exam_id': examId,
        'session_date': sessionDate,
        'session_time': sessionTime,
        'hall_ids': hallIds,
      });
      return response.data;
    } on DioException catch (e) {
      final msg = e.response?.data['message'] ?? e.message;
      throw Exception(msg);
    }
  }

  Future<List<SeatingArrangement>> getSeatingArrangements(String examId) async {
    final response = await _apiClient.get('/exams/$examId/seating');
    final data = response.data['data'] as List;
    return data.map((json) => SeatingArrangement.fromJson(json)).toList();
  }

  // Helpers for Schedules
  Future<List<dynamic>> getClasses() async {
    final response = await _apiClient.get('/classes');
    if (response.data is List) return response.data;
    return response.data['data'] ?? [];
  }

  Future<List<dynamic>> getBooks() async {
    final response = await _apiClient.get('/academic/books');
    if (response.data is List) return response.data;
    return response.data['data'] ?? [];
  }
}
