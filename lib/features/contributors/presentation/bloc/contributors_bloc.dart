import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/models/contributor_model.dart';
import '../../data/repositories/contributor_repository.dart';

// ─── BLoC EVENTS ─────────────────────────────────────────────────────
abstract class ContributorsEvent {}

class LoadContributors extends ContributorsEvent {}

class CreateContributorEvent extends ContributorsEvent {
  final Map<String, dynamic> data;
  CreateContributorEvent(this.data);
}

class UpdateContributorEvent extends ContributorsEvent {
  final String id;
  final Map<String, dynamic> data;
  UpdateContributorEvent({required this.id, required this.data});
}

class DeleteContributorEvent extends ContributorsEvent {
  final String id;
  DeleteContributorEvent(this.id);
}

// ─── BLoC STATES ─────────────────────────────────────────────────────
abstract class ContributorsState {}

class ContributorsInitial extends ContributorsState {}

class ContributorsLoading extends ContributorsState {}

class ContributorsLoaded extends ContributorsState {
  final List<Contributor> contributors;
  ContributorsLoaded(this.contributors);
}

class ContributorsError extends ContributorsState {
  final String message;
  ContributorsError(this.message);
}

// ─── BLoC CLASS ──────────────────────────────────────────────────────
class ContributorsBloc extends Bloc<ContributorsEvent, ContributorsState> {
  final ContributorRepository repository;

  ContributorsBloc({required this.repository}) : super(ContributorsInitial()) {
    on<LoadContributors>(_onLoadContributors);
    on<CreateContributorEvent>(_onCreateContributor);
    on<UpdateContributorEvent>(_onUpdateContributor);
    on<DeleteContributorEvent>(_onDeleteContributor);
  }

  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      return error.response?.data?['message'] ??
          error.response?.data?['error'] ??
          error.message ??
          'Server error occurred.';
    }
    return error.toString();
  }

  Future<void> _onLoadContributors(LoadContributors event, Emitter<ContributorsState> emit) async {
    emit(ContributorsLoading());
    try {
      final list = await repository.getContributors();
      emit(ContributorsLoaded(list));
    } catch (e) {
      emit(ContributorsError(_getErrorMessage(e)));
    }
  }

  Future<void> _onCreateContributor(CreateContributorEvent event, Emitter<ContributorsState> emit) async {
    emit(ContributorsLoading());
    try {
      await repository.createContributor(event.data);
      final list = await repository.getContributors();
      emit(ContributorsLoaded(list));
    } catch (e) {
      emit(ContributorsError(_getErrorMessage(e)));
    }
  }

  Future<void> _onUpdateContributor(UpdateContributorEvent event, Emitter<ContributorsState> emit) async {
    emit(ContributorsLoading());
    try {
      await repository.updateContributor(event.id, event.data);
      final list = await repository.getContributors();
      emit(ContributorsLoaded(list));
    } catch (e) {
      emit(ContributorsError(_getErrorMessage(e)));
    }
  }

  Future<void> _onDeleteContributor(DeleteContributorEvent event, Emitter<ContributorsState> emit) async {
    emit(ContributorsLoading());
    try {
      await repository.deleteContributor(event.id);
      final list = await repository.getContributors();
      emit(ContributorsLoaded(list));
    } catch (e) {
      emit(ContributorsError(_getErrorMessage(e)));
    }
  }
}
