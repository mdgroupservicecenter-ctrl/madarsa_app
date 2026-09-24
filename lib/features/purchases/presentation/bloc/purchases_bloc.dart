import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/purchases_repository.dart';
import '../../data/models/purchases_models.dart';

// ─── EVENTS ────────────────────────────────────────────────────────
abstract class PurchasesEvent {}

class LoadPurchasesData extends PurchasesEvent {}

class AddTransactionEvent extends PurchasesEvent {
  final String receiptNo;
  final String type;
  final String category;
  final String transactionDate;
  final String? contactPerson;
  final String? remarks;
  final List<Map<String, dynamic>> items;

  AddTransactionEvent({
    required this.receiptNo,
    required this.type,
    required this.category,
    required this.transactionDate,
    this.contactPerson,
    this.remarks,
    required this.items,
  });
}

class UpdateTransactionEvent extends PurchasesEvent {
  final String id;
  final String receiptNo;
  final String type;
  final String category;
  final String transactionDate;
  final String? contactPerson;
  final String? remarks;
  final List<Map<String, dynamic>> items;

  UpdateTransactionEvent({
    required this.id,
    required this.receiptNo,
    required this.type,
    required this.category,
    required this.transactionDate,
    this.contactPerson,
    this.remarks,
    required this.items,
  });
}

class DeleteTransactionEvent extends PurchasesEvent {
  final String id;
  final String? itemName;
  DeleteTransactionEvent(this.id, {this.itemName});
}

class AddUnitEvent extends PurchasesEvent {
  final String name;
  AddUnitEvent(this.name);
}

class DeleteUnitEvent extends PurchasesEvent {
  final String id;
  DeleteUnitEvent(this.id);
}

class AddCategoryEvent extends PurchasesEvent {
  final String name;
  AddCategoryEvent(this.name);
}

class DeleteCategoryEvent extends PurchasesEvent {
  final String id;
  DeleteCategoryEvent(this.id);
}

class IssueGeneralStockEvent extends PurchasesEvent {
  final String receiptNo;
  final String transactionDate;
  final String category;
  final String? contactPerson;
  final String? remarks;
  final List<Map<String, dynamic>> items;

  IssueGeneralStockEvent({
    required this.receiptNo,
    required this.transactionDate,
    required this.category,
    this.contactPerson,
    this.remarks,
    required this.items,
  });
}

class UpdateGeneralStockItemEvent extends PurchasesEvent {
  final String id;
  final String itemName;
  final double minThreshold;
  final double quantity;
  final String unit;
  final String category;

  UpdateGeneralStockItemEvent({
    required this.id,
    required this.itemName,
    required this.minThreshold,
    required this.quantity,
    required this.unit,
    required this.category,
  });
}

class DeleteGeneralStockItemEvent extends PurchasesEvent {
  final String id;
  DeleteGeneralStockItemEvent(this.id);
}

// ─── STATES ────────────────────────────────────────────────────────
abstract class PurchasesState {}

class PurchasesInitial extends PurchasesState {}

class PurchasesLoading extends PurchasesState {}

class PurchasesLoaded extends PurchasesState {
  final List<PurchaseSellTransaction> transactions;
  final List<UnitModel> units;
  final List<CategoryModel> categories;
  final List<GeneralStockItem> generalStock;
  final String? actionMessage;

  PurchasesLoaded({
    required this.transactions,
    required this.units,
    required this.categories,
    required this.generalStock,
    this.actionMessage,
  });

  PurchasesLoaded copyWith({
    List<PurchaseSellTransaction>? transactions,
    List<UnitModel>? units,
    List<CategoryModel>? categories,
    List<GeneralStockItem>? generalStock,
    String? actionMessage,
  }) {
    return PurchasesLoaded(
      transactions: transactions ?? this.transactions,
      units: units ?? this.units,
      categories: categories ?? this.categories,
      generalStock: generalStock ?? this.generalStock,
      actionMessage: actionMessage,
    );
  }
}

class PurchasesError extends PurchasesState {
  final String message;
  PurchasesError(this.message);
}

// ─── BLOC ──────────────────────────────────────────────────────────
class PurchasesBloc extends Bloc<PurchasesEvent, PurchasesState> {
  final PurchasesRepository repository;

  PurchasesBloc({required this.repository}) : super(PurchasesInitial()) {
    on<LoadPurchasesData>(_onLoadPurchasesData);
    on<AddTransactionEvent>(_onAddTransaction);
    on<UpdateTransactionEvent>(_onUpdateTransaction);
    on<DeleteTransactionEvent>(_onDeleteTransaction);
    on<AddUnitEvent>(_onAddUnit);
    on<DeleteUnitEvent>(_onDeleteUnit);
    on<AddCategoryEvent>(_onAddCategory);
    on<DeleteCategoryEvent>(_onDeleteCategory);
    on<IssueGeneralStockEvent>(_onIssueGeneralStock);
    on<UpdateGeneralStockItemEvent>(_onUpdateGeneralStockItem);
    on<DeleteGeneralStockItemEvent>(_onDeleteGeneralStockItem);
  }

  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      return error.response?.data?['message'] ??
          error.response?.data?['error'] ??
          error.message ??
          'Server error occurred.';
    }
    return error.toString().replaceAll('Exception: ', '');
  }

  Future<void> _reloadData(Emitter<PurchasesState> emit, {String? message}) async {
    final transactionsList = await repository.getTransactions();
    final unitsList = await repository.getUnits();
    final categoriesList = await repository.getCategories();
    final generalStockList = await repository.getGeneralStock();

    emit(PurchasesLoaded(
      transactions: transactionsList,
      units: unitsList,
      categories: categoriesList,
      generalStock: generalStockList,
      actionMessage: message,
    ));
  }

  Future<void> _onLoadPurchasesData(LoadPurchasesData event, Emitter<PurchasesState> emit) async {
    emit(PurchasesLoading());
    try {
      await _reloadData(emit);
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
    }
  }

  Future<void> _onAddTransaction(AddTransactionEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.createTransaction(
        receiptNo: event.receiptNo,
        type: event.type,
        category: event.category,
        transactionDate: event.transactionDate,
        contactPerson: event.contactPerson,
        remarks: event.remarks,
        items: event.items,
      );
      await _reloadData(emit, message: 'Transaction logged successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateTransaction(UpdateTransactionEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.updateTransaction(
        id: event.id,
        receiptNo: event.receiptNo,
        type: event.type,
        category: event.category,
        transactionDate: event.transactionDate,
        contactPerson: event.contactPerson,
        remarks: event.remarks,
        items: event.items,
      );
      await _reloadData(emit, message: 'Transaction updated successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteTransaction(DeleteTransactionEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteTransaction(event.id, itemName: event.itemName);
      await _reloadData(emit, message: 'Transaction deleted successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onAddUnit(AddUnitEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.createUnit(event.name);
      await _reloadData(emit, message: 'Unit added successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteUnit(DeleteUnitEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteUnit(event.id);
      await _reloadData(emit, message: 'Unit deleted successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onAddCategory(AddCategoryEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.createCategory(event.name);
      await _reloadData(emit, message: 'Category added successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteCategory(DeleteCategoryEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteCategory(event.id);
      await _reloadData(emit, message: 'Category deleted successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onIssueGeneralStock(IssueGeneralStockEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.issueGeneralStock(
        receiptNo: event.receiptNo,
        transactionDate: event.transactionDate,
        category: event.category,
        contactPerson: event.contactPerson,
        remarks: event.remarks,
        items: event.items,
      );
      await _reloadData(emit, message: 'Stock items marked In Use successfully!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateGeneralStockItem(UpdateGeneralStockItemEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.updateGeneralStockItem(
        id: event.id,
        itemName: event.itemName,
        minThreshold: event.minThreshold,
        quantity: event.quantity,
        unit: event.unit,
        category: event.category,
      );
      await _reloadData(emit, message: 'General stock item updated!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteGeneralStockItem(DeleteGeneralStockItemEvent event, Emitter<PurchasesState> emit) async {
    final currentState = state;
    try {
      await repository.deleteGeneralStockItem(event.id);
      await _reloadData(emit, message: 'General stock item deleted!');
    } catch (e) {
      emit(PurchasesError(_getErrorMessage(e)));
      if (currentState is PurchasesLoaded) emit(currentState);
    }
  }
}
