import 'package:equatable/equatable.dart';

abstract class UsersEvent extends Equatable {
  const UsersEvent();

  @override
  List<Object?> get props => [];
}

class FetchUsersRequested extends UsersEvent {}

class CreateUserRequested extends UsersEvent {
  final Map<String, dynamic> userData;

  const CreateUserRequested({required this.userData});

  @override
  List<Object?> get props => [userData];
}

class UpdateUserRequested extends UsersEvent {
  final String userId;
  final Map<String, dynamic> userData;

  const UpdateUserRequested({required this.userId, required this.userData});

  @override
  List<Object?> get props => [userId, userData];
}

class ResetUserPasswordRequested extends UsersEvent {
  final String userId;
  final String newPassword;

  const ResetUserPasswordRequested({required this.userId, required this.newPassword});

  @override
  List<Object?> get props => [userId, newPassword];
}
