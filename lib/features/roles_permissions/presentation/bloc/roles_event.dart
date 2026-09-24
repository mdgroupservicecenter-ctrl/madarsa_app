import 'package:equatable/equatable.dart';

abstract class RolesEvent extends Equatable {
  const RolesEvent();

  @override
  List<Object?> get props => [];
}

class FetchRolesRequested extends RolesEvent {}

class CreateRoleRequested extends RolesEvent {
  final Map<String, dynamic> roleData;

  const CreateRoleRequested({required this.roleData});

  @override
  List<Object?> get props => [roleData];
}

class UpdateRoleRequested extends RolesEvent {
  final String id;
  final Map<String, dynamic> roleData;

  const UpdateRoleRequested({required this.id, required this.roleData});

  @override
  List<Object?> get props => [id, roleData];
}

class ToggleRoleStatusRequested extends RolesEvent {
  final String id;

  const ToggleRoleStatusRequested({required this.id});

  @override
  List<Object?> get props => [id];
}
