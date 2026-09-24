import '../../../../core/network/api_client.dart';
import '../models/purchases_models.dart';

class PurchasesRepository {
  final ApiClient _apiClient;

  PurchasesRepository(this._apiClient);

  // ─── TRANSACTIONS (PURCHASES & SELLS) ─────────────────────────────────
  Future<List<PurchaseSellTransaction>> getTransactions() async {
    try {
      final response = await _apiClient.get('/purchases');
      final List data = response.data ?? [];
      return data.map((json) => PurchaseSellTransaction.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createTransaction({
    required String receiptNo,
    required String type, // 'Purchase' or 'Sell'
    required String category,
    required String transactionDate,
    String? contactPerson,
    String? remarks,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _apiClient.post(
        '/purchases',
        data: {
          'receipt_no': receiptNo,
          'type': type,
          'category': category,
          'transaction_date': transactionDate,
          'contact_person': contactPerson,
          'remarks': remarks,
          'items': items,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateTransaction({
    required String id,
    required String receiptNo,
    required String type, // 'Purchase' or 'Sell'
    required String category,
    required String transactionDate,
    String? contactPerson,
    String? remarks,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _apiClient.put(
        '/purchases/$id',
        data: {
          'receipt_no': receiptNo,
          'type': type,
          'category': category,
          'transaction_date': transactionDate,
          'contact_person': contactPerson,
          'remarks': remarks,
          'items': items,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteTransaction(String id, {String? itemName}) async {
    try {
      final String url = itemName != null 
          ? '/purchases/$id?itemName=${Uri.encodeComponent(itemName)}' 
          : '/purchases/$id';
      await _apiClient.delete(url);
    } catch (e) {
      rethrow;
    }
  }

  // ─── UNIT OPTIONS MANAGEMENT ──────────────────────────────────────────
  Future<List<UnitModel>> getUnits() async {
    try {
      final response = await _apiClient.get('/purchases/units');
      final List data = response.data ?? [];
      return data.map((json) => UnitModel.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createUnit(String name) async {
    try {
      await _apiClient.post(
        '/purchases/units',
        data: {'name': name},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteUnit(String id) async {
    try {
      await _apiClient.delete('/purchases/units/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── CATEGORY OPTIONS MANAGEMENT ──────────────────────────────────────
  Future<List<CategoryModel>> getCategories() async {
    try {
      final response = await _apiClient.get('/purchases/categories');
      final List data = response.data ?? [];
      return data.map((json) => CategoryModel.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> createCategory(String name) async {
    try {
      await _apiClient.post(
        '/purchases/categories',
        data: {'name': name},
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteCategory(String id) async {
    try {
      await _apiClient.delete('/purchases/categories/$id');
    } catch (e) {
      rethrow;
    }
  }

  // ─── GENERAL / ASSET STOCK MANAGEMENT ─────────────────────────────────
  Future<List<GeneralStockItem>> getGeneralStock() async {
    try {
      final response = await _apiClient.get('/purchases/general-stock');
      final List data = response.data ?? [];
      return data.map((json) => GeneralStockItem.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> issueGeneralStock({
    required String receiptNo,
    required String transactionDate,
    required String category,
    String? contactPerson,
    String? remarks,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      await _apiClient.post(
        '/purchases/general-stock/issue',
        data: {
          'receipt_no': receiptNo,
          'transaction_date': transactionDate,
          'category': category,
          'contact_person': contactPerson,
          'remarks': remarks,
          'items': items,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateGeneralStockItem({
    required String id,
    required String itemName,
    required double minThreshold,
    required double quantity,
    required String unit,
    required String category,
  }) async {
    try {
      await _apiClient.put(
        '/purchases/general-stock/$id',
        data: {
          'item_name': itemName,
          'min_threshold': minThreshold,
          'quantity': quantity,
          'unit': unit,
          'category': category,
        },
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteGeneralStockItem(String id) async {
    try {
      await _apiClient.delete('/purchases/general-stock/$id');
    } catch (e) {
      rethrow;
    }
  }
}
