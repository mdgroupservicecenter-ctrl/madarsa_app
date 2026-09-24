import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/staff_model.dart';
import '../../data/repositories/staff_repository.dart';

// ── Events ──────────────────────────────────────────────────────────────────
abstract class StaffEvent {}

class LoadStaff extends StaffEvent {
  final bool silent;
  LoadStaff({this.silent = false});
}

class SearchStaff extends StaffEvent {
  final String query;
  SearchStaff(this.query);
}

class AddStaff extends StaffEvent {
  final Map<String, dynamic> data;
  AddStaff(this.data);
}

class UpdateStaff extends StaffEvent {
  final String id;
  final Map<String, dynamic> data;
  UpdateStaff(this.id, this.data);
}

class DeleteStaff extends StaffEvent {
  final String id;
  DeleteStaff(this.id);
}

class BulkDeleteStaff extends StaffEvent {
  final List<String> staffIds;
  BulkDeleteStaff(this.staffIds);
}

class FilterByType extends StaffEvent {
  final String? staffType;
  FilterByType(this.staffType);
}

// ── States ───────────────────────────────────────────────────────────────────
abstract class StaffState {}

class StaffInitial extends StaffState {}

class StaffLoading extends StaffState {}

class StaffLoaded extends StaffState {
  final List<StaffMember> staff;
  final String? activeFilter;
  StaffLoaded(this.staff, {this.activeFilter});
}

class StaffError extends StaffState {
  final String message;
  StaffError(this.message);
}

class StaffOperationSuccess extends StaffState {
  final String message;
  final List<StaffMember> staff;
  StaffOperationSuccess(this.message, this.staff);
}

// ── BLoC ─────────────────────────────────────────────────────────────────────
class StaffBloc extends Bloc<StaffEvent, StaffState> {
  final StaffRepository _repository;
  String? _currentQuery;
  String? _currentFilter;

  StaffBloc({required StaffRepository repository})
      : _repository = repository,
        super(StaffInitial()) {
    on<LoadStaff>(_onLoad);
    on<SearchStaff>(_onSearch);
    on<AddStaff>(_onAdd);
    on<UpdateStaff>(_onUpdate);
    on<DeleteStaff>(_onDelete);
    on<BulkDeleteStaff>(_onBulkDelete);
    on<FilterByType>(_onFilter);
  }

  Future<void> _onLoad(LoadStaff event, Emitter<StaffState> emit) async {
    if (!event.silent && state is! StaffLoaded) {
      emit(StaffLoading());
    }
    try {
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffLoaded(staff, activeFilter: _currentFilter));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onSearch(SearchStaff event, Emitter<StaffState> emit) async {
    _currentQuery = event.query.isEmpty ? null : event.query;
    emit(StaffLoading());
    try {
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffLoaded(staff, activeFilter: _currentFilter));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onFilter(FilterByType event, Emitter<StaffState> emit) async {
    _currentFilter = event.staffType;
    emit(StaffLoading());
    try {
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffLoaded(staff, activeFilter: _currentFilter));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onAdd(AddStaff event, Emitter<StaffState> emit) async {
    try {
      await _repository.create(event.data);
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffOperationSuccess('Staff added successfully', staff));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onUpdate(UpdateStaff event, Emitter<StaffState> emit) async {
    try {
      await _repository.update(event.id, event.data);
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffOperationSuccess('Staff updated successfully', staff));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onDelete(DeleteStaff event, Emitter<StaffState> emit) async {
    try {
      await _repository.delete(event.id);
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffOperationSuccess('Staff deleted successfully', staff));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onBulkDelete(BulkDeleteStaff event, Emitter<StaffState> emit) async {
    try {
      await _repository.bulkDelete(event.staffIds);
      final staff = await _repository.getAll(
        query: _currentQuery,
        staffType: _currentFilter,
      );
      emit(StaffOperationSuccess('Staff deleted successfully', staff));
    } catch (e) {
      emit(StaffError(e.toString().replaceAll('Exception: ', '')));
    }
  }
}
