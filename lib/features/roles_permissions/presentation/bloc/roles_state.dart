import 'package:equatable/equatable.dart';

abstract class RolesState extends Equatable {
  const RolesState();

  @override
  List<Object?> get props => [];
}

class RolesInitial extends RolesState {}

class RolesLoading extends RolesState {}

class RolesLoaded extends RolesState {
  final List<Map<String, dynamic>> roles;
  final Map<String, dynamic>? permissionsData;

  const RolesLoaded({
    required this.roles,
    this.permissionsData,
  });

  @override
  List<Object?> get props => [roles, permissionsData];
}

class RolesError extends RolesState {
  final String message;

  const RolesError({required this.message});

  @override
  List<Object?> get props => [message];
}

class RoleActionSuccess extends RolesState {
  final String message;

  const RoleActionSuccess({required this.message});

  @override
  List<Object?> get props => [message];
}
