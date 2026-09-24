import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import 'attendance_timing_helper.dart';

enum CctvSessionType {
  shift,
  period,
  idle,
}

class CctvScheduleSlot {
  final String id;
  final String name;
  final String urduName;
  final CctvSessionType sessionType;
  final int? periodNumber;
  final String startTime; // "HH:mm" (24-hour)
  final String endTime;   // "HH:mm" (24-hour)
  final bool isAttendanceActive;

  const CctvScheduleSlot({
    required this.id,
    required this.name,
    required this.urduName,
    required this.sessionType,
    this.periodNumber,
    required this.startTime,
    required this.endTime,
    this.isAttendanceActive = true,
  });

  int get startMinutes {
    final parts = startTime.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }

  int get endMinutes {
    final parts = endTime.split(':');
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
  }

  bool contains(int minutes) {
    if (startMinutes <= endMinutes) {
      return minutes >= startMinutes && minutes < endMinutes;
    } else {
      // Overnight slot crossing midnight (e.g. 21:00 to 00:50)
      return minutes >= startMinutes || minutes < endMinutes;
    }
  }

  String formatDisplayTime(String time24) {
    try {
      final parts = time24.split(':');
      final dt = DateTime(2026, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('hh:mm:ss a').format(dt);
    } catch (_) {
      return time24;
    }
  }

  String get displayRange => '${formatDisplayTime(startTime)} - ${formatDisplayTime(endTime)}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'urduName': urduName,
        'sessionType': sessionType.name,
        'periodNumber': periodNumber,
        'startTime': startTime,
        'endTime': endTime,
        'isAttendanceActive': isAttendanceActive,
      };

  factory CctvScheduleSlot.fromJson(Map<String, dynamic> json) => CctvScheduleSlot(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        urduName: json['urduName'] ?? '',
        sessionType: CctvSessionType.values.firstWhere(
          (e) => e.name == json['sessionType'],
          orElse: () => CctvSessionType.idle,
        ),
        periodNumber: json['periodNumber'] is int ? json['periodNumber'] : int.tryParse(json['periodNumber']?.toString() ?? ''),
        startTime: json['startTime'] ?? '08:00',
        endTime: json['endTime'] ?? '09:00',
        isAttendanceActive: json['isAttendanceActive'] ?? true,
      );
}

class CctvScheduleState {
  final bool isAttendanceActive;
  final CctvSessionType sessionType;
  final CctvScheduleSlot? activeSlot;
  final CctvScheduleSlot? nextSlot;
  final String statusTitle;
  final String statusSubtitle;
  final Color badgeColor;

  const CctvScheduleState({
    required this.isAttendanceActive,
    required this.sessionType,
    this.activeSlot,
    this.nextSlot,
    required this.statusTitle,
    required this.statusSubtitle,
    required this.badgeColor,
  });

  bool get isPeriod => sessionType == CctvSessionType.period;
  bool get isShift => sessionType == CctvSessionType.shift;
  bool get isIdle => sessionType == CctvSessionType.idle || !isAttendanceActive;
  int get periodNumber => activeSlot?.periodNumber ?? 1;
}

class CctvScheduleResolver {
  static final CctvScheduleResolver _instance = CctvScheduleResolver._internal();
  factory CctvScheduleResolver() => _instance;
  CctvScheduleResolver._internal() {
    _slots = List.from(defaultScheduleSlots);
  }

  List<CctvScheduleSlot> _slots = [];
  List<CctvScheduleSlot> get slots => List.unmodifiable(_slots);

  static final List<CctvScheduleSlot> defaultScheduleSlots = [
    // 1. Morning Shift Check-in Window
    const CctvScheduleSlot(
      id: 'shift_morning',
      name: 'Madarsa Morning Shift',
      urduName: 'مدرسہ صبح کی حاضری',
      sessionType: CctvSessionType.shift,
      startTime: '07:30',
      endTime: '08:30',
      isAttendanceActive: true,
    ),
    // 2. Periods 1 to 3
    const CctvScheduleSlot(
      id: 'period_1',
      name: 'Period 1 Attendance',
      urduName: 'پیریڈ 1 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 1,
      startTime: '08:30',
      endTime: '09:15',
      isAttendanceActive: true,
    ),
    const CctvScheduleSlot(
      id: 'period_2',
      name: 'Period 2 Attendance',
      urduName: 'پیریڈ 2 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 2,
      startTime: '09:15',
      endTime: '10:00',
      isAttendanceActive: true,
    ),
    const CctvScheduleSlot(
      id: 'period_3',
      name: 'Period 3 Attendance',
      urduName: 'پیریڈ 3 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 3,
      startTime: '10:00',
      endTime: '10:45',
      isAttendanceActive: true,
    ),
    // 3. Tafarrugh / Break (Idle / No attendance)
    const CctvScheduleSlot(
      id: 'break_tafarrugh',
      name: 'Tafarrugh / Break',
      urduName: 'تفریح اور وقفہ',
      sessionType: CctvSessionType.idle,
      startTime: '10:45',
      endTime: '11:15',
      isAttendanceActive: false,
    ),
    // 4. Periods 4 to 6
    const CctvScheduleSlot(
      id: 'period_4',
      name: 'Period 4 Attendance',
      urduName: 'پیریڈ 4 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 4,
      startTime: '11:15',
      endTime: '12:00',
      isAttendanceActive: true,
    ),
    const CctvScheduleSlot(
      id: 'period_5',
      name: 'Period 5 Attendance',
      urduName: 'پیریڈ 5 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 5,
      startTime: '12:00',
      endTime: '12:45',
      isAttendanceActive: true,
    ),
    const CctvScheduleSlot(
      id: 'period_6',
      name: 'Period 6 Attendance',
      urduName: 'پیریڈ 6 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 6,
      startTime: '12:45',
      endTime: '13:30',
      isAttendanceActive: true,
    ),
    // 5. Zuhr & Lunch Break
    const CctvScheduleSlot(
      id: 'break_zuhr',
      name: 'Zuhr Namaz & Lunch',
      urduName: 'نماز ظہر و طعام',
      sessionType: CctvSessionType.idle,
      startTime: '13:30',
      endTime: '14:15',
      isAttendanceActive: false,
    ),
    // 6. Periods 7 to 8
    const CctvScheduleSlot(
      id: 'period_7',
      name: 'Period 7 Attendance',
      urduName: 'پیریڈ 7 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 7,
      startTime: '14:15',
      endTime: '15:00',
      isAttendanceActive: true,
    ),
    const CctvScheduleSlot(
      id: 'period_8',
      name: 'Period 8 Attendance',
      urduName: 'پیریڈ 8 کی حاضری',
      sessionType: CctvSessionType.period,
      periodNumber: 8,
      startTime: '15:00',
      endTime: '15:45',
      isAttendanceActive: true,
    ),
    // 7. Evening Shift Check-in
    const CctvScheduleSlot(
      id: 'shift_evening',
      name: 'Evening Shift Check-in',
      urduName: 'مدرسہ شام کی حاضری',
      sessionType: CctvSessionType.shift,
      startTime: '15:45',
      endTime: '17:45',
      isAttendanceActive: true,
    ),
  ];

  Future<void> loadSavedSchedule() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cctv_schedule_slots_json');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = jsonDecode(jsonStr);
        final loaded = decoded.map((e) => CctvScheduleSlot.fromJson(Map<String, dynamic>.from(e))).toList();
        if (loaded.isNotEmpty) {
          _slots = loaded;
          return;
        }
      }
    } catch (e) {
      debugPrint('[CctvScheduleResolver] Error loading saved schedule: $e');
    }

    // Default to syncing directly from Madarsa Timings
    await syncFromMadarsaTimings();
  }

  /// Synchronizes schedule slots directly with configured Madarsa shifts and class periods
  Future<void> syncFromMadarsaTimings({
    List<Map<String, dynamic>>? shifts,
    List<Map<String, dynamic>>? periods,
    ApiClient? apiClient,
  }) async {
    List<Map<String, dynamic>> activeShifts = shifts ?? AttendanceTimingHelper.shifts;
    if (shifts == null && activeShifts.isEmpty) {
      try {
        final client = apiClient ?? ApiClient();
        final res = await client.get('/settings/shifts');
        if (res.data is List) {
          activeShifts = List<Map<String, dynamic>>.from(res.data as List);
          AttendanceTimingHelper.shifts = activeShifts;
        }
      } catch (e) {
        debugPrint('[CctvScheduleResolver] Failed to fetch shifts from API: $e');
      }
    }

    List<Map<String, dynamic>> classPeriods = periods ?? [];
    if (periods == null && classPeriods.isEmpty) {
      try {
        final client = apiClient ?? ApiClient();
        final res = await client.get('/academic/class-periods');
        if (res.data is List) {
          classPeriods = List<Map<String, dynamic>>.from(res.data as List);
        }
      } catch (e) {
        debugPrint('[CctvScheduleResolver] Failed to fetch class periods: $e');
      }
    }

    if (activeShifts.isNotEmpty || classPeriods.isNotEmpty) {
      final List<CctvScheduleSlot> dynamicSlots = [];

      // Add all active shifts
      for (final s in activeShifts) {
        final isActive = s['is_active'] == 1 || s['is_active'] == true || s['is_active'] == null;
        if (!isActive) continue;
        final rawId = s['id']?.toString() ?? 'shift_${dynamicSlots.length + 1}';
        final name = s['shift_name']?.toString() ?? s['name']?.toString() ?? 'Madarsa Shift';
        final start = (s['start_time'] ?? '08:00').toString();
        final end = (s['end_time'] ?? '13:00').toString();

        dynamicSlots.add(CctvScheduleSlot(
          id: rawId.startsWith('shift_') ? rawId : 'shift_$rawId',
          name: name,
          urduName: '',
          sessionType: CctvSessionType.shift,
          startTime: start.length >= 5 ? start.substring(0, 5) : start,
          endTime: end.length >= 5 ? end.substring(0, 5) : end,
          isAttendanceActive: true,
        ));
      }

      // Add all class periods
      for (final p in classPeriods) {
        final pNum = int.tryParse(p['period_number']?.toString() ?? '1') ?? 1;
        final bName = p['book_name']?.toString();
        final pName = bName != null && bName.isNotEmpty ? 'Period $pNum ($bName)' : 'Period $pNum';
        final start = (p['start_time'] ?? '08:00').toString();
        final end = (p['end_time'] ?? '09:00').toString();

        dynamicSlots.add(CctvScheduleSlot(
          id: 'period_${p['id'] ?? pNum}',
          name: pName,
          urduName: '',
          sessionType: CctvSessionType.period,
          periodNumber: pNum,
          startTime: start.length >= 5 ? start.substring(0, 5) : start,
          endTime: end.length >= 5 ? end.substring(0, 5) : end,
          isAttendanceActive: true,
        ));
      }

      if (dynamicSlots.isNotEmpty) {
        _slots = dynamicSlots;
        debugPrint('[CctvScheduleResolver] Synced ${_slots.length} slots from Madarsa timings & periods.');
      }
    }
  }

  Future<void> saveSchedule(List<CctvScheduleSlot> newSlots) async {
    _slots = List.from(newSlots);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _slots.map((s) => s.toJson()).toList();
      await prefs.setString('cctv_schedule_slots_json', jsonEncode(list));
    } catch (e) {
      debugPrint('[CctvScheduleResolver] Error saving schedule: $e');
    }
  }

  /// Evaluates current clock time against timetable
  CctvScheduleState resolveCurrentState(DateTime now) {
    final nowMinutes = now.hour * 60 + now.minute;

    CctvScheduleSlot? activeSlot;
    for (final slot in _slots) {
      if (slot.contains(nowMinutes)) {
        activeSlot = slot;
        break;
      }
    }

    // Find next upcoming slot
    CctvScheduleSlot? nextSlot;
    int minDiff = 999999;
    for (final slot in _slots) {
      int diff = slot.startMinutes - nowMinutes;
      if (diff <= 0) diff += 24 * 60; // next day wrap
      if (diff < minDiff) {
        minDiff = diff;
        nextSlot = slot;
      }
    }

    if (activeSlot != null && activeSlot.isAttendanceActive) {
      final isPer = activeSlot.sessionType == CctvSessionType.period;
      return CctvScheduleState(
        isAttendanceActive: true,
        sessionType: activeSlot.sessionType,
        activeSlot: activeSlot,
        nextSlot: nextSlot,
        statusTitle: isPer
            ? '🟢 Active: Period ${activeSlot.periodNumber} (${activeSlot.displayRange})'
            : '🟢 Active: ${activeSlot.name} (${activeSlot.displayRange})',
        statusSubtitle: isPer
            ? 'Auto Attendance Period ${activeSlot.periodNumber}'
            : 'Auto Attendance Madarsa Shift',
        badgeColor: const Color(0xFF15803D),
      );
    }

    // Idle / Outside of attendance hours
    final nextInfo = nextSlot != null
        ? '${nextSlot.name} starts at ${nextSlot.formatDisplayTime(nextSlot.startTime)}'
        : 'Next session tomorrow morning';

    return CctvScheduleState(
      isAttendanceActive: false,
      sessionType: CctvSessionType.idle,
      activeSlot: activeSlot,
      nextSlot: nextSlot,
      statusTitle: '⏸️ Outside Attendance Hours',
      statusSubtitle: 'Attendance OFF | Next Session: $nextInfo',
      badgeColor: const Color(0xFF64748B),
    );
  }
}
