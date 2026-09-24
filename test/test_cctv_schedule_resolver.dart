import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/services/cctv_schedule_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('CctvScheduleResolver Tests', () {
    late CctvScheduleResolver resolver;

    setUp(() {
      resolver = CctvScheduleResolver();
    });

    test('Morning Shift is active between 07:30 and 08:30', () {
      // 08:00 AM -> Morning Shift
      final time = DateTime(2026, 9, 17, 8, 0);
      final state = resolver.resolveCurrentState(time);

      expect(state.isAttendanceActive, isTrue);
      expect(state.isShift, isTrue);
      expect(state.isPeriod, isFalse);
      expect(state.activeSlot?.id, 'shift_morning');
    });

    test('Period 1 is active between 08:30 and 09:15', () {
      // 08:45 AM -> Period 1
      final time = DateTime(2026, 9, 17, 8, 45);
      final state = resolver.resolveCurrentState(time);

      expect(state.isAttendanceActive, isTrue);
      expect(state.isPeriod, isTrue);
      expect(state.periodNumber, 1);
      expect(state.activeSlot?.id, 'period_1');
    });

    test('Period 2 is active between 09:15 and 10:00', () {
      // 09:30 AM -> Period 2
      final time = DateTime(2026, 9, 17, 9, 30);
      final state = resolver.resolveCurrentState(time);

      expect(state.isAttendanceActive, isTrue);
      expect(state.isPeriod, isTrue);
      expect(state.periodNumber, 2);
    });

    test('Tafarrugh / Break between 10:45 and 11:15 is IDLE (Attendance Paused)', () {
      // 11:00 AM -> Tafarrugh Break
      final time = DateTime(2026, 9, 17, 11, 0);
      final state = resolver.resolveCurrentState(time);

      expect(state.isAttendanceActive, isFalse);
      expect(state.isIdle, isTrue);
      expect(state.activeSlot?.id, 'break_tafarrugh');
      expect(state.statusTitle, contains('Outside Attendance Hours'));
      expect(state.nextSlot?.id, 'period_4');
    });

    test('Night time outside all shifts and periods is IDLE with next upcoming session info', () {
      // 06:30 AM -> Idle before morning shift
      final time = DateTime(2026, 9, 17, 6, 30);
      final state = resolver.resolveCurrentState(time);

      expect(state.isAttendanceActive, isFalse);
      expect(state.isIdle, isTrue);
      expect(state.activeSlot, isNull);
      expect(state.nextSlot?.id, 'shift_morning');
      expect(state.statusTitle, contains('Outside Attendance Hours'));
    });

    test('Overnight shift crossing midnight (21:00 - 00:50) is active at 21:30 and 00:30', () async {
      await resolver.syncFromMadarsaTimings(
        shifts: [
          {
            'id': 'night_shift_1',
            'name': 'Morning Night Window',
            'start_time': '21:00',
            'end_time': '00:50',
            'is_active': 1,
          },
          {
            'id': 'raat_shift_2',
            'name': 'Raat Shift',
            'start_time': '23:41',
            'end_time': '00:00',
            'is_active': 1,
          }
        ],
        periods: [],
      );

      // At 21:30 (before midnight) -> active
      final state1 = resolver.resolveCurrentState(DateTime(2026, 9, 17, 21, 30));
      expect(state1.isAttendanceActive, isTrue);
      expect(state1.activeSlot?.name, 'Morning Night Window');

      // At 00:30 (after midnight) -> active
      final state2 = resolver.resolveCurrentState(DateTime(2026, 9, 17, 0, 30));
      expect(state2.isAttendanceActive, isTrue);
      expect(state2.activeSlot?.name, 'Morning Night Window');

      // At 01:15 (outside window) -> idle
      final state3 = resolver.resolveCurrentState(DateTime(2026, 9, 17, 1, 15));
      expect(state3.isAttendanceActive, isFalse);
    });
  });
}
