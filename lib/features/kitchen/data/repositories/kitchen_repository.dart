import '../../../../core/network/api_client.dart';
import '../models/kitchen_models.dart';

class KitchenRepository {
  final ApiClient _apiClient;

  KitchenRepository(this._apiClient);

  // ─── DAILY FOOD MENU ───────────────────────────────────────────────
  Future<List<KitchenMenuItem>> getMenu() async {
    try {
      final response = await _apiClient.get('/kitchen/menu');
      final List data = response.data ?? [];
      return data.map((json) => KitchenMenuItem.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateMenuItem({
    required String dayOfWeek,
    required String mealType,
    required String items,
    String? notes,
  }) async {
    try {
      await _apiClient.put(
        '/kitchen/menu',
        data: {
          'day_of_week': dayOfWeek,
          'meal_type': mealType,
          'items': items,
          'notes': notes,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMenuItem(String id) async {
    try {
      await _apiClient.delete('/kitchen/menu/$id');
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> issueTodayMenuRation({
    required String dayOfWeek,
    required String issueDate,
    String? remarks,
  }) async {
    try {
      final response = await _apiClient.post(
        '/kitchen/menu/issue-today',
        data: {
          'day_of_week': dayOfWeek,
          'issue_date': issueDate,
          'remarks': remarks,
        },
      );
      return response.data ?? {};
    } catch (e) {
      rethrow;
    }
  }

  // ─── RATION STOCK ──────────────────────────────────────────────────
  Future<List<StockItem>> getStock() async {
    try {
      final response = await _apiClient.get('/kitchen/stock');
      final List data = response.data ?? [];
      return data.map((json) => StockItem.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<StockItem> createStockItem({
    required String itemName,
    required double quantity,
    required String unit,
    required double minThreshold,
  }) async {
    try {
      final response = await _apiClient.post(
        '/kitchen/stock',
        data: {
          'item_name': itemName,
          'quantity': quantity,
          'unit': unit,
          'min_threshold': minThreshold,
        },
      );
      return StockItem.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateStockItem(
    String id, {
    String? itemName,
    double? minThreshold,
    double? quantity,
    String? unit,
  }) async {
    try {
      await _apiClient.put(
        '/kitchen/stock/$id',
        data: {
          if (itemName != null) 'item_name': itemName,
          if (minThreshold != null) 'min_threshold': minThreshold,
          if (quantity != null) 'quantity': quantity,
          if (unit != null) 'unit': unit,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteStockItem(String id) async {
    try {
      await _apiClient.delete('/kitchen/stock/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── STOCK TRANSACTIONS ────────────────────────────────────────────
  Future<List<StockTransaction>> getStockTransactions() async {
    try {
      final response = await _apiClient.get('/kitchen/stock/transactions');
      final List data = response.data ?? [];
      return data.map((json) => StockTransaction.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> recordStockTransaction({
    required String stockId,
    required String transactionType, // 'In' or 'Out'
    required double quantity,
    String? remarks,
  }) async {
    try {
      await _apiClient.post(
        '/kitchen/stock/transactions',
        data: {
          'stock_id': stockId,
          'transaction_type': transactionType,
          'quantity': quantity,
          'remarks': remarks,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> issueMealRation({
    required String mealName,
    required String issueDate,
    required List<Map<String, dynamic>> items,
    String? remarks,
  }) async {
    try {
      await _apiClient.post(
        '/kitchen/stock/issue-meal',
        data: {
          'meal_name': mealName,
          'issue_date': issueDate,
          'items': items,
          'remarks': remarks,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  // ─── EXPENSES ──────────────────────────────────────────────────────
  Future<List<KitchenExpense>> getExpenses() async {
    try {
      final response = await _apiClient.get('/kitchen/expenses');
      final List data = response.data ?? [];
      return data.map((json) => KitchenExpense.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<KitchenExpense> createExpense({
    required String itemName,
    required double amount,
    required String expenseDate,
    String? remarks,
  }) async {
    try {
      final response = await _apiClient.post(
        '/kitchen/expenses',
        data: {
          'item_name': itemName,
          'amount': amount,
          'expense_date': expenseDate,
          'remarks': remarks,
        },
      );
      return KitchenExpense.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteExpense(String id, {String? itemName}) async {
    try {
      final String url = itemName != null 
          ? '/kitchen/expenses/$id?itemName=${Uri.encodeComponent(itemName)}' 
          : '/kitchen/expenses/$id';
      await _apiClient.delete(url);
    } catch (e) {
      rethrow;
    }
  }

  // ─── MEAL PLANNING ─────────────────────────────────────────────────
  Future<List<MealPlan>> getMealPlans() async {
    try {
      final response = await _apiClient.get('/kitchen/meal-plans');
      final List data = response.data ?? [];
      return data.map((json) => MealPlan.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<MealPlan> createMealPlan({
    required String planDate,
    required String mealType,
    required String menuItems,
    required int expectedCount,
  }) async {
    try {
      final response = await _apiClient.post(
        '/kitchen/meal-plans',
        data: {
          'plan_date': planDate,
          'meal_type': mealType,
          'menu_items': menuItems,
          'expected_count': expectedCount,
        },
      );
      return MealPlan.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateMealPlan(
    String id, {
    String? status,
    String? menuItems,
    int? expectedCount,
  }) async {
    try {
      await _apiClient.put(
        '/kitchen/meal-plans/$id',
        data: {
          if (status != null) 'status': status,
          if (menuItems != null) 'menu_items': menuItems,
          if (expectedCount != null) 'expected_count': expectedCount,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteMealPlan(String id) async {
    try {
      await _apiClient.delete('/kitchen/meal-plans/$id');
    } catch (e) {
      rethrow;
    }
  }
}
