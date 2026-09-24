import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/users_repository.dart';
import 'users_event.dart';
import 'users_state.dart';

class UsersBloc extends Bloc<UsersEvent, UsersState> {
  final UsersRepository _repository;

  UsersBloc({UsersRepository? repository})
      : _repository = repository ?? UsersRepository(),
        super(UsersInitial()) {
    on<FetchUsersRequested>(_onFetchUsersRequested);
    on<CreateUserRequested>(_onCreateUserRequested);
    on<UpdateUserRequested>(_onUpdateUserRequested);
    on<ResetUserPasswordRequested>(_onResetUserPasswordRequested);
  }

  Future<void> _onFetchUsersRequested(
    FetchUsersRequested event,
    Emitter<UsersState> emit,
  ) async {
    emit(UsersLoading());
    try {
      final users = await _repository.getUsers();
      final roles = await _repository.getRoles();
      emit(UsersLoaded(users: users, availableRoles: roles));
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to fetch users.';
      emit(UsersError(message: message));
    } catch (e) {
      emit(UsersError(message: 'An unexpected error occurred: $e'));
    }
  }

  Future<void> _onCreateUserRequested(
    CreateUserRequested event,
    Emitter<UsersState> emit,
  ) async {
    // Preserve old loaded state if possible
    final currentState = state;
    emit(UsersLoading());
    try {
      await _repository.createUser(event.userData);
      emit(const UserActionSuccess(message: 'User created successfully.'));
      // Re-fetch users
      add(FetchUsersRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to create user.';
      emit(UsersError(message: message));
      if (currentState is UsersLoaded) {
        emit(currentState); // Return to previous loaded state
      }
    } catch (e) {
      emit(UsersError(message: 'An unexpected error occurred: $e'));
      if (currentState is UsersLoaded) {
        emit(currentState);
      }
    }
  }

  Future<void> _onUpdateUserRequested(
    UpdateUserRequested event,
    Emitter<UsersState> emit,
  ) async {
    final currentState = state;
    emit(UsersLoading());
    try {
      await _repository.updateUser(event.userId, event.userData);
      emit(const UserActionSuccess(message: 'User updated successfully.'));
      add(FetchUsersRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to update user.';
      emit(UsersError(message: message));
      if (currentState is UsersLoaded) {
        emit(currentState);
      }
    } catch (e) {
      emit(UsersError(message: 'An unexpected error occurred: $e'));
      if (currentState is UsersLoaded) {
        emit(currentState);
      }
    }
  }

  Future<void> _onResetUserPasswordRequested(
    ResetUserPasswordRequested event,
    Emitter<UsersState> emit,
  ) async {
    final currentState = state;
    emit(UsersLoading());
    try {
      await _repository.resetUserPassword(event.userId, event.newPassword);
      emit(const UserActionSuccess(message: 'Password reset successfully.'));
      add(FetchUsersRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to reset password.';
      emit(UsersError(message: message));
      if (currentState is UsersLoaded) {
        emit(currentState);
      }
    } catch (e) {
      emit(UsersError(message: 'An unexpected error occurred: $e'));
      if (currentState is UsersLoaded) {
        emit(currentState);
      }
    }
  }
}
