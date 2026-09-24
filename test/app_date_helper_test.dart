import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:madarsa_app/core/utils/app_date_helper.dart';

void main() {
  group('AppDateHelper Localization Tests', () {
    final testDate = DateTime(2026, 9, 22, 5, 39);

    test('Gregorian date formats across all 4 languages', () {
      expect(AppDateHelper.formatGregorian(testDate, 'en'), contains('Tue, 22 Sep 2026'));
      expect(AppDateHelper.formatGregorian(testDate, 'ur'), contains('منگل'));
      expect(AppDateHelper.formatGregorian(testDate, 'ur'), contains('ستمبر'));
      expect(AppDateHelper.formatGregorian(testDate, 'hi'), contains('मंगल'));
      expect(AppDateHelper.formatGregorian(testDate, 'hi'), contains('सितंबर'));
      expect(AppDateHelper.formatGregorian(testDate, 'gu'), contains('મંગળ'));
      expect(AppDateHelper.formatGregorian(testDate, 'gu'), contains('સપ્ટેમ્બર'));
    });

    test('Hijri date formats across all 4 languages', () {
      final enHijri = AppDateHelper.formatHijri(testDate, 'en');
      final urHijri = AppDateHelper.formatHijri(testDate, 'ur');
      final hiHijri = AppDateHelper.formatHijri(testDate, 'hi');
      final guHijri = AppDateHelper.formatHijri(testDate, 'gu');

      expect(enHijri, contains('AH'));
      expect(urHijri, contains('ھ'));
      expect(hiHijri, contains('हिजरी'));
      expect(guHijri, contains('હિજરી'));
    });

    test('Jamat time formats across all 4 languages without flipping', () {
      const time = TimeOfDay(hour: 5, minute: 39);
      expect(AppDateHelper.formatJamatTime(time, 'en'), equals('\u200E5:39\u200E AM'));
      expect(AppDateHelper.formatJamatTime(time, 'ur'), equals('\u200E5:39\u200E صبح'));
      expect(AppDateHelper.formatJamatTime(time, 'hi'), equals('\u200E5:39\u200E सुबह'));
      expect(AppDateHelper.formatJamatTime(time, 'gu'), equals('\u200E5:39\u200E સવાર'));
    });

    test('Time remaining formats naturally across all 4 languages', () {
      const dur = Duration(hours: 4, minutes: 15);
      expect(AppDateHelper.formatTimeRemaining(dur, 'en'), equals('in 4h 15m'));
      expect(AppDateHelper.formatTimeRemaining(dur, 'ur'), equals('4 گھنٹے 15 منٹ میں'));
      expect(AppDateHelper.formatTimeRemaining(dur, 'hi'), equals('4 घंटे 15 मिनट में'));
      expect(AppDateHelper.formatTimeRemaining(dur, 'gu'), equals('4 કલાક 15 મિનિટમાં'));
    });
  });
}
