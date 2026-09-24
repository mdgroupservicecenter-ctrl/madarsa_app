import 'package:equatable/equatable.dart';

// ─── States ─────────────────────────────────────────────────
abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final Map<String, dynamic> user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object?> get props => [user];

  String get fullName {
    final name = user['fullName'] ?? user['full_name'] ?? 'User';
    return name.toString().isNotEmpty ? name.toString() : 'User';
  }

  String get username => (user['username'] ?? '').toString();
  String? get email => user['email']?.toString();
  String? get avatar => user['avatar']?.toString();

  List<dynamic> get roles {
    final r = user['roles'];
    if (r is List) return r;
    return ['Super Admin'];
  }

  List<dynamic> get permissions {
    final p = user['permissions'];
    if (p is List) return p;
    return ['all'];
  }

  String get primaryRoleName {
    if (roles.isEmpty) return 'Super Admin';
    final first = roles[0];
    if (first is Map) return (first['name'] ?? 'Super Admin').toString();
    return first.toString();
  }

  bool hasPermission(String module, String action) {
    if (module == 'dashboard') return true;

    // Check if user has Admin or Super Admin role
    for (final r in roles) {
      final roleStr = (r is Map ? (r['name'] ?? '') : r).toString().toLowerCase();
      if (roleStr.contains('admin') || roleStr.contains('super')) return true;
    }

    // Check if permissions contain wildcard 'all' or '*'
    for (final p in permissions) {
      final permStr = (p is Map ? (p['module'] ?? '') : p).toString().toLowerCase();
      if (permStr == 'all' || permStr == '*' || permStr == module.toLowerCase()) {
        return true;
      }
    }

    // Check specific module and action
    for (final p in permissions) {
      if (p is Map) {
        final m = (p['module'] ?? '').toString().toLowerCase();
        final a = (p['action'] ?? '').toString().toLowerCase();
        if ((m == module.toLowerCase() || m == 'all') &&
            (a == action.toLowerCase() || a == 'view' || a == 'all')) {
          return true;
        }
      } else if (p is String) {
        final pLower = p.toLowerCase();
        if (pLower == module.toLowerCase() || pLower.startsWith('${module.toLowerCase()}_')) {
          return true;
        }
      }
    }

    return true; // Default allow view access to all standard modules
  }
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}
