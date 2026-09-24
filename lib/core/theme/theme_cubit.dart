import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

// ─── State ───────────────────────────────────────────────
class ThemeState extends Equatable {
  final ThemeMode themeMode;

  const ThemeState({this.themeMode = ThemeMode.light});

  @override
  List<Object> get props => [themeMode];
}

// ─── Cubit ───────────────────────────────────────────────
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState()) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(AppConstants.themeKey) ?? false;
    emit(ThemeState(themeMode: isDark ? ThemeMode.dark : ThemeMode.light));
  }

  Future<void> toggleTheme() async {
    final newMode = state.themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    emit(ThemeState(themeMode: newMode));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.themeKey, newMode == ThemeMode.dark);
  }

  bool get isDark => state.themeMode == ThemeMode.dark;
}
