import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';
import '../../../../core/network/api_client.dart';

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
      final user = await _repository.login(event.username, event.password);
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
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
