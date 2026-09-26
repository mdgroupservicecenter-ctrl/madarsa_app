import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/windows_system_branding_service.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;

  AuthBloc({AuthRepository? repository})
      : _repository = repository ?? AuthRepository(),
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);

    ApiClient.onUnauthorized = () {
      add(AuthLogoutRequested());
    };
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final token = await _repository.getSavedToken();
      if (token != null && token.isNotEmpty) {
        final user = await _repository.getSavedUser();
        if (user != null) {
          emit(AuthAuthenticated(user: user));
          return;
        }
      }
      emit(AuthUnauthenticated());
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await WindowsSystemBrandingService.ensureBackendRunning();
      final user = await _repository.login(event.username, event.password);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      String message = e.toString().replaceFirst('Exception: ', '');
      if (e is DioException) {
        if (e.response?.data is Map && e.response?.data['error'] != null) {
          message = e.response!.data['error'].toString();
        } else if (e.type == DioExceptionType.connectionTimeout ||
                   e.type == DioExceptionType.sendTimeout ||
                   e.type == DioExceptionType.receiveTimeout ||
                   e.type == DioExceptionType.connectionError) {
          message = 'Backend server se rabta nahi ho saka. Server start ho raha hai, dobara koshish karein.';
        }
      }
      emit(AuthError(message: message));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _repository.logout();
    emit(AuthUnauthenticated());
  }
}
