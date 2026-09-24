import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/repositories/kitchen_repository.dart';
import '../../data/models/kitchen_models.dart';

// ─── EVENTS ────────────────────────────────────────────────────────
abstract class KitchenEvent {}

class LoadKitchenData extends KitchenEvent {}

class UpdateMenuItemEvent extends KitchenEvent {
  final String dayOfWeek;
  final String mealType;
  final String items;
  final String? notes;

  UpdateMenuItemEvent({
    required this.dayOfWeek,
    required this.mealType,
    required this.items,
    this.notes,
  });
}

class DeleteMenuItemEvent extends KitchenEvent {
  final String id;
  DeleteMenuItemEvent(this.id);
}

class AddStockItemEvent extends KitchenEvent {
  final String itemName;
  final double quantity;
  final String unit;
  final double minThreshold;

  AddStockItemEvent({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.minThreshold,
  });
}

class UpdateStockItemEvent extends KitchenEvent {
  final String id;
  final String itemName;
  final double minThreshold;
  final double quantity;
  final String unit;

  UpdateStockItemEvent({
    required this.id,
    required this.itemName,
    required this.minThreshold,
    required this.quantity,
    required this.unit,
  });
}

class DeleteStockItemEvent extends KitchenEvent {
  final String id;
  DeleteStockItemEvent(this.id);
}

class RecordStockTransactionEvent extends KitchenEvent {
  final String stockId;
  final String transactionType; // 'In' or 'Out'
  final double quantity;
  final String? remarks;

  RecordStockTransactionEvent({
    required this.stockId,
    required this.transactionType,
    required this.quantity,
    this.remarks,
  });
}

class IssueMealRationEvent extends KitchenEvent {
  final String mealName;
  final String issueDate;
  final List<Map<String, dynamic>> items;
  final String? remarks;

  IssueMealRationEvent({
    required this.mealName,
    required this.issueDate,
    required this.items,
    this.remarks,
  });
}

class IssueTodayMenuRationEvent extends KitchenEvent {
  final String dayOfWeek;
  final String issueDate;
  final String? remarks;
  final void Function(Map<String, dynamic> result) onSuccess;

  IssueTodayMenuRationEvent({
    required this.dayOfWeek,
    required this.issueDate,
    this.remarks,
    required this.onSuccess,
  });
}

class AddKitchenExpenseEvent extends KitchenEvent {
  final String itemName;
  final double amount;
  final String expenseDate;
  final String? remarks;

  AddKitchenExpenseEvent({
    required this.itemName,
    required this.amount,
    required this.expenseDate,
    this.remarks,
  });
}

class DeleteKitchenExpenseEvent extends KitchenEvent {
  final String id;
  final String? itemName;
  DeleteKitchenExpenseEvent(this.id, {this.itemName});
}

class CreateMealPlanEvent extends KitchenEvent {
  final String planDate;
  final String mealType;
  final String menuItems;
  final int expectedCount;

  CreateMealPlanEvent({
    required this.planDate,
    required this.mealType,
    required this.menuItems,
    required this.expectedCount,
  });
}

class UpdateMealPlanStatusEvent extends KitchenEvent {
  final String id;
  final String status;

  UpdateMealPlanStatusEvent({
    required this.id,
    required this.status,
  });
}

class DeleteMealPlanEvent extends KitchenEvent {
  final String id;
  DeleteMealPlanEvent(this.id);
}

// ─── STATES ────────────────────────────────────────────────────────
abstract class KitchenState {}

class KitchenInitial extends KitchenState {}

class KitchenLoading extends KitchenState {}

class KitchenLoaded extends KitchenState {
  final List<KitchenMenuItem> menuItems;
  final List<StockItem> stockItems;
  final List<StockTransaction> transactions;
  final List<KitchenExpense> expenses;
  final List<MealPlan> mealPlans;
  final String? actionMessage;

  KitchenLoaded({
    required this.menuItems,
    required this.stockItems,
    required this.transactions,
    required this.expenses,
    required this.mealPlans,
    this.actionMessage,
  });

  KitchenLoaded copyWith({
    List<KitchenMenuItem>? menuItems,
    List<StockItem>? stockItems,
    List<StockTransaction>? transactions,
    List<KitchenExpense>? expenses,
    List<MealPlan>? mealPlans,
    String? actionMessage,
  }) {
    return KitchenLoaded(
      menuItems: menuItems ?? this.menuItems,
      stockItems: stockItems ?? this.stockItems,
      transactions: transactions ?? this.transactions,
      expenses: expenses ?? this.expenses,
      mealPlans: mealPlans ?? this.mealPlans,
      actionMessage: actionMessage,
    );
  }
}

class KitchenError extends KitchenState {
  final String message;
  KitchenError(this.message);
}

// ─── BLOC ──────────────────────────────────────────────────────────
class KitchenBloc extends Bloc<KitchenEvent, KitchenState> {
  final KitchenRepository repository;

  KitchenBloc({required this.repository}) : super(KitchenInitial()) {
    on<LoadKitchenData>(_onLoadKitchenData);
    on<UpdateMenuItemEvent>(_onUpdateMenuItem);
    on<DeleteMenuItemEvent>(_onDeleteMenuItem);
    on<AddStockItemEvent>(_onAddStockItem);
    on<UpdateStockItemEvent>(_onUpdateStockItem);
    on<DeleteStockItemEvent>(_onDeleteStockItem);
    on<RecordStockTransactionEvent>(_onRecordStockTransaction);
    on<IssueMealRationEvent>(_onIssueMealRation);
    on<IssueTodayMenuRationEvent>(_onIssueTodayMenuRation);
    on<AddKitchenExpenseEvent>(_onAddKitchenExpense);
    on<DeleteKitchenExpenseEvent>(_onDeleteKitchenExpense);
    on<CreateMealPlanEvent>(_onCreateMealPlan);
    on<UpdateMealPlanStatusEvent>(_onUpdateMealPlanStatus);
    on<DeleteMealPlanEvent>(_onDeleteMealPlan);
  }

  Future<void> _reloadData(Emitter<KitchenState> emit, {String? message}) async {
    final menu = await repository.getMenu();
    final stock = await repository.getStock();
    final trans = await repository.getStockTransactions();
    final exp = await repository.getExpenses();
    final plans = await repository.getMealPlans();

    emit(KitchenLoaded(
      menuItems: menu,
      stockItems: stock,
      transactions: trans,
      expenses: exp,
      mealPlans: plans,
      actionMessage: message,
    ));
  }

  Future<void> _onLoadKitchenData(LoadKitchenData event, Emitter<KitchenState> emit) async {
    emit(KitchenLoading());
    try {
      await _reloadData(emit);
    } catch (e) {
      emit(KitchenError(e.toString()));
    }
  }

  Future<void> _onUpdateMenuItem(UpdateMenuItemEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.updateMenuItem(
        dayOfWeek: event.dayOfWeek,
        mealType: event.mealType,
        items: event.items,
        notes: event.notes,
      );
      await _reloadData(emit, message: 'Menu updated successfully!');
    } catch (e) {
      emit(KitchenError(e.toString()));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteMenuItem(DeleteMenuItemEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.deleteMenuItem(event.id);
      await _reloadData(emit, message: 'Menu item deleted successfully!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onAddStockItem(AddStockItemEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.createStockItem(
        itemName: event.itemName,
        quantity: event.quantity,
        unit: event.unit,
        minThreshold: event.minThreshold,
      );
      await _reloadData(emit, message: 'Stock item added!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateStockItem(UpdateStockItemEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.updateStockItem(
        event.id,
        itemName: event.itemName,
        minThreshold: event.minThreshold,
        quantity: event.quantity,
        unit: event.unit,
      );
      await _reloadData(emit, message: 'Stock item updated!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteStockItem(DeleteStockItemEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.deleteStockItem(event.id);
      await _reloadData(emit, message: 'Stock item deleted!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onRecordStockTransaction(RecordStockTransactionEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.recordStockTransaction(
        stockId: event.stockId,
        transactionType: event.transactionType,
        quantity: event.quantity,
        remarks: event.remarks,
      );
      await _reloadData(emit, message: 'Stock transaction recorded!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onIssueMealRation(IssueMealRationEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.issueMealRation(
        mealName: event.mealName,
        issueDate: event.issueDate,
        items: event.items,
        remarks: event.remarks,
      );
      await _reloadData(emit, message: 'Ration issued and expense logged successfully!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onIssueTodayMenuRation(IssueTodayMenuRationEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      final result = await repository.issueTodayMenuRation(
        dayOfWeek: event.dayOfWeek,
        issueDate: event.issueDate,
        remarks: event.remarks,
      );
      await _reloadData(emit, message: 'Today\'s menu ration issued and expense logged successfully!');
      event.onSuccess(result);
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onAddKitchenExpense(AddKitchenExpenseEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.createExpense(
        itemName: event.itemName,
        amount: event.amount,
        expenseDate: event.expenseDate,
        remarks: event.remarks,
      );
      await _reloadData(emit, message: 'Kitchen expense added!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteKitchenExpense(DeleteKitchenExpenseEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.deleteExpense(event.id, itemName: event.itemName);
      await _reloadData(emit, message: 'Expense deleted!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onCreateMealPlan(CreateMealPlanEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.createMealPlan(
        planDate: event.planDate,
        mealType: event.mealType,
        menuItems: event.menuItems,
        expectedCount: event.expectedCount,
      );
      await _reloadData(emit, message: 'Meal plan created!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onUpdateMealPlanStatus(UpdateMealPlanStatusEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.updateMealPlan(
        event.id,
        status: event.status,
      );
      await _reloadData(emit, message: 'Meal plan status updated!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }

  Future<void> _onDeleteMealPlan(DeleteMealPlanEvent event, Emitter<KitchenState> emit) async {
    final currentState = state;
    try {
      await repository.deleteMealPlan(event.id);
      await _reloadData(emit, message: 'Meal plan deleted!');
    } catch (e) {
      emit(KitchenError(e.toString().replaceAll('Exception: ', '')));
      if (currentState is KitchenLoaded) emit(currentState);
    }
  }
}
