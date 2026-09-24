import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../licensing/device_hwid_service.dart';
import '../storage/database_helper.dart';
import 'storage_mode_service.dart';

class FirebaseService {
  static const String defaultApiKey = 'AIzaSyBQINwAJ1VjWbI6_UsEE_Mq-97VsP_jH3A';
  static const String defaultProjectId = 'madarsa-management-cloud';

  static const String _prefKeyCustomProjectId = 'custom_firebase_project_id';
  static const String _prefKeyCustomApiKey = 'custom_firebase_api_key';
  static const String _prefKeyPendingDeletions = 'firebase_pending_deletions';
  static const String _prefKeyAutoSyncEnabled = 'firebase_auto_sync_enabled';
  static const String _prefKeyAutoSyncInterval = 'firebase_auto_sync_interval_seconds';

  static final Set<String> _pendingDeletionsCache = {};

  static bool _autoSyncEnabled = true;
  static int _autoSyncIntervalSeconds = 15;
  static Timer? _autoSyncTimer;
  static DateTime? _lastAutoSyncTime;

  static bool get isAutoSyncEnabled => _autoSyncEnabled;
  static int get autoSyncIntervalSeconds => _autoSyncIntervalSeconds;
  static DateTime? get lastAutoSyncTime => _lastAutoSyncTime;

  static String _activeApiKey = defaultApiKey;
  static String _activeProjectId = defaultProjectId;

  static String get apiKey => _activeApiKey;
  static String get projectId => _activeProjectId;
  static bool get isCustomAccount => _activeProjectId != defaultProjectId;

  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static const String masterRtdbBase =
      'https://madarsa-management-cloud-default-rtdb.asia-southeast1.firebasedatabase.app';

  static final Map<String, Set<String>> _tableColumnsCache = {};

  static Future<Map<String, dynamic>> filterValidColumns(
    Database db,
    String table,
    Map<String, dynamic> data,
  ) async {
    if (!_tableColumnsCache.containsKey(table)) {
      try {
        final info = await db.rawQuery('PRAGMA table_info($table)');
        final cols = info.map((r) => r['name']?.toString() ?? '').where((n) => n.isNotEmpty).toSet();
        _tableColumnsCache[table] = cols;
      } catch (_) {
        return data;
      }
    }
    final validCols = _tableColumnsCache[table];
    if (validCols == null || validCols.isEmpty) return data;
    return Map.fromEntries(data.entries.where((e) => validCols.contains(e.key)));
  }

  static Future<void> initCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pId = prefs.getString(_prefKeyCustomProjectId)?.trim();
      final aKey = prefs.getString(_prefKeyCustomApiKey)?.trim();
      if (pId != null && pId.isNotEmpty && aKey != null && aKey.isNotEmpty) {
        _activeProjectId = pId;
        _activeApiKey = aKey;
      } else {
        _activeProjectId = defaultProjectId;
        _activeApiKey = defaultApiKey;
      }
      final pending = prefs.getStringList(_prefKeyPendingDeletions) ?? [];
      _pendingDeletionsCache.addAll(pending);

      _autoSyncEnabled = prefs.getBool(_prefKeyAutoSyncEnabled) ?? true;
      _autoSyncIntervalSeconds = prefs.getInt(_prefKeyAutoSyncInterval) ?? 15;
      if (_autoSyncIntervalSeconds < 3) _autoSyncIntervalSeconds = 3;
      if (StorageModeService.isOnlineSyncEnabled && _autoSyncEnabled) {
        startAutoSyncTimer();
      }
    } catch (_) {}
  }

  static Future<void> saveCustomCredentials(String newProjectId, String newApiKey) async {
    final cleanProj = newProjectId.trim().toLowerCase();
    final cleanKey = newApiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyCustomProjectId, cleanProj);
    await prefs.setString(_prefKeyCustomApiKey, cleanKey);
    _activeProjectId = cleanProj;
    _activeApiKey = cleanKey;
    if (StorageModeService.isOnlineSyncEnabled) {
      startLiveCloudSync();
    }
  }

  static Future<void> resetToDefaultCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyCustomProjectId);
    await prefs.remove(_prefKeyCustomApiKey);
    _activeProjectId = defaultProjectId;
    _activeApiKey = defaultApiKey;
    if (StorageModeService.isOnlineSyncEnabled) {
      startLiveCloudSync();
    }
  }

  static Future<(bool, String)> testConnection(String testProjectId, String testApiKey) async {
    final cleanProj = testProjectId.trim().toLowerCase();
    final cleanKey = testApiKey.trim();
    if (cleanProj.isEmpty) return (false, 'Project ID cannot be empty (پروجیکٹ آئی ڈی درج کریں)');
    if (cleanKey.isEmpty) return (false, 'API Key cannot be empty (اے پی آئی کی درج کریں)');

    try {
      final url = 'https://firestore.googleapis.com/v1/projects/$cleanProj/databases/(default)/documents/settings?key=$cleanKey&pageSize=1';
      final res = await _dio.get(url);
      if (res.statusCode == 200) {
        return (true, 'Connected successfully to Firebase Project: $cleanProj (کامیابی سے کنکٹ ہو گیا)');
      } else if (res.statusCode == 429) {
        return (true, 'Connected to Firebase Project: $cleanProj (Project verified, but daily free quota limit reached).');
      } else if (res.statusCode == 403) {
        final errBody = res.data?.toString() ?? '';
        if (errBody.contains('CONSUMER_INVALID')) {
          return (false,
              'Project "$cleanProj" was not found on Google Cloud.\n\n'
              'Please check:\n'
              '1. Verify the exact Project ID in Firebase Console -> Project Settings.\n'
              '2. Make sure Cloud Firestore API is enabled.');
        } else {
          return (false,
              'Project "$cleanProj" verified, BUT Security Rules are blocking access!\n\n'
              'How to fix:\n'
              '1. Go to Firebase Console -> Build -> Firestore Database.\n'
              '2. Click the "Rules" tab at the top.\n'
              '3. Change rules to allow access:\n'
              '   allow read, write: if true;\n'
              '4. Click "Publish".\n\n'
              '(فائر بیس رولز میں read, write کی اجازت دینا ضروری ہے)');
        }
      } else if (res.statusCode == 404) {
        return (false,
            'Firestore Database not found in "$cleanProj"!\n\n'
            'Please check:\n'
            'Go to Firebase Console -> Build -> "Firestore Database" and click "Create database" (choose Test mode).\n\n'
            '(فائر بیس میں "Firestore Database" کری ایٹ کریں)');
      } else if (res.statusCode == 400) {
        final err = res.data?['error']?['message']?.toString() ?? 'Invalid request or invalid API Key';
        return (false, 'API Key error: $err\n\n(اے پی آئی کی درست نہیں ہے)');
      } else {
        return (false, 'Status ${res.statusCode}: ${res.data}');
      }
    } catch (e) {
      return (false, 'Connection error: $e');
    }
  }

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 5),
    validateStatus: (status) => status != null && status < 500,
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  // ── Helper to convert standard Dart Map to Firestore JSON Fields ──
  static Map<String, dynamic> toFirestoreFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    data.forEach((key, val) {
      if (val == null) {
        fields[key] = {'nullValue': null};
      } else if (val is bool) {
        fields[key] = {'booleanValue': val};
      } else if (val is int) {
        fields[key] = {'integerValue': val.toString()};
      } else if (val is double) {
        fields[key] = {'doubleValue': val};
      } else if (val is String) {
        fields[key] = {'stringValue': val};
      } else if (val is List) {
        fields[key] = {
          'arrayValue': {
            'values': val.map((v) {
              if (v is String) return {'stringValue': v};
              if (v is int) return {'integerValue': v.toString()};
              if (v is double) return {'doubleValue': v};
              if (v is bool) return {'booleanValue': v};
              return {'stringValue': v.toString()};
            }).toList(),
          }
        };
      } else if (val is Map<String, dynamic>) {
        fields[key] = {
          'mapValue': {'fields': toFirestoreFields(val)}
        };
      }
    });
    return fields;
  }

  // ── Helper to convert Firestore JSON Fields to plain Dart Map ──
  static Map<String, dynamic> fromFirestoreFields(Map<String, dynamic>? fields) {
    if (fields == null) return {};
    final result = <String, dynamic>{};
    fields.forEach((key, raw) {
      if (raw is Map<String, dynamic>) {
        if (raw.containsKey('stringValue')) {
          result[key] = raw['stringValue'];
        } else if (raw.containsKey('integerValue')) {
          result[key] = int.tryParse(raw['integerValue'].toString()) ?? 0;
        } else if (raw.containsKey('doubleValue')) {
          result[key] = (raw['doubleValue'] as num).toDouble();
        } else if (raw.containsKey('booleanValue')) {
          result[key] = raw['booleanValue'] == true;
        } else if (raw.containsKey('nullValue')) {
          result[key] = null;
        } else if (raw.containsKey('arrayValue')) {
          final list = (raw['arrayValue']['values'] as List<dynamic>? ?? []);
          result[key] = list.map((item) {
            if (item is Map<String, dynamic>) {
              if (item.containsKey('stringValue')) return item['stringValue'];
              if (item.containsKey('integerValue')) return int.tryParse(item['integerValue'].toString()) ?? 0;
              if (item.containsKey('doubleValue')) return (item['doubleValue'] as num).toDouble();
              if (item.containsKey('booleanValue')) return item['booleanValue'] == true;
            }
            return item.toString();
          }).toList();
        } else if (raw.containsKey('mapValue')) {
          result[key] = fromFirestoreFields(raw['mapValue']['fields'] as Map<String, dynamic>?);
        }
      }
    });
    return result;
  }

  // ── Generic Firestore Document Getter ──
  static Future<Map<String, dynamic>?> getFirestoreDocument(String collection, String docId) async {
    try {
      final cleanId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = '$firestoreBase/$collection/$cleanId?key=$apiKey';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data != null) {
        final fields = res.data['fields'] as Map<String, dynamic>?;
        return fromFirestoreFields(fields);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Generic Firestore Document Push (Background Cloud Sync) ──
  static Future<bool> setFirestoreDocument(String collection, String docId, Map<String, dynamic> data) async {
    try {
      final cleanId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = '$firestoreBase/$collection/$cleanId?key=$apiKey';
      final res = await _dio.patch(
        url,
        data: {'fields': toFirestoreFields(data)},
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Generic Firestore Document Delete ──
  static Future<bool> deleteFirestoreDocument(String collection, String docId) async {
    try {
      final cleanId = docId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final url = '$firestoreBase/$collection/$cleanId?key=$apiKey';
      final res = await _dio.delete(url);
      return res.statusCode == 200 || res.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  // ── Track & Execute Local Deletions (Tombstones) ──
  static Future<void> recordDeletionAndSync(String collection, String docId) async {
    final rawId = docId.trim();
    if (rawId.isEmpty) return;
    final cleanId = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

    _recentlySavedIds.remove(rawId);
    _recentlySavedIds.remove(cleanId);

    _pendingDeletionsCache.add('$collection:$rawId');
    _pendingDeletionsCache.add('$collection:$cleanId');

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKeyPendingDeletions) ?? [];
      final entry = '$collection:$cleanId';
      if (!list.contains(entry)) {
        list.add(entry);
        await prefs.setStringList(_prefKeyPendingDeletions, list);
      }
    } catch (_) {}

    // Immediate attempt to delete from Firestore online
    try {
      await deleteFirestoreDocument(collection, cleanId);
      if (cleanId != rawId) {
        await deleteFirestoreDocument(collection, rawId);
      }
    } catch (_) {}
  }

  static bool isPendingDeletion(String collection, String docId) {
    final rawId = docId.trim();
    final cleanId = rawId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return _pendingDeletionsCache.contains('$collection:$rawId') ||
        _pendingDeletionsCache.contains('$collection:$cleanId');
  }

  static Future<void> flushPendingDeletions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKeyPendingDeletions) ?? [];
      if (list.isEmpty) return;

      final remaining = <String>[];
      for (final item in list) {
        final parts = item.split(':');
        if (parts.length == 2) {
          final collection = parts[0];
          final docId = parts[1];
          final ok = await deleteFirestoreDocument(collection, docId);
          if (!ok) {
            remaining.add(item);
          }
        }
      }
      await prefs.setStringList(_prefKeyPendingDeletions, remaining);
      _pendingDeletionsCache.clear();
      _pendingDeletionsCache.addAll(remaining);
    } catch (_) {}
  }

  // ── Query All Document IDs from Firestore ──
  static Future<Set<String>> getFirestoreDocumentIds(String collectionName) async {
    final ids = <String>{};
    String? pageToken;
    try {
      do {
        final tokenParam = (pageToken != null && pageToken.isNotEmpty) ? '&pageToken=$pageToken' : '';
        final url = '$firestoreBase/$collectionName?key=$apiKey&pageSize=300$tokenParam';
        final res = await _dio.get(url);
        if (res.statusCode != 200 || res.data == null) break;

        final docs = res.data['documents'] as List?;
        if (docs == null || docs.isEmpty) break;

        for (final doc in docs) {
          final name = doc['name']?.toString() ?? '';
          final id = name.split('/').last;
          if (id.isNotEmpty) {
            ids.add(id);
          }
        }
        pageToken = res.data['nextPageToken']?.toString();
      } while (pageToken != null && pageToken.isNotEmpty);
    } catch (_) {}
    return ids;
  }

  // ── Prune Any Cloud Documents that Were Deleted Locally ──
  static Future<int> pruneDeletedFromCloud(
    String collectionName,
    String sqliteTableName, {
    String idColumn = 'id',
  }) async {
    int pruned = 0;
    try {
      final cloudIds = await getFirestoreDocumentIds(collectionName);
      if (cloudIds.isEmpty) return 0;

      final db = await DatabaseHelper().database;
      final localRows = await db.query(sqliteTableName, columns: [idColumn]);
      final localIds = <String>{};
      for (final r in localRows) {
        final val = r[idColumn]?.toString().trim();
        if (val != null && val.isNotEmpty) {
          localIds.add(val);
          localIds.add(val.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'));
        }
      }

      for (final cId in cloudIds) {
        if (!localIds.contains(cId) && !_recentlySavedIds.contains(cId)) {
          final ok = await deleteFirestoreDocument(collectionName, cId);
          if (ok) pruned++;
        }
      }
    } catch (_) {}
    return pruned;
  }

  // ── Protected Recently Saved Tracking (Prevents Race Condition Deletion) ──
  static final Set<String> _recentlySavedIds = {};
  static void markRecentlySaved(String id) {
    if (id.trim().isEmpty) return;
    _recentlySavedIds.add(id.trim());
    Future.delayed(const Duration(minutes: 5), () {
      _recentlySavedIds.remove(id.trim());
    });
  }

  // ── Background Sync Specific Models ──
  static Future<void> syncStudent(Map<String, dynamic> rawStudent) async {
    Map<String, dynamic> student;
    if (rawStudent['data'] is Map<String, dynamic>) {
      student = Map<String, dynamic>.from(rawStudent['data']);
    } else {
      student = Map<String, dynamic>.from(rawStudent);
    }
    final rawId = student['id']?.toString().trim();
    final grNo = student['gr_no']?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((grNo != null && grNo.isNotEmpty) ? grNo : null);
    if (id != null && id.isNotEmpty) {
      student['id'] = id;
      markRecentlySaved(id);
      await setFirestoreDocument('students', id, student);
    }
  }

  static Future<void> syncStaff(Map<String, dynamic> rawStaff) async {
    Map<String, dynamic> staffMember;
    if (rawStaff['data'] is Map<String, dynamic>) {
      staffMember = Map<String, dynamic>.from(rawStaff['data']);
    } else {
      staffMember = Map<String, dynamic>.from(rawStaff);
    }
    final rawId = staffMember['id']?.toString().trim();
    final staffNo = staffMember['staff_no']?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((staffNo != null && staffNo.isNotEmpty) ? staffNo : null);
    if (id != null && id.isNotEmpty) {
      staffMember['id'] = id;
      markRecentlySaved(id);
      await setFirestoreDocument('staff', id, staffMember);
    }
  }

  static Future<void> syncFee(Map<String, dynamic> fee) async {
    final id = fee['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      markRecentlySaved(id);
      await setFirestoreDocument('fees', id, fee);
    }
  }

  static Future<void> syncAttendance(Map<String, dynamic> att) async {
    final id = att['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      markRecentlySaved(id);
      await setFirestoreDocument('attendance', id, att);
    }
  }

  static Future<void> syncStudentAcademicHistory(Map<String, dynamic> rawHistory) async {
    final history = Map<String, dynamic>.from(rawHistory);
    final id = history['id']?.toString().trim();
    if (id != null && id.isNotEmpty) {
      markRecentlySaved(id);
      await setFirestoreDocument('student_academic_history', id, history);
    }
  }

  static Future<void> deleteStudentAcademicHistoryFromCloud(String historyId) async {
    final cleanId = historyId.trim();
    if (cleanId.isEmpty) return;
    await recordDeletionAndSync('student_academic_history', cleanId);
    await deleteFirestoreDocument('student_academic_history', cleanId);
  }

  static Future<List<Map<String, dynamic>>> fetchStudentAcademicHistoryFromCloud(String studentId) async {
    final list = <Map<String, dynamic>>[];
    try {
      final url = '$firestoreBase/student_academic_history?key=$apiKey&pageSize=300';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data != null) {
        final docs = res.data['documents'] as List?;
        if (docs != null) {
          for (final doc in docs) {
            final fields = doc['fields'] as Map<String, dynamic>?;
            if (fields != null) {
              final map = fromFirestoreFields(fields);
              final sId = map['student_id']?.toString() ?? map['studentId']?.toString();
              if (sId == studentId) {
                list.add(map);
              }
            }
          }
        }
      }
    } catch (_) {}
    return list;
  }

  static Future<void> syncClass(Map<String, dynamic> cls) async {
    final rawId = cls['id']?.toString().trim();
    final name = cls['name']?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((name != null && name.isNotEmpty) ? name : null);
    if (id != null && id.isNotEmpty) {
      markRecentlySaved(id);
      await setFirestoreDocument('classes', id, cls);
    }
  }

  static Future<void> syncDepartment(Map<String, dynamic> rawDept) async {
    Map<String, dynamic> dept = Map<String, dynamic>.from(
      rawDept['data'] is Map<String, dynamic> ? rawDept['data'] : rawDept,
    );
    final rawId = dept['id']?.toString().trim();
    final name = dept['name']?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((name != null && name.isNotEmpty) ? name : null);
    if (id != null && id.isNotEmpty) {
      dept['id'] = id;
      markRecentlySaved(id);
      await setFirestoreDocument('departments', id, dept);
    }
  }

  static Future<void> syncCourse(Map<String, dynamic> rawCourse) async {
    Map<String, dynamic> course = Map<String, dynamic>.from(
      rawCourse['data'] is Map<String, dynamic> ? rawCourse['data'] : rawCourse,
    );
    final rawId = course['id']?.toString().trim();
    final name = course['name']?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((name != null && name.isNotEmpty) ? name : null);
    if (id != null && id.isNotEmpty) {
      course['id'] = id;
      markRecentlySaved(id);
      await setFirestoreDocument('courses', id, course);
    }
  }

  static Future<void> syncBook(Map<String, dynamic> rawBook) async {
    Map<String, dynamic> book = Map<String, dynamic>.from(
      rawBook['data'] is Map<String, dynamic> ? rawBook['data'] : rawBook,
    );
    if (book['name'] == null && book['title'] != null) book['name'] = book['title'];
    if (book['title'] == null && book['name'] != null) book['title'] = book['name'];
    final rawId = book['id']?.toString().trim();
    final name = (book['name'] ?? book['title'])?.toString().trim();
    final id = (rawId != null && rawId.isNotEmpty) ? rawId : ((name != null && name.isNotEmpty) ? name : null);
    if (id != null && id.isNotEmpty) {
      book['id'] = id;
      markRecentlySaved(id);
      await setFirestoreDocument('books', id, book);
    }
  }

  static Future<void> syncClassCourse(Map<String, dynamic> rawCc) async {
    Map<String, dynamic> cc = Map<String, dynamic>.from(
      rawCc['data'] is Map<String, dynamic> ? rawCc['data'] : rawCc,
    );
    final rawId = cc['id']?.toString().trim() ?? cc['class_course_id']?.toString().trim();
    if (rawId != null && rawId.isNotEmpty) {
      cc['id'] = rawId;
      markRecentlySaved(rawId);
      await setFirestoreDocument('class_courses', rawId, cc);
    }
  }

  static Future<void> syncCourseBook(Map<String, dynamic> rawCb) async {
    Map<String, dynamic> cb = Map<String, dynamic>.from(
      rawCb['data'] is Map<String, dynamic> ? rawCb['data'] : rawCb,
    );
    final rawId = cb['id']?.toString().trim() ?? cb['course_book_id']?.toString().trim();
    if (rawId != null && rawId.isNotEmpty) {
      cb['id'] = rawId;
      markRecentlySaved(rawId);
      await setFirestoreDocument('course_books', rawId, cb);
    }
  }

  // ── Sync Progression Series & Academic Sessions to Cloud ──
  static Future<void> syncDepartmentProgressionSeries(List<Map<String, dynamic>> depts) async {
    for (final d in depts) {
      final id = d['id']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        markRecentlySaved(id);
        await setFirestoreDocument('department_progression_series', id, d);
      }
    }
  }

  static Future<void> syncClassProgressionSeries(List<Map<String, dynamic>> classes) async {
    for (final c in classes) {
      final id = c['id']?.toString().trim();
      if (id != null && id.isNotEmpty) {
        markRecentlySaved(id);
        await setFirestoreDocument('class_progression_series', id, c);
      }
    }
  }

  static Future<void> syncAcademicSessionConfig(Map<String, dynamic> config) async {
    markRecentlySaved('academic_session_config');
    await setFirestoreDocument('settings', 'academic_session_config', config);
  }

  // ── Sync Tools & Operations Settings to Cloud (Firestore: settings/*) ──
  static Future<void> syncStudentStatusSettings({List<String>? categories, Map<String, dynamic>? colors}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cats = categories ??
          prefs.getStringList('student_status_categories_v1') ??
          ['Active', 'Inactive', 'Graduated', 'Passed Out', 'Suspended', 'On Leave', 'Transferred'];
      final colorsJson = prefs.getString('student_status_colors_map_v1');
      Map<String, dynamic> colorsMap = {};
      if (colors != null) {
        colorsMap = colors;
      } else if (colorsJson != null && colorsJson.isNotEmpty) {
        try {
          colorsMap = Map<String, dynamic>.from(jsonDecode(colorsJson));
        } catch (_) {}
      }
      await setFirestoreDocument('settings', 'student_status_categories', {
        'categories': cats,
        'colors': colorsMap,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncGenderOptions({List<String>? options}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opts = options ??
          prefs.getStringList('student_gender_options_v1') ??
          ['Male', 'Female', 'Other'];
      await setFirestoreDocument('settings', 'student_gender_options', {
        'options': opts,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncAdmissionTypes({List<String>? options}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opts = options ??
          prefs.getStringList('student_admission_type_options_v1') ??
          ['New', 'Old', 'Promoted', 'Regular', 'Private', 'Hosteller', 'Day Scholar', 'Re-admission'];
      await setFirestoreDocument('settings', 'student_admission_types', {
        'options': opts,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncFeeConditions({List<String>? options}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final opts = options ??
          prefs.getStringList('student_condition_type_options_v1') ??
          ['Regular', 'Scholarship', 'Partial', 'Concession', 'Orphan Free', 'Staff Child'];
      await setFirestoreDocument('settings', 'student_fee_conditions', {
        'options': opts,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncGrNoSettings({Map<String, dynamic>? settings}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = settings ?? {
        'enable_alphabet': prefs.getBool('gr_enable_alphabet') ?? false,
        'start_alphabet': prefs.getString('gr_start_alphabet') ?? 'A',
        'end_alphabet': prefs.getString('gr_end_alphabet') ?? 'Z',
        'alphabet_prefix': prefs.getString('gr_alphabet_prefix') ?? 'A',
        'enable_year': prefs.getBool('gr_enable_year') ?? false,
        'year_format': prefs.getString('gr_year_format') ?? '2digit',
        'custom_year_value': prefs.getString('gr_custom_year_value') ?? '',
        'digit_padding': prefs.getInt('gr_digit_padding') ?? 4,
        'starting_number': prefs.getInt('gr_starting_number') ?? 1,
      };
      data['updated_at'] = DateTime.now().toIso8601String();
      await setFirestoreDocument('settings', 'gr_no_settings', data);
    } catch (_) {}
  }

  // ── Sync Staff Administration (Types, Qualifications & Stat Cards) ──
  static Future<void> syncStaffTypes([List<Map<String, dynamic>>? directTypes]) async {
    try {
      List<Map<String, dynamic>> list = [];
      if (directTypes != null) {
        list = directTypes;
      } else {
        final db = await DatabaseHelper().database;
        try {
          final rows = await db.query('staff_types', where: 'is_active = 1', orderBy: 'name ASC');
          list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        } catch (_) {}
      }
      await setFirestoreDocument('settings', 'staff_types', {
        'types': list,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncStaffQualifications([List<Map<String, dynamic>>? directQuals]) async {
    try {
      List<Map<String, dynamic>> list = [];
      if (directQuals != null) {
        list = directQuals;
      } else {
        final db = await DatabaseHelper().database;
        try {
          final rows = await db.query('qualifications', where: 'is_active = 1', orderBy: 'name ASC');
          list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
        } catch (_) {}
      }
      await setFirestoreDocument('settings', 'staff_qualifications', {
        'qualifications': list,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Future<void> syncStaffStatCardsConfig([List<Map<String, dynamic>>? configs]) async {
    try {
      List<Map<String, dynamic>> list = [];
      if (configs != null) {
        list = configs;
      } else {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('staff_stat_cards_config_v2');
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            list = List<Map<String, dynamic>>.from(decoded.whereType<Map>());
          }
        }
      }
      if (list.isNotEmpty) {
        await setFirestoreDocument('settings', 'staff_stat_cards', {
          'configs': list,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {}
  }

  static Future<void> pullStaffSettings() async {
    try {
      final db = await DatabaseHelper().database;

      // 1. Staff Types
      final typesDoc = await getFirestoreDocument('settings', 'staff_types');
      if (typesDoc != null && typesDoc['types'] is List) {
        final typesList = typesDoc['types'] as List;
        final batch = db.batch();
        final cloudTypeIds = <String>{};
        for (final item in typesList) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final id = map['id']?.toString();
            if (id != null && id.isNotEmpty) {
              cloudTypeIds.add(id);
              final toInsert = await filterValidColumns(db, 'staff_types', map);
              batch.insert('staff_types', toInsert, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
        await batch.commit(noResult: true);

        // Prune local staff types missing from cloud (unless recently saved)
        if (cloudTypeIds.isNotEmpty) {
          try {
            final localRows = await db.query('staff_types', columns: ['id']);
            for (final row in localRows) {
              final localId = row['id']?.toString();
              if (localId != null && !cloudTypeIds.contains(localId) && !_recentlySavedIds.contains(localId)) {
                await db.delete('staff_types', where: 'id = ?', whereArgs: [localId]);
              }
            }
          } catch (_) {}
        }
      }

      // 2. Qualifications
      final qualsDoc = await getFirestoreDocument('settings', 'staff_qualifications');
      if (qualsDoc != null && qualsDoc['qualifications'] is List) {
        final qualsList = qualsDoc['qualifications'] as List;
        final batch = db.batch();
        final cloudQualIds = <String>{};
        for (final item in qualsList) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);
            final id = map['id']?.toString();
            if (id != null && id.isNotEmpty) {
              cloudQualIds.add(id);
              final toInsert = await filterValidColumns(db, 'qualifications', map);
              batch.insert('qualifications', toInsert, conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
        await batch.commit(noResult: true);

        // Prune local qualifications missing from cloud (unless recently saved)
        if (cloudQualIds.isNotEmpty) {
          try {
            final localRows = await db.query('qualifications', columns: ['id']);
            for (final row in localRows) {
              final localId = row['id']?.toString();
              if (localId != null && !cloudQualIds.contains(localId) && !_recentlySavedIds.contains(localId)) {
                await db.delete('qualifications', where: 'id = ?', whereArgs: [localId]);
              }
            }
          } catch (_) {}
        }
      }

      // 3. Stat Cards
      final cardsDoc = await getFirestoreDocument('settings', 'staff_stat_cards');
      if (cardsDoc != null && cardsDoc['configs'] is List) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('staff_stat_cards_config_v2', jsonEncode(cardsDoc['configs']));
      }
    } catch (_) {}
  }

  static Future<void> pushAllToolsSettings() async {
    await syncStudentStatusSettings();
    await syncGenderOptions();
    await syncAdmissionTypes();
    await syncFeeConditions();
    await syncGrNoSettings();
    await syncStaffTypes();
    await syncStaffQualifications();
    await syncStaffStatCardsConfig();
  }

  static Future<void> pullAllToolsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Status Categories & Colors
      final statusDoc = await getFirestoreDocument('settings', 'student_status_categories');
      if (statusDoc != null) {
        if (statusDoc['categories'] is List) {
          final cats = (statusDoc['categories'] as List).map((e) => e.toString()).toList();
          if (cats.isNotEmpty) {
            await prefs.setStringList('student_status_categories_v1', cats);
          }
        }
        if (statusDoc['colors'] is Map) {
          await prefs.setString('student_status_colors_map_v1', jsonEncode(statusDoc['colors']));
        }
      }

      // 2. Gender Options
      final genderDoc = await getFirestoreDocument('settings', 'student_gender_options');
      if (genderDoc != null && genderDoc['options'] is List) {
        final opts = (genderDoc['options'] as List).map((e) => e.toString()).toList();
        if (opts.isNotEmpty) {
          await prefs.setStringList('student_gender_options_v1', opts);
        }
      }

      // 3. Admission Types
      final admDoc = await getFirestoreDocument('settings', 'student_admission_types');
      if (admDoc != null && admDoc['options'] is List) {
        final opts = (admDoc['options'] as List).map((e) => e.toString()).toList();
        if (opts.isNotEmpty) {
          await prefs.setStringList('student_admission_type_options_v1', opts);
        }
      }

      // 4. Fee Conditions
      final condDoc = await getFirestoreDocument('settings', 'student_fee_conditions');
      if (condDoc != null && condDoc['options'] is List) {
        final opts = (condDoc['options'] as List).map((e) => e.toString()).toList();
        if (opts.isNotEmpty) {
          await prefs.setStringList('student_condition_type_options_v1', opts);
        }
      }

      // 5. GR No Settings
      final grDoc = await getFirestoreDocument('settings', 'gr_no_settings');
      if (grDoc != null) {
        if (grDoc['enable_alphabet'] != null) await prefs.setBool('gr_enable_alphabet', grDoc['enable_alphabet'] == true);
        if (grDoc['start_alphabet'] != null) await prefs.setString('gr_start_alphabet', grDoc['start_alphabet'].toString());
        if (grDoc['end_alphabet'] != null) await prefs.setString('gr_end_alphabet', grDoc['end_alphabet'].toString());
        if (grDoc['alphabet_prefix'] != null) await prefs.setString('gr_alphabet_prefix', grDoc['alphabet_prefix'].toString());
        if (grDoc['enable_year'] != null) await prefs.setBool('gr_enable_year', grDoc['enable_year'] == true);
        if (grDoc['year_format'] != null) await prefs.setString('gr_year_format', grDoc['year_format'].toString());
        if (grDoc['custom_year_value'] != null) await prefs.setString('gr_custom_year_value', grDoc['custom_year_value'].toString());
        if (grDoc['digit_padding'] != null) await prefs.setInt('gr_digit_padding', int.tryParse(grDoc['digit_padding'].toString()) ?? 4);
        if (grDoc['starting_number'] != null) await prefs.setInt('gr_starting_number', int.tryParse(grDoc['starting_number'].toString()) ?? 1);
      }

      // 6. Staff Settings
      await pullStaffSettings();
    } catch (_) {}
  }

  // ── Pull Collections from Firestore to Local SQLite (Cloud -> Local Sync) ──
  static Future<bool> pullCollectionFromFirestore(String collectionName, String sqliteTableName) async {
    try {
      final db = await DatabaseHelper().database;
      int count = 0;
      String? pageToken;
      final firestoreDocIds = <String>{};

      do {
        final tokenParam = (pageToken != null && pageToken.isNotEmpty) ? '&pageToken=$pageToken' : '';
        final url = '$firestoreBase/$collectionName?key=$apiKey&pageSize=300$tokenParam';
        final res = await _dio.get(url);
        if (res.statusCode != 200 || res.data == null) break;

        final docs = res.data['documents'] as List?;
        if (docs == null || docs.isEmpty) break;

        final batch = db.batch();
        for (final doc in docs) {
          final fields = doc['fields'] as Map<String, dynamic>?;
          if (fields == null) continue;
          final map = fromFirestoreFields(fields);
          final docId = map['id']?.toString() ?? doc['name']?.toString().split('/').last;
          if (docId != null && docId.isNotEmpty) {
            if (isPendingDeletion(collectionName, docId)) {
              await deleteFirestoreDocument(collectionName, docId);
              continue;
            }
            map['id'] = docId;
            if (sqliteTableName == 'books') {
              if (map['name'] == null && map['title'] != null) map['name'] = map['title'];
              if (map['title'] == null && map['name'] != null) map['title'] = map['name'];
            }
            firestoreDocIds.add(docId);
            final toInsert = await filterValidColumns(db, sqliteTableName, map);
            batch.insert(sqliteTableName, toInsert, conflictAlgorithm: ConflictAlgorithm.replace);
            count++;
          }
        }
        await batch.commit(noResult: true);
        pageToken = res.data['nextPageToken']?.toString();
      } while (pageToken != null && pageToken.isNotEmpty);

      // Reconcile Deletions: If documents exist online, any local record missing from Firestore is deleted,
      // EXCEPT recently saved local records which are protected from deletion!
      bool hasDeletions = false;
      if (firestoreDocIds.isNotEmpty) {
        final localRows = await db.query(sqliteTableName, columns: ['id']);
        final batchDelete = db.batch();
        for (final row in localRows) {
          final localId = row['id']?.toString();
          if (localId != null && !firestoreDocIds.contains(localId) && !_recentlySavedIds.contains(localId)) {
            batchDelete.delete(sqliteTableName, where: 'id = ?', whereArgs: [localId]);
            hasDeletions = true;
          }
        }
        if (hasDeletions) {
          await batchDelete.commit(noResult: true);
        }
      }

      return count > 0 || hasDeletions;
    } catch (_) {
      return false;
    }
  }

  static bool _isSyncing = false;
  static StreamController<bool>? _cloudUpdatesController;
  static Stream<bool> get onCloudUpdated {
    _cloudUpdatesController ??= StreamController<bool>.broadcast();
    return _cloudUpdatesController!.stream;
  }

  // ── Configurable Background Auto-Sync ──
  static Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyAutoSyncEnabled, enabled);
    } catch (_) {}
    if (enabled && StorageModeService.isOnlineSyncEnabled) {
      startAutoSyncTimer();
    } else {
      stopAutoSyncTimer();
    }
    if (_cloudUpdatesController != null && !_cloudUpdatesController!.isClosed) {
      _cloudUpdatesController!.add(true);
    }
  }

  static Future<void> setAutoSyncInterval(int seconds) async {
    if (seconds < 3) seconds = 3;
    _autoSyncIntervalSeconds = seconds;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyAutoSyncInterval, seconds);
    } catch (_) {}
    if (_autoSyncEnabled && StorageModeService.isOnlineSyncEnabled) {
      startAutoSyncTimer();
    }
    if (_cloudUpdatesController != null && !_cloudUpdatesController!.isClosed) {
      _cloudUpdatesController!.add(true);
    }
  }

  static void startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (!_autoSyncEnabled || !StorageModeService.isOnlineSyncEnabled) return;

    _autoSyncTimer = Timer.periodic(Duration(seconds: _autoSyncIntervalSeconds), (_) async {
      if (!_autoSyncEnabled || !StorageModeService.isOnlineSyncEnabled) {
        stopAutoSyncTimer();
        return;
      }
      if (_isSyncing) return;
      try {
        final res = await performFullTwoWaySync();
        if (res.success) {
          _lastAutoSyncTime = DateTime.now();
          if (_cloudUpdatesController != null && !_cloudUpdatesController!.isClosed) {
            _cloudUpdatesController!.add(true);
          }
        }
      } catch (_) {}
    });
  }

  static void stopAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  static Timer? _liveSyncTimer;
  static void startLiveCloudSync() {
    _liveSyncTimer?.cancel();
    if (!StorageModeService.isOnlineSyncEnabled) return;

    if (_autoSyncEnabled) {
      startAutoSyncTimer();
    }

    // Run immediately
    syncAllFromFirestoreInBackground().then((changed) {
      if (changed && _cloudUpdatesController != null && !_cloudUpdatesController!.isClosed) {
        _cloudUpdatesController!.add(true);
      }
    });

    // Run periodic check every 10 seconds to catch live changes from Firebase Console
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!StorageModeService.isOnlineSyncEnabled) {
        stopLiveCloudSync();
        return;
      }
      final changed = await syncAllFromFirestoreInBackground();
      if (changed && _cloudUpdatesController != null && !_cloudUpdatesController!.isClosed) {
        _cloudUpdatesController!.add(true);
      }
    });
  }

  static void stopLiveCloudSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    stopAutoSyncTimer();
  }

  static Future<bool> syncAllFromFirestoreInBackground() async {
    if (!StorageModeService.isOnlineSyncEnabled) return false;
    if (_isSyncing) return false;
    _isSyncing = true;
    bool anyChanged = false;
    try {
      final dChanged = await pullCollectionFromFirestore('departments', 'departments');
      final cChanged = await pullCollectionFromFirestore('classes', 'classes');
      final crsChanged = await pullCollectionFromFirestore('courses', 'courses');
      final bChanged = await pullCollectionFromFirestore('books', 'books');
      final ccChanged = await pullCollectionFromFirestore('class_courses', 'class_courses');
      final cbChanged = await pullCollectionFromFirestore('course_books', 'course_books');
      final sChanged = await pullCollectionFromFirestore('students', 'students');
      final stChanged = await pullCollectionFromFirestore('staff', 'staff');
      final seChanged = await pullCollectionFromFirestore('settings', 'settings');
      final hChanged = await pullCollectionFromFirestore('student_academic_history', 'student_academic_history');
      final dpsChanged = await pullCollectionFromFirestore('department_progression_series', 'department_progression_series');
      final cpsChanged = await pullCollectionFromFirestore('class_progression_series', 'class_progression_series');
      try {
        final cfgDoc = await getFirestoreDocument('settings', 'academic_session_config');
        if (cfgDoc != null && cfgDoc.isNotEmpty) {
          await DatabaseHelper().saveAcademicSessionConfig(cfgDoc);
        }
      } catch (_) {}
      await pullAllToolsSettings();
      anyChanged = dChanged ||
          cChanged ||
          crsChanged ||
          bChanged ||
          ccChanged ||
          cbChanged ||
          sChanged ||
          stChanged ||
          seChanged ||
          hChanged ||
          dpsChanged ||
          cpsChanged;
    } catch (_) {
    } finally {
      _isSyncing = false;
    }
    return anyChanged;
  }

  /// Manually pull all data from Cloud to SQLite (Works on-demand)
  static Future<Map<String, int>> pullAllDataFromCloud() async {
    final counts = <String, int>{};
    try {
      final dCount = await _pullCollectionCount('departments', 'departments');
      counts['departments'] = dCount;
      final cCount = await _pullCollectionCount('classes', 'classes');
      counts['classes'] = cCount;
      final crsCount = await _pullCollectionCount('courses', 'courses');
      counts['courses'] = crsCount;
      final bCount = await _pullCollectionCount('books', 'books');
      counts['books'] = bCount;
      final ccCount = await _pullCollectionCount('class_courses', 'class_courses');
      counts['class_courses'] = ccCount;
      final cbCount = await _pullCollectionCount('course_books', 'course_books');
      counts['course_books'] = cbCount;
      final sCount = await _pullCollectionCount('students', 'students');
      counts['students'] = sCount;
      final stCount = await _pullCollectionCount('staff', 'staff');
      counts['staff'] = stCount;
      final seCount = await _pullCollectionCount('settings', 'settings');
      counts['settings'] = seCount;
      final hCount = await _pullCollectionCount('student_academic_history', 'student_academic_history');
      counts['student_academic_history'] = hCount;
      final dpsCount = await _pullCollectionCount('department_progression_series', 'department_progression_series');
      counts['department_progression_series'] = dpsCount;
      final cpsCount = await _pullCollectionCount('class_progression_series', 'class_progression_series');
      counts['class_progression_series'] = cpsCount;
      try {
        final cfgDoc = await getFirestoreDocument('settings', 'academic_session_config');
        if (cfgDoc != null && cfgDoc.isNotEmpty) {
          await DatabaseHelper().saveAcademicSessionConfig(cfgDoc);
          counts['academic_session_config'] = 1;
        }
      } catch (_) {}
      await pullAllToolsSettings();
    } catch (_) {}
    return counts;
  }

  static Future<int> _pullCollectionCount(String col, String table) async {
    await pullCollectionFromFirestore(col, table);
    final db = await DatabaseHelper().database;
    final res = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table'));
    return res ?? 0;
  }

  /// Manually push all local database records to Firebase Firestore AND remove deleted records from Firestore
  static Future<Map<String, int>> pushAllLocalDataToCloud({bool skipPrune = false}) async {
    final db = await DatabaseHelper().database;
    final counts = <String, int>{
      'departments': 0,
      'classes': 0,
      'courses': 0,
      'books': 0,
      'class_courses': 0,
      'course_books': 0,
      'students': 0,
      'staff': 0,
      'settings': 0,
      'pruned': 0,
    };

    // 1. Flush any pending tombstones
    await flushPendingDeletions();

    // 2. Prune remote deleted records
    int totalPruned = 0;
    if (!skipPrune) {
      totalPruned += await pruneDeletedFromCloud('departments', 'departments', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('classes', 'classes', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('courses', 'courses', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('books', 'books', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('class_courses', 'class_courses', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('course_books', 'course_books', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('students', 'students', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('staff', 'staff', idColumn: 'id');
      counts['pruned'] = totalPruned;
    }

    // 3. Push departments
    try {
      final depts = await db.query('departments');
      for (final d in depts) {
        final dMap = Map<String, dynamic>.from(d);
        final id = dMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('departments', id, dMap);
          if (ok) counts['departments'] = (counts['departments'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 4. Push classes
    try {
      final classes = await db.query('classes');
      for (final c in classes) {
        final cMap = Map<String, dynamic>.from(c);
        final id = cMap['id']?.toString().trim() ?? cMap['name']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('classes', id, cMap);
          if (ok) counts['classes'] = (counts['classes'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 5. Push courses
    try {
      final courses = await db.query('courses');
      for (final crs in courses) {
        final crsMap = Map<String, dynamic>.from(crs);
        final id = crsMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('courses', id, crsMap);
          if (ok) counts['courses'] = (counts['courses'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 6. Push books
    try {
      final books = await db.query('books');
      for (final b in books) {
        final bMap = Map<String, dynamic>.from(b);
        if (bMap['name'] == null && bMap['title'] != null) bMap['name'] = bMap['title'];
        if (bMap['title'] == null && bMap['name'] != null) bMap['title'] = bMap['name'];
        final id = bMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('books', id, bMap);
          if (ok) counts['books'] = (counts['books'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 7. Push class_courses
    try {
      final ccs = await db.query('class_courses');
      for (final cc in ccs) {
        final ccMap = Map<String, dynamic>.from(cc);
        final id = ccMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('class_courses', id, ccMap);
          if (ok) counts['class_courses'] = (counts['class_courses'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 8. Push course_books
    try {
      final cbs = await db.query('course_books');
      for (final cb in cbs) {
        final cbMap = Map<String, dynamic>.from(cb);
        final id = cbMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('course_books', id, cbMap);
          if (ok) counts['course_books'] = (counts['course_books'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 9. Push students
    try {
      final students = await db.query('students');
      for (final s in students) {
        final sMap = Map<String, dynamic>.from(s);
        final id = sMap['id']?.toString().trim() ?? sMap['gr_no']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('students', id, sMap);
          if (ok) counts['students'] = (counts['students'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 10. Push staff
    try {
      final staff = await db.query('staff');
      for (final st in staff) {
        final stMap = Map<String, dynamic>.from(st);
        final id = stMap['id']?.toString().trim() ?? stMap['staff_no']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('staff', id, stMap);
          if (ok) counts['staff'] = (counts['staff'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 11. Push settings
    try {
      final settings = await db.query('settings');
      for (final set in settings) {
        final setMap = Map<String, dynamic>.from(set);
        final key = setMap['key']?.toString().trim();
        if (key != null && key.isNotEmpty) {
          final ok = await setFirestoreDocument('settings', key, setMap);
          if (ok) counts['settings'] = (counts['settings'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 12. Push Tools & Operations Settings
    try {
      await pushAllToolsSettings();
      counts['settings'] = (counts['settings'] ?? 0) + 5;
    } catch (_) {}

    // 13. Push Student Academic History
    try {
      final histories = await db.query('student_academic_history');
      for (final h in histories) {
        final hMap = Map<String, dynamic>.from(h);
        final id = hMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('student_academic_history', id, hMap);
          if (ok) counts['student_academic_history'] = (counts['student_academic_history'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 14. Push Department Progression Series
    try {
      final deptProg = await db.query('department_progression_series');
      for (final dp in deptProg) {
        final dpMap = Map<String, dynamic>.from(dp);
        final id = dpMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('department_progression_series', id, dpMap);
          if (ok) counts['department_progression_series'] = (counts['department_progression_series'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 15. Push Class Progression Series
    try {
      final classProg = await db.query('class_progression_series');
      for (final cp in classProg) {
        final cpMap = Map<String, dynamic>.from(cp);
        final id = cpMap['id']?.toString().trim();
        if (id != null && id.isNotEmpty) {
          final ok = await setFirestoreDocument('class_progression_series', id, cpMap);
          if (ok) counts['class_progression_series'] = (counts['class_progression_series'] ?? 0) + 1;
        }
      }
    } catch (_) {}

    // 16. Push Academic Session Config
    try {
      final sessionConfig = await DatabaseHelper().getCurrentAcademicSessionConfig();
      if (sessionConfig.isNotEmpty) {
        final ok = await setFirestoreDocument('settings', 'academic_session_config', sessionConfig);
        if (ok) counts['settings'] = (counts['settings'] ?? 0) + 1;
      }
    } catch (_) {}

    return counts;
  }

  /// Full 2-Way Synchronization (Runs on-demand when "Sync Now" is tapped)
  static Future<({bool success, int uploaded, int deleted, int downloaded, String? error})> performFullTwoWaySync() async {
    if (_isSyncing) return (success: false, uploaded: 0, deleted: 0, downloaded: 0, error: 'Sync already in progress');
    _isSyncing = true;
    try {
      // 1. Flush any pending tombstones
      await flushPendingDeletions();

      // 2. Prune remote deleted records
      int totalPruned = 0;
      totalPruned += await pruneDeletedFromCloud('departments', 'departments', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('classes', 'classes', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('courses', 'courses', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('books', 'books', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('class_courses', 'class_courses', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('course_books', 'course_books', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('students', 'students', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('staff', 'staff', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('student_academic_history', 'student_academic_history', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('department_progression_series', 'department_progression_series', idColumn: 'id');
      totalPruned += await pruneDeletedFromCloud('class_progression_series', 'class_progression_series', idColumn: 'id');

      // 3. Push active local records to Cloud
      final pushCounts = await pushAllLocalDataToCloud(skipPrune: true);
      final totalUploaded = (pushCounts['departments'] ?? 0) +
          (pushCounts['classes'] ?? 0) +
          (pushCounts['courses'] ?? 0) +
          (pushCounts['books'] ?? 0) +
          (pushCounts['class_courses'] ?? 0) +
          (pushCounts['course_books'] ?? 0) +
          (pushCounts['students'] ?? 0) +
          (pushCounts['staff'] ?? 0) +
          (pushCounts['settings'] ?? 0) +
          (pushCounts['student_academic_history'] ?? 0) +
          (pushCounts['department_progression_series'] ?? 0) +
          (pushCounts['class_progression_series'] ?? 0);

      // 4. Pull updates from Cloud
      int downloaded = 0;
      final dChanged = await pullCollectionFromFirestore('departments', 'departments');
      final cChanged = await pullCollectionFromFirestore('classes', 'classes');
      final crsChanged = await pullCollectionFromFirestore('courses', 'courses');
      final bChanged = await pullCollectionFromFirestore('books', 'books');
      final ccChanged = await pullCollectionFromFirestore('class_courses', 'class_courses');
      final cbChanged = await pullCollectionFromFirestore('course_books', 'course_books');
      final sChanged = await pullCollectionFromFirestore('students', 'students');
      final stChanged = await pullCollectionFromFirestore('staff', 'staff');
      final seChanged = await pullCollectionFromFirestore('settings', 'settings');
      final hChanged = await pullCollectionFromFirestore('student_academic_history', 'student_academic_history');
      final dpsChanged = await pullCollectionFromFirestore('department_progression_series', 'department_progression_series');
      final cpsChanged = await pullCollectionFromFirestore('class_progression_series', 'class_progression_series');
      try {
        final cfgDoc = await getFirestoreDocument('settings', 'academic_session_config');
        if (cfgDoc != null && cfgDoc.isNotEmpty) {
          await DatabaseHelper().saveAcademicSessionConfig(cfgDoc);
        }
      } catch (_) {}
      await pullAllToolsSettings();
      if (dChanged ||
          cChanged ||
          crsChanged ||
          bChanged ||
          ccChanged ||
          cbChanged ||
          sChanged ||
          stChanged ||
          seChanged ||
          hChanged ||
          dpsChanged ||
          cpsChanged) {
        downloaded = 1;
      }

      _lastAutoSyncTime = DateTime.now();

      return (
        success: true,
        uploaded: totalUploaded,
        deleted: totalPruned,
        downloaded: downloaded,
        error: null,
      );
    } catch (e) {
      return (success: false, uploaded: 0, deleted: 0, downloaded: 0, error: e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  // ── User Authentication (Instant Offline SQLite Check + Cloud Sync) ──
  static Future<Map<String, dynamic>?> loginUser(String username, String password) async {
    final cleanUser = username.trim().toLowerCase();

    // 1. Instant Local SQLite & Hardcoded Admin Check (0.01s - Zero Delay)
    try {
      final db = await DatabaseHelper().database;
      final localUsers = await db.rawQuery(
        'SELECT u.*, r.name as role_name, r.permissions FROM users u LEFT JOIN roles r ON u.role_id = r.id WHERE LOWER(u.username) = ?',
        [cleanUser],
      );
      if (localUsers.isNotEmpty) {
        final u = localUsers.first;
        final savedPass = (u['password'] ?? '').toString();
        if (savedPass == password || (cleanUser == 'admin' && (password == 'admin123' || password == 'admin'))) {
          return {
            'id': u['id']?.toString() ?? 'admin_local_1',
            'username': u['username']?.toString() ?? cleanUser,
            'full_name': u['full_name']?.toString() ?? 'Super Administrator',
            'email': u['email']?.toString() ?? 'admin@madarsa.com',
            'roles': [u['role_name']?.toString() ?? 'Super Admin'],
            'permissions': ['all'],
            'token': 'local_session_${DateTime.now().millisecondsSinceEpoch}',
          };
        }
      }
    } catch (_) {}

    // Hardcoded Default Super Admin instant fallback
    if (cleanUser == 'admin' && (password == 'admin123' || password == 'admin')) {
      return {
        'id': 'admin_master_1',
        'username': 'admin',
        'full_name': 'Super Administrator',
        'email': 'admin@madarsa.com',
        'roles': ['Super Admin'],
        'permissions': ['all'],
        'token': 'instant_master_session',
      };
    }

    // 2. Cloud Firestore Check (When Online)
    try {
      final url = '$firestoreBase/users?key=$apiKey';
      final response = await _dio.get(url);
      if (response.statusCode == 200 && response.data != null && response.data['documents'] is List) {
        final docs = response.data['documents'] as List;
        for (final doc in docs) {
          final fields = doc['fields'] as Map<String, dynamic>?;
          final userMap = fromFirestoreFields(fields);
          final uName = (userMap['username'] ?? '').toString().toLowerCase();
          final uPass = (userMap['password'] ?? userMap['password_hash'] ?? '').toString();

          if (uName == cleanUser && (uPass == password || (cleanUser == 'admin' && password == 'admin123'))) {
            return {
              'id': userMap['id'] ?? doc['name']?.toString().split('/').last ?? 'user_1',
              'username': userMap['username'] ?? cleanUser,
              'full_name': userMap['full_name'] ?? 'Administrator',
              'email': userMap['email'] ?? 'admin@madarsa.com',
              'roles': [userMap['role'] ?? 'Super Admin'],
              'permissions': ['all'],
              'token': 'firebase_token_${DateTime.now().millisecondsSinceEpoch}',
            };
          }
        }
      }
    } catch (_) {}

    return null;
  }

  // ── Trial Heartbeat & Telemetry Ping ──
  static Future<({bool isBlocked, List<String>? features, int? durationDays})> pingTrialTelemetry({
    required String institutionName,
  }) async {
    try {
      final hwid = await DeviceHwidService.getDeviceHwid();
      final deviceName = DeviceHwidService.getDeviceName();
      final osInfo = DeviceHwidService.getOsInfo();
      final prefs = await SharedPreferences.getInstance();
      final trialDate = prefs.getString('madarsa_app_trial_installed_at') ?? DateTime.now().toIso8601String();

      // Clean HWID for RTDB key
      final docId = hwid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final rtdbUrl = '$masterRtdbBase/trial_devices/$docId.json';

      // Clean up previous different docId if any
      final prevDocId = prefs.getString('madarsa_last_trial_doc_id');
      if (prevDocId != null && prevDocId != docId) {
        try {
          await _dio.delete('$masterRtdbBase/trial_devices/$prevDocId.json');
        } catch (_) {}
      }
      await prefs.setString('madarsa_last_trial_doc_id', docId);

      // Read existing record
      final getRes = await _dio.get(rtdbUrl);
      if (getRes.statusCode == 200 && getRes.data != null && getRes.data is Map) {
        final existing = Map<String, dynamic>.from(getRes.data);
        if (existing['is_blocked'] == true) {
          return (isBlocked: true, features: null, durationDays: null);
        }
      }

      // Update device telemetry in Firebase RTDB
      final payload = {
        'hwid': hwid,
        'device_name': deviceName,
        'os_info': osInfo,
        'institution_name': institutionName,
        'trial_installed_at': trialDate,
        'last_heartbeat_at': DateTime.now().toIso8601String(),
        'is_blocked': false,
      };

      await _dio.put(
        rtdbUrl,
        data: payload,
      );

      return (isBlocked: false, features: null, durationDays: null);
    } catch (_) {
      // Offline: continue normally
      return (isBlocked: false, features: null, durationDays: null);
    }
  }

  // ── Paid License Heartbeat & Activation ──
  static Future<({bool isValid, bool isBlocked, List<String>? liveModules, DateTime? expiresAt, String? error})>
      syncLicenseHeartbeat(String licenseKey) async {
    try {
      final cleanKey = licenseKey.trim().toUpperCase().replaceAll(' ', '-');
      final docId = cleanKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final rtdbUrl = '$masterRtdbBase/licenses/$docId.json';

      final res = await _dio.get(rtdbUrl);
      if (res.statusCode == 200 && res.data == null) {
        // The license was DELETED by the administrator from Cloud RTDB! Reject plan immediately!
        return (isValid: false, isBlocked: true, liveModules: null, expiresAt: null, error: 'License deleted or rejected by administrator');
      }
      if (res.statusCode != 200 || res.data is! Map) {
        return (isValid: true, isBlocked: false, liveModules: null, expiresAt: null, error: null);
      }

      final data = Map<String, dynamic>.from(res.data);
      if (data['is_blocked'] == true || data['status'] == 'revoked') {
        return (isValid: false, isBlocked: true, liveModules: null, expiresAt: null, error: 'License blocked by administrator');
      }

      // Register PC hardware information & timestamp in Firebase Realtime Database
      try {
        final hwid = await DeviceHwidService.getDeviceHwid();
        final deviceName = DeviceHwidService.getDeviceName();
        final osInfo = DeviceHwidService.getOsInfo();
        final cleanHwid = hwid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

        String? firstAct;
        // Check if this specific PC has been unlinked or blocked
        if (data['devices'] is Map) {
          final devMap = Map<String, dynamic>.from(data['devices']);
          if (devMap[cleanHwid] != null && devMap[cleanHwid] is Map) {
            final thisDev = Map<String, dynamic>.from(devMap[cleanHwid]);
            if (thisDev['is_blocked'] == true) {
              return (isValid: false, isBlocked: true, liveModules: null, expiresAt: null, error: 'This PC has been blocked from this license.');
            }
            firstAct = thisDev['first_activated_at']?.toString() ?? thisDev['activated_at']?.toString();
          }
        }

        final nowIso = DateTime.now().toIso8601String();
        final devUrl = '$masterRtdbBase/licenses/$docId/devices/$cleanHwid.json';
        await _dio.patch(devUrl, data: {
          'id': cleanHwid,
          'hwid': hwid,
          'device_name': deviceName,
          'os_info': osInfo,
          'last_heartbeat_at': nowIso,
          'first_activated_at': firstAct ?? nowIso,
          'is_blocked': false,
        });

        // Also update license overall heartbeat time
        await _dio.patch(rtdbUrl, data: {
          'last_heartbeat_at': nowIso,
        });
      } catch (_) {}

      List<String>? modules;
      if (data['allowed_modules'] is List) {
        modules = List<String>.from(data['allowed_modules']);
      } else if (data['custom_modules'] is List) {
        modules = List<String>.from(data['custom_modules']);
      }

      DateTime? exp;
      if (data['expires_at'] != null) {
        exp = DateTime.tryParse(data['expires_at'].toString());
      }

      return (isValid: true, isBlocked: false, liveModules: modules, expiresAt: exp, error: null);
    } catch (_) {
      // Offline: keep active
      return (isValid: true, isBlocked: false, liveModules: null, expiresAt: null, error: null);
    }
  }

  // ── UPI & Payment Configuration from Seller ──
  static Future<Map<String, dynamic>?> getPaymentConfig() async {
    try {
      final res = await _dio.get('$masterRtdbBase/settings/payment_config.json');
      if (res.statusCode == 200 && res.data != null && res.data is Map) {
        return Map<String, dynamic>.from(res.data);
      }
    } catch (_) {}
    return null;
  }

  // ── Live Subscription Plans from Seller ──
  static Future<List<Map<String, dynamic>>> getLivePlans() async {
    try {
      final res = await _dio.get('$masterRtdbBase/plans.json');
      if (res.statusCode == 200 && res.data != null && res.data is Map) {
        final Map<String, dynamic> rawMap = Map<String, dynamic>.from(res.data);
        final list = <Map<String, dynamic>>[];
        rawMap.forEach((key, value) {
          if (value is Map) {
            final item = Map<String, dynamic>.from(value);
            item['id'] = item['id'] ?? key;
            list.add(item);
          }
        });
        list.sort((a, b) {
          final pA = (a['price'] as num?)?.toDouble() ?? 0.0;
          final pB = (b['price'] as num?)?.toDouble() ?? 0.0;
          return pA.compareTo(pB);
        });
        return list;
      }
    } catch (_) {}
    return [];
  }
}
