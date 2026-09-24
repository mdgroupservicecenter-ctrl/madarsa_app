import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/hostel_models.dart';
import '../../data/repositories/hostel_repository.dart';

// ─── BLoC EVENTS ─────────────────────────────────────────────────────

abstract class HostelEvent {}

class LoadHostelData extends HostelEvent {
  final String? hostelId;
  final String? roomId;
  final String? status;
  final String? search;

  LoadHostelData({this.hostelId, this.roomId, this.status, this.search});
}

class CreateHostelEvent extends HostelEvent {
  final String name;
  final String? description;

  CreateHostelEvent({required this.name, this.description});
}

class UpdateHostelEvent extends HostelEvent {
  final String id;
  final String name;
  final String? description;

  UpdateHostelEvent({required this.id, required this.name, this.description});
}

class DeleteHostelEvent extends HostelEvent {
  final String id;
  DeleteHostelEvent(this.id);
}

class CreateRoomEvent extends HostelEvent {
  final String hostelId;
  final String roomNumber;
  final String? description;

  CreateRoomEvent({
    required this.hostelId,
    required this.roomNumber,
    this.description,
  });
}

class UpdateRoomEvent extends HostelEvent {
  final String id;
  final String roomNumber;
  final String? description;

  UpdateRoomEvent({
    required this.id,
    required this.roomNumber,
    this.description,
  });
}

class DeleteRoomEvent extends HostelEvent {
  final String id;
  DeleteRoomEvent(this.id);
}

class AllocateRoomEvent extends HostelEvent {
  final String bedId;
  final String studentId;
  final String allocationDate;

  AllocateRoomEvent({
    required this.bedId,
    required this.studentId,
    required this.allocationDate,
  });
}

class BulkAllocateRoomEvent extends HostelEvent {
  final String roomId;
  final List<String> studentIds;
  final String allocationDate;

  BulkAllocateRoomEvent({
    required this.roomId,
    required this.studentIds,
    required this.allocationDate,
  });
}

class VacateRoomEvent extends HostelEvent {
  final String id;
  final String vacateDate;

  VacateRoomEvent({
    required this.id,
    required this.vacateDate,
  });
}

class DeleteAllocationEvent extends HostelEvent {
  final String id;
  DeleteAllocationEvent(this.id);
}

// ─── BLoC STATES ─────────────────────────────────────────────────────

abstract class HostelState {}

class HostelInitial extends HostelState {}

class HostelLoading extends HostelState {}

class HostelLoaded extends HostelState {
  final List<Hostel> hostels;
  final List<HostelRoom> rooms;
  final List<HostelAllocation> allocations;

  HostelLoaded({
    required this.hostels,
    required this.rooms,
    required this.allocations,
  });
}

class HostelError extends HostelState {
  final String message;
  HostelError(this.message);
}

// ─── BLoC CLASS ──────────────────────────────────────────────────────

class HostelBloc extends Bloc<HostelEvent, HostelState> {
  final HostelRepository repository;

  HostelBloc({required this.repository}) : super(HostelInitial()) {
    on<LoadHostelData>(_onLoadHostelData);
    on<CreateHostelEvent>(_onCreateHostel);
    on<UpdateHostelEvent>(_onUpdateHostel);
    on<DeleteHostelEvent>(_onDeleteHostel);
    on<CreateRoomEvent>(_onCreateRoom);
    on<UpdateRoomEvent>(_onUpdateRoom);
    on<DeleteRoomEvent>(_onDeleteRoom);
    on<AllocateRoomEvent>(_onAllocateRoom);
    on<BulkAllocateRoomEvent>(_onBulkAllocateRoom);
    on<VacateRoomEvent>(_onVacateRoom);
    on<DeleteAllocationEvent>(_onDeleteAllocation);
  }

  Future<void> _onLoadHostelData(LoadHostelData event, Emitter<HostelState> emit) async {
    emit(HostelLoading());
    try {
      final hostels = await repository.getHostels();
      final rooms = await repository.getRooms(hostelId: event.hostelId);
      final allocations = await repository.getAllocations(
        roomId: event.roomId,
        status: event.status,
        search: event.search,
      );
      emit(HostelLoaded(hostels: hostels, rooms: rooms, allocations: allocations));
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onCreateHostel(CreateHostelEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.createHostel(
        name: event.name,
        description: event.description,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onUpdateHostel(UpdateHostelEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.updateHostel(
        event.id,
        name: event.name,
        description: event.description,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onDeleteHostel(DeleteHostelEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.deleteHostel(event.id);
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onCreateRoom(CreateRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.createRoom(
        hostelId: event.hostelId,
        roomNumber: event.roomNumber,
        description: event.description,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onUpdateRoom(UpdateRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.updateRoom(
        event.id,
        roomNumber: event.roomNumber,
        description: event.description,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onDeleteRoom(DeleteRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.deleteRoom(event.id);
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onAllocateRoom(AllocateRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.allocateRoom(
        bedId: event.bedId,
        studentId: event.studentId,
        allocationDate: event.allocationDate,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onBulkAllocateRoom(BulkAllocateRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.bulkAllocateRoom(
        roomId: event.roomId,
        studentIds: event.studentIds,
        allocationDate: event.allocationDate,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onVacateRoom(VacateRoomEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.vacateRoom(
        event.id,
        vacateDate: event.vacateDate,
      );
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }

  Future<void> _onDeleteAllocation(DeleteAllocationEvent event, Emitter<HostelState> emit) async {
    try {
      await repository.deleteAllocation(event.id);
      add(LoadHostelData());
    } catch (e) {
      emit(HostelError(e.toString()));
    }
  }
}
