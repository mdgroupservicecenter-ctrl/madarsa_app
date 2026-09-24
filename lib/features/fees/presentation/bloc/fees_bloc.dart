import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/fees_repository.dart';
import '../../data/models/fee_models.dart';

// --- Events ---
abstract class FeesEvent {}

class LoadFeesData extends FeesEvent {}

class PayStudentFee extends FeesEvent {
  final String studentId;
  final double amount;
  final String feeType;
  final String? remarks;
  final String? receiptNo;
  PayStudentFee({
    required this.studentId,
    required this.amount,
    required this.feeType,
    this.remarks,
    this.receiptNo,
  });
}

class RecordDonation extends FeesEvent {
  final String? receiptNo;
  final String? donorName;
  final String? donorPhone;
  final String? village;
  final String? taluka;
  final String? district;
  final String? state;
  final String? country;
  final String? pinCode;
  final double amount;
  final String donationType;
  final String paymentMethod;
  final String? paymentDate;
  
  RecordDonation({
    this.receiptNo,
    this.donorName,
    this.donorPhone,
    this.village,
    this.taluka,
    this.district,
    this.state,
    this.country,
    this.pinCode,
    required this.amount,
    required this.donationType,
    required this.paymentMethod,
    this.paymentDate,
  });
}

// Fee Types events
class AddFeeType extends FeesEvent {
  final String name;
  final String billingType;
  final int defaultMonths;
  final double defaultAmount;
  AddFeeType(
    this.name, {
    this.billingType = 'monthly',
    this.defaultMonths = 12,
    this.defaultAmount = 0.0,
  });
}

class UpdateFeeType extends FeesEvent {
  final String id;
  final String name;
  final String? billingType;
  final int? defaultMonths;
  final double? defaultAmount;
  UpdateFeeType(
    this.id,
    this.name, {
    this.billingType,
    this.defaultMonths,
    this.defaultAmount,
  });
}

class DeleteFeeType extends FeesEvent {
  final String id;
  DeleteFeeType(this.id);
}

// Donation Types events
class AddDonationType extends FeesEvent {
  final String name;
  AddDonationType(this.name);
}

class UpdateDonationType extends FeesEvent {
  final String id;
  final String name;
  UpdateDonationType(this.id, this.name);
}

class DeleteDonationType extends FeesEvent {
  final String id;
  DeleteDonationType(this.id);
}

// Fee & Donation Deletion events
class DeleteFeePayment extends FeesEvent {
  final String id;
  DeleteFeePayment(this.id);
}

class DeleteDonation extends FeesEvent {
  final String id;
  DeleteDonation(this.id);
}

// --- States ---
abstract class FeesState {}

class FeesInitial extends FeesState {}

class FeesLoading extends FeesState {}

class FeesLoaded extends FeesState {
  final List<StudentFeeSummary> summaries;
  final List<Donation> donations;
  final List<DonationType> donationTypes;
  final List<FeeType> feeTypes;
  final String? actionMessage;
  
  FeesLoaded({
    required this.summaries,
    required this.donations,
    required this.donationTypes,
    required this.feeTypes,
    this.actionMessage,
  });

  FeesLoaded copyWith({
    List<StudentFeeSummary>? summaries,
    List<Donation>? donations,
    List<DonationType>? donationTypes,
    List<FeeType>? feeTypes,
    String? actionMessage,
  }) {
    return FeesLoaded(
      summaries: summaries ?? this.summaries,
      donations: donations ?? this.donations,
      donationTypes: donationTypes ?? this.donationTypes,
      feeTypes: feeTypes ?? this.feeTypes,
      actionMessage: actionMessage,
    );
  }
}

class FeesError extends FeesState {
  final String message;
  FeesError(this.message);
}

// --- BLoC ---
class FeesBloc extends Bloc<FeesEvent, FeesState> {
  final FeesRepository repository;

  FeesBloc({required this.repository}) : super(FeesInitial()) {
    on<LoadFeesData>(_onLoadFeesData);
    on<PayStudentFee>(_onPayStudentFee);
    on<RecordDonation>(_onRecordDonation);
    on<AddFeeType>(_onAddFeeType);
    on<UpdateFeeType>(_onUpdateFeeType);
    on<DeleteFeeType>(_onDeleteFeeType);
    on<AddDonationType>(_onAddDonationType);
    on<UpdateDonationType>(_onUpdateDonationType);
    on<DeleteDonationType>(_onDeleteDonationType);
    on<DeleteFeePayment>(_onDeleteFeePayment);
    on<DeleteDonation>(_onDeleteDonation);
  }

  Future<void> _reloadAll(Emitter<FeesState> emit, {String? message}) async {
    final summaries = await repository.getStudentFeeSummaries();
    final donations = await repository.getDonations();
    final donationTypes = await repository.getDonationTypes();
    final feeTypes = await repository.getFeeTypes();
    emit(FeesLoaded(
      summaries: summaries,
      donations: donations,
      donationTypes: donationTypes,
      feeTypes: feeTypes,
      actionMessage: message,
    ));
  }

  Future<void> _onLoadFeesData(LoadFeesData event, Emitter<FeesState> emit) async {
    emit(FeesLoading());
    try {
      await _reloadAll(emit);
    } catch (e) {
      emit(FeesError(e.toString()));
    }
  }

  Future<void> _onPayStudentFee(PayStudentFee event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.payFee(
        studentId: event.studentId,
        amount: event.amount,
        feeType: event.feeType,
        remarks: event.remarks,
        receiptNo: event.receiptNo,
      );
      await _reloadAll(emit, message: 'Fee payment recorded & SMS sent!');
    } catch (e) {
      emit(FeesError(e.toString()));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onRecordDonation(RecordDonation event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.recordDonation(
        receiptNo: event.receiptNo,
        donorName: event.donorName,
        donorPhone: event.donorPhone,
        village: event.village,
        taluka: event.taluka,
        district: event.district,
        state: event.state,
        country: event.country,
        pinCode: event.pinCode,
        amount: event.amount,
        donationType: event.donationType,
        paymentMethod: event.paymentMethod,
        paymentDate: event.paymentDate,
      );
      await _reloadAll(emit, message: 'Donation recorded successfully!');
    } catch (e) {
      emit(FeesError(e.toString()));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  // ─── Fee Types ─────────────────────────────────────────────────
  Future<void> _onAddFeeType(AddFeeType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.addFeeType(
        event.name,
        billingType: event.billingType,
        defaultMonths: event.defaultMonths,
        defaultAmount: event.defaultAmount,
      );
      await _reloadAll(emit, message: 'Fee type added!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateFeeType(UpdateFeeType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.updateFeeType(
        event.id,
        event.name,
        billingType: event.billingType,
        defaultMonths: event.defaultMonths,
        defaultAmount: event.defaultAmount,
      );
      await _reloadAll(emit, message: 'Fee type updated!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteFeeType(DeleteFeeType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteFeeType(event.id);
      await _reloadAll(emit, message: 'Fee type deleted!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  // ─── Donation Types ────────────────────────────────────────────
  Future<void> _onAddDonationType(AddDonationType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.addDonationType(event.name);
      await _reloadAll(emit, message: 'Donation category added!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateDonationType(UpdateDonationType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.updateDonationType(event.id, event.name);
      await _reloadAll(emit, message: 'Donation category updated!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteDonationType(DeleteDonationType event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteDonationType(event.id);
      await _reloadAll(emit, message: 'Donation category deleted!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  // ─── Delete Fee Payment & Donation Handlers ─────────────────────
  Future<void> _onDeleteFeePayment(DeleteFeePayment event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteFeePayment(event.id);
      await _reloadAll(emit, message: 'Fee payment entry deleted successfully!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteDonation(DeleteDonation event, Emitter<FeesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteDonation(event.id);
      await _reloadAll(emit, message: 'Donation record deleted successfully!');
    } catch (e) {
      emit(FeesError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is FeesLoaded) emit(currentState);
    }
  }
}
