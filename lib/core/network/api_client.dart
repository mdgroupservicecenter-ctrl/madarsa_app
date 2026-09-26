import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../services/firebase_service.dart';
import '../services/storage_mode_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  static void Function()? onUnauthorized;

  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Request interceptor - add auth token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(AppConstants.tokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        final path = error.requestOptions.path;
        final isAuthEndpoint = path.contains('/auth/login') || path.contains('/auth/register');
        if (error.response?.statusCode == 401 && !isAuthEndpoint) {
          _handleUnauthorized();
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  Future<void> _handleUnauthorized() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
  }

  // ─── HTTP Methods Connected to Backend (D:\MD Group\backend) ───

  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) {
    return _dio.get(path, queryParameters: queryParams);
  }

  Map<String, dynamic>? _extractDataToSync(dynamic resData, dynamic reqData) {
    Map<String, dynamic> merged = {};
    if (reqData is Map<String, dynamic>) {
      merged.addAll(Map<String, dynamic>.from(reqData));
    }
    if (resData is Map<String, dynamic>) {
      if (resData['data'] is Map<String, dynamic>) {
        merged.addAll(Map<String, dynamic>.from(resData['data']));
      } else if (resData['student'] is Map<String, dynamic>) {
        merged.addAll(Map<String, dynamic>.from(resData['student']));
      } else if (resData['staff'] is Map<String, dynamic>) {
        merged.addAll(Map<String, dynamic>.from(resData['staff']));
      } else {
        merged.addAll(Map<String, dynamic>.from(resData));
      }
    }
    return merged.isNotEmpty ? merged : null;
  }

  void _injectIdFromPathIfNeeded(String path, Map<String, dynamic> map) {
    if (map['id'] == null || map['id'].toString().trim().isEmpty) {
      final cleanPath = path.split('?').first;
      final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final last = segments.last;
        if (!['types', 'qualifications', 'class-course', 'course-book'].contains(last)) {
          map['id'] = last;
        }
      }
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    final res = await _dio.post(path, data: data);
    final toSync = _extractDataToSync(res.data, data);
    if (toSync != null) {
      _syncToFirebase(path, toSync);
    }
    return res;
  }

  Future<Response> put(String path, {dynamic data}) async {
    final res = await _dio.put(path, data: data);
    final toSync = _extractDataToSync(res.data, data);
    if (toSync != null) {
      _injectIdFromPathIfNeeded(path, toSync);
      _syncToFirebase(path, toSync);
    }
    return res;
  }

  Future<Response> patch(String path, {dynamic data}) async {
    final res = await _dio.patch(path, data: data);
    final toSync = _extractDataToSync(res.data, data);
    if (toSync != null) {
      _injectIdFromPathIfNeeded(path, toSync);
      _syncToFirebase(path, toSync);
    }
    return res;
  }

  Future<Response> delete(String path) async {
    final res = await _dio.delete(path);
    _deleteFromFirebase(path);
    return res;
  }

  // ── Background Firestore Sync Handlers ──
  void _syncToFirebase(String path, dynamic data) {
    if (!StorageModeService.isOnlineSyncEnabled) return;
    try {
      final cleanPath = path.split('?').first;
      if (cleanPath.contains('/staff/types')) {
        FirebaseService.syncStaffTypes();
        return;
      } else if (cleanPath.contains('/staff/qualifications')) {
        FirebaseService.syncStaffQualifications();
        return;
      }

      if (data is! Map<String, dynamic>) return;
      Map<String, dynamic> payload = Map<String, dynamic>.from(data);
      if (payload['data'] is Map<String, dynamic>) {
        payload = Map<String, dynamic>.from(payload['data']);
      }
      if (cleanPath.contains('/students')) {
        FirebaseService.syncStudent(payload);
      } else if (cleanPath.contains('/staff')) {
        FirebaseService.syncStaff(payload);
      } else if (cleanPath.contains('/fees')) {
        FirebaseService.syncFee(payload);
      } else if (cleanPath.contains('/attendance')) {
        FirebaseService.syncAttendance(payload);
      } else if (cleanPath.contains('/academic/departments')) {
        FirebaseService.syncDepartment(payload);
      } else if (cleanPath.contains('/academic/courses')) {
        FirebaseService.syncCourse(payload);
      } else if (cleanPath.contains('/academic/books')) {
        FirebaseService.syncBook(payload);
      } else if (cleanPath.contains('/academic/mappings/class-course')) {
        FirebaseService.syncClassCourse(payload);
      } else if (cleanPath.contains('/academic/mappings/course-book')) {
        FirebaseService.syncCourseBook(payload);
      } else if (cleanPath.contains('/classes')) {
        FirebaseService.syncClass(payload);
      }
    } catch (_) {}
  }

  void _deleteFromFirebase(String path) {
    try {
      final cleanPath = path.split('?').first;
      if (cleanPath.contains('/staff/types')) {
        FirebaseService.syncStaffTypes();
        return;
      }
      if (cleanPath.contains('/staff/qualifications')) {
        FirebaseService.syncStaffQualifications();
        return;
      }

      final id = cleanPath.split('/').last;
      if (id.isEmpty) return;

      String? collection;
      if (cleanPath.contains('/students/')) {
        collection = 'students';
      } else if (cleanPath.contains('/staff/')) {
        collection = 'staff';
      } else if (cleanPath.contains('/fees/')) {
        collection = 'fees';
      } else if (cleanPath.contains('/academic/departments/')) {
        collection = 'departments';
      } else if (cleanPath.contains('/academic/courses/')) {
        collection = 'courses';
      } else if (cleanPath.contains('/academic/books/')) {
        collection = 'books';
      } else if (cleanPath.contains('/academic/mappings/class-course/')) {
        collection = 'class_courses';
      } else if (cleanPath.contains('/academic/mappings/course-book/')) {
        collection = 'course_books';
      } else if (cleanPath.contains('/classes/')) {
        collection = 'classes';
      } else if (cleanPath.contains('/contributors/')) {
        collection = 'contributors';
      }

      if (collection != null) {
        FirebaseService.recordDeletionAndSync(collection, id);
      }
    } catch (_) {}
  }
}
