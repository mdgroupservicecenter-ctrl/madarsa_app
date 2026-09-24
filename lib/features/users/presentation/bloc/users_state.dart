import 'package:equatable/equatable.dart';

abstract class UsersState extends Equatable {
  const UsersState();

  @override
  List<Object?> get props => [];
}

class UsersInitial extends UsersState {}

class UsersLoading extends UsersState {}

class UsersLoaded extends UsersState {
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> availableRoles;

  const UsersLoaded({required this.users, required this.availableRoles});

  @override
  List<Object?> get props => [users, availableRoles];
}

class UsersError extends UsersState {
  final String message;

  const UsersError({required this.message});

  @override
  List<Object?> get props => [message];
}

class UserActionSuccess extends UsersState {
  final String message;

  const UserActionSuccess({required this.message});

  @override
  List<Object?> get props => [message];
}
