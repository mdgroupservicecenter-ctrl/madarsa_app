import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/roles_repository.dart';
import 'roles_event.dart';
import 'roles_state.dart';

class RolesBloc extends Bloc<RolesEvent, RolesState> {
  final RolesRepository _repository;

  RolesBloc({RolesRepository? repository})
      : _repository = repository ?? RolesRepository(),
        super(RolesInitial()) {
    on<FetchRolesRequested>(_onFetchRolesRequested);
    on<CreateRoleRequested>(_onCreateRoleRequested);
    on<UpdateRoleRequested>(_onUpdateRoleRequested);
    on<ToggleRoleStatusRequested>(_onToggleRoleStatusRequested);
  }

  Future<void> _onFetchRolesRequested(
    FetchRolesRequested event,
    Emitter<RolesState> emit,
  ) async {
    emit(RolesLoading());
    try {
      final roles = await _repository.getRoles();
      final permissionsData = await _repository.getPermissions();
      emit(RolesLoaded(roles: roles, permissionsData: permissionsData));
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to fetch roles.';
      emit(RolesError(message: message));
    } catch (e) {
      emit(RolesError(message: 'An unexpected error occurred: $e'));
    }
  }

  Future<void> _onCreateRoleRequested(
    CreateRoleRequested event,
    Emitter<RolesState> emit,
  ) async {
    final currentState = state;
    emit(RolesLoading());
    try {
      await _repository.createRole(event.roleData);
      emit(const RoleActionSuccess(message: 'Role created successfully.'));
      add(FetchRolesRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to create role.';
      emit(RolesError(message: message));
      if (currentState is RolesLoaded) emit(currentState);
    } catch (e) {
      emit(RolesError(message: 'An unexpected error occurred: $e'));
      if (currentState is RolesLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateRoleRequested(
    UpdateRoleRequested event,
    Emitter<RolesState> emit,
  ) async {
    final currentState = state;
    emit(RolesLoading());
    try {
      await _repository.updateRole(event.id, event.roleData);
      emit(const RoleActionSuccess(message: 'Role updated successfully.'));
      add(FetchRolesRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to update role.';
      emit(RolesError(message: message));
      if (currentState is RolesLoaded) emit(currentState);
    } catch (e) {
      emit(RolesError(message: 'An unexpected error occurred: $e'));
      if (currentState is RolesLoaded) emit(currentState);
    }
  }

  Future<void> _onToggleRoleStatusRequested(
    ToggleRoleStatusRequested event,
    Emitter<RolesState> emit,
  ) async {
    final currentState = state;
    emit(RolesLoading());
    try {
      await _repository.toggleRoleStatus(event.id);
      emit(const RoleActionSuccess(message: 'Role status toggled.'));
      add(FetchRolesRequested());
    } on DioException catch (e) {
      final message = e.response?.data?['error'] ?? 'Failed to toggle status.';
      emit(RolesError(message: message));
      if (currentState is RolesLoaded) emit(currentState);
    } catch (e) {
      emit(RolesError(message: 'An unexpected error occurred: $e'));
      if (currentState is RolesLoaded) emit(currentState);
    }
  }
}
