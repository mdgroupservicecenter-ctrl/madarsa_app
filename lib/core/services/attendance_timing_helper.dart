import 'package:intl/intl.dart';
import '../network/api_client.dart';

class AttendanceTimingResult {
  final String status; // 'Present' or 'Late'
  final String timeFormatted; // e.g. '08:15 AM'
  final String? shiftName;
  final int lateMinutes;

  AttendanceTimingResult({
    required this.status,
    required this.timeFormatted,
    this.shiftName,
    this.lateMinutes = 0,
  });

  bool get isLate => status == 'Late';
  String get message => isLate ? 'Late by $lateMinutes mins' : 'On Time';
}

class ShiftWindowCheck {
  final bool isWithinWindow;
  final String shiftName;
  final String shiftStartTime;
  final String shiftEndTime;
  final String currentTime;
  final String reason;

  ShiftWindowCheck({
    required this.isWithinWindow,
    required this.shiftName,
    required this.shiftStartTime,
    required this.shiftEndTime,
    required this.currentTime,
    required this.reason,
  });
}

class AttendanceTimingHelper {
  static int _lateGraceMinutes = 15;
  static List<Map<String, dynamic>> _shifts = [];
  static bool _isLoaded = false;

  static int get lateGraceMinutes => _lateGraceMinutes;
  static set lateGraceMinutes(int val) => _lateGraceMinutes = val;
  static List<Map<String, dynamic>> get shifts => _shifts;
  static set shifts(List<Map<String, dynamic>> val) => _shifts = val;
  static bool get isLoaded => _isLoaded;

  static void configureForTest({int lateGrace = 15, String startTime = '08:00', String endTime = '13:00'}) {
    _lateGraceMinutes = lateGrace;
    _shifts = [
      {
        'id': 'test_shift',
        'name': 'Morning Shift',
        'start_time': startTime,
        'end_time': endTime,
        'is_active': 1,
      }
    ];
    _isLoaded = true;
  }

  static Future<void> loadTimings([ApiClient? apiClient]) async {
    final client = apiClient ?? ApiClient();
    try {
      final genRes = await client.get('/settings/general');
      if (genRes.data is Map) {
        _lateGraceMinutes = int.tryParse(genRes.data['late_grace_minutes']?.toString() ?? '15') ?? 15;
      }
    } catch (_) {}

    try {
      final shiftRes = await client.get('/settings/shifts');
      if (shiftRes.data is List) {
        _shifts = List<Map<String, dynamic>>.from(shiftRes.data as List);
      }
    } catch (_) {}

    _isLoaded = true;
  }

  static String formatTime(DateTime dateTime) {
    return DateFormat('hh:mm:ss a').format(dateTime);
  }

  /// Calculates whether the student is 'Present' or 'Late' based on Madarsa Timings & Grace Period.
  static AttendanceTimingResult evaluate(DateTime dateTime, {String? targetShiftId}) {
    final formattedTime = DateFormat('hh:mm:ss a').format(dateTime);
    final currentMinutes = dateTime.hour * 60 + dateTime.minute;

    if (_shifts.isEmpty) {
      // Default: 08:00 AM start time, 15m grace
      const defaultStartMinutes = 8 * 60; // 08:00
      final cutoff = defaultStartMinutes + _lateGraceMinutes;
      final isLate = currentMinutes > cutoff;
      final lateDiff = isLate ? currentMinutes - defaultStartMinutes : 0;
      return AttendanceTimingResult(
        status: isLate ? 'Late' : 'Present',
        timeFormatted: formattedTime,
        shiftName: 'General Shift',
        lateMinutes: lateDiff,
      );
    }

    // Find requested shift or active shift by time window
    Map<String, dynamic>? activeShift;
    if (targetShiftId != null && targetShiftId.isNotEmpty) {
      for (final s in _shifts) {
        if (s['id']?.toString() == targetShiftId) {
          activeShift = s;
          break;
        }
      }
    }

    if (activeShift == null) {
      for (final s in _shifts) {
        if (s['is_active'] == 1 || s['is_active'] == true || s['is_active'] == null) {
          final startParts = (s['start_time'] ?? '08:00').toString().split(':');
          final endParts = (s['end_time'] ?? '13:00').toString().split(':');
          final sMin = (int.tryParse(startParts[0]) ?? 8) * 60 + (int.tryParse(startParts[1]) ?? 0);
          final eMin = (int.tryParse(endParts[0]) ?? 13) * 60 + (int.tryParse(endParts[1]) ?? 0);

          final bool isWithin;
          if (sMin <= eMin) {
            isWithin = currentMinutes >= sMin && currentMinutes <= eMin;
          } else {
            // Overnight shift crossing midnight (e.g. 21:00 to 00:50)
            isWithin = currentMinutes >= sMin || currentMinutes <= eMin;
          }

          if (isWithin) {
            activeShift = s;
            break;
          }
        }
      }
    }

    activeShift ??= _shifts.first;

    final startParts = (activeShift['start_time'] ?? '08:00').toString().split(':');
    final shiftStartMinutes = (int.tryParse(startParts[0]) ?? 8) * 60 + (int.tryParse(startParts[1]) ?? 0);

    // Elapsed minutes from shift start time with 24h wrap
    int diffFromStart = currentMinutes - shiftStartMinutes;
    if (diffFromStart < 0) {
      diffFromStart += 24 * 60;
    }

    final isLate = diffFromStart > _lateGraceMinutes && diffFromStart < 18 * 60;
    final lateDiff = isLate ? diffFromStart : 0;

    final sName = activeShift['shift_name']?.toString() ?? activeShift['name']?.toString() ?? 'Madarsa Shift';

    return AttendanceTimingResult(
      status: isLate ? 'Late' : 'Present',
      timeFormatted: formattedTime,
      shiftName: sName,
      lateMinutes: lateDiff,
    );
  }

  /// Checks if the given DateTime is within the operating window of the target shift.
  /// Standard window: from shift start_time (minus 30m early arrival) to shift end_time (plus 30m grace).
  static ShiftWindowCheck checkShiftWindow(DateTime now, {String? targetShiftId}) {
    final currentMinutes = now.hour * 60 + now.minute;
    final curFormatted = DateFormat('hh:mm:ss a').format(now);

    if (_shifts.isEmpty) {
      return ShiftWindowCheck(
        isWithinWindow: true,
        shiftName: 'General Shift',
        shiftStartTime: '08:00',
        shiftEndTime: '13:00',
        currentTime: curFormatted,
        reason: 'No shifts configured',
      );
    }

    Map<String, dynamic>? activeShift;
    if (targetShiftId != null && targetShiftId.isNotEmpty) {
      for (final s in _shifts) {
        if (s['id']?.toString() == targetShiftId) {
          activeShift = s;
          break;
        }
      }
    }
    activeShift ??= _shifts.first;

    final sName = activeShift['shift_name']?.toString() ?? activeShift['name']?.toString() ?? 'Madarsa Shift';
    final startStr = (activeShift['start_time'] ?? '08:00').toString();
    final endStr = (activeShift['end_time'] ?? '13:00').toString();

    final startParts = startStr.split(':');
    final endParts = endStr.split(':');
    final sMin = (int.tryParse(startParts[0]) ?? 8) * 60 + (int.tryParse(startParts[1]) ?? 0);
    final eMin = (int.tryParse(endParts[0]) ?? 13) * 60 + (int.tryParse(endParts[1]) ?? 0);

    // Allow 30 minutes before shift start and 30 minutes after shift end with 1440m wrap
    final startMargin = (sMin - 30 + 1440) % 1440;
    final endMargin = (eMin + 30) % 1440;

    final bool isWithin;
    if (startMargin <= endMargin) {
      isWithin = currentMinutes >= startMargin && currentMinutes <= endMargin;
    } else {
      // Overnight window crossing midnight (e.g. 20:30 to 01:20)
      isWithin = currentMinutes >= startMargin || currentMinutes <= endMargin;
    }

    return ShiftWindowCheck(
      isWithinWindow: isWithin,
      shiftName: sName,
      shiftStartTime: startStr,
      shiftEndTime: endStr,
      currentTime: curFormatted,
      reason: isWithin ? 'Within shift operating window' : 'Outside shift hours ($startStr - $endStr)',
    );
  }
}
