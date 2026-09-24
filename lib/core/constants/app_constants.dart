class ApiConstants {
  static const String baseUrl = 'http://127.0.0.1:3000/api';

  // Auth
  static const String login = '/auth/login';
  static const String profile = '/auth/profile';
  static const String changePassword = '/auth/change-password';

  // Roles
  static const String roles = '/roles';
  static const String permissions = '/roles/permissions';

  // Users
  static const String users = '/users';

  // Health
  static const String health = '/health';

  // Core Modules
  static const String students = '/students';
  static const String classes = '/classes';
  static const String staff = '/staff';
}

class AppConstants {
  static const String appName = 'Madarsa Management';
  static const String appNameUrdu = 'مدرسہ مینجمنٹ';
  static const String appVersion = '1.0.0';
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String themeKey = 'theme_mode';
  static const String languageKey = 'language';
}
