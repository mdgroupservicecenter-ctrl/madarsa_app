import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../theme/app_theme.dart';

// ─── State ────────────────────────────────────────────────
class LocaleState extends Equatable {
  final Locale locale;

  const LocaleState({this.locale = const Locale('en')});

  @override
  List<Object> get props => [locale];
}

// ─── Cubit ────────────────────────────────────────────────
class LocaleCubit extends Cubit<LocaleState> {
  LocaleCubit() : super(const LocaleState()) {
    _loadLocale();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString(AppConstants.languageKey) ?? 'en';
    AppTheme.isUrdu = (langCode == 'ur');
    emit(LocaleState(locale: Locale(langCode)));
  }

  Future<void> changeLocale(String languageCode) async {
    AppTheme.isUrdu = (languageCode == 'ur');
    emit(LocaleState(locale: Locale(languageCode)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.languageKey, languageCode);
  }

  // Supported languages
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'ur', 'name': 'Urdu', 'nativeName': 'اردو'},
    {'code': 'hi', 'name': 'Hindi', 'nativeName': 'हिन्दी'},
    {'code': 'gu', 'name': 'Gujarati', 'nativeName': 'ગુજરાતી'},
  ];
}
