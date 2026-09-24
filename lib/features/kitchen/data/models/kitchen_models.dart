class KitchenMenuItem {
  final String id;
  final String dayOfWeek;
  final String mealType;
  final String items;
  final String? notes;
  final String? updatedAt;

  KitchenMenuItem({
    required this.id,
    required this.dayOfWeek,
    required this.mealType,
    required this.items,
    this.notes,
    this.updatedAt,
  });

  factory KitchenMenuItem.fromJson(Map<String, dynamic> json) {
    return KitchenMenuItem(
      id: json['id'] ?? '',
      dayOfWeek: json['day_of_week'] ?? '',
      mealType: json['meal_type'] ?? '',
      items: json['items'] ?? '',
      notes: json['notes'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'day_of_week': dayOfWeek,
      'meal_type': mealType,
      'items': items,
      'notes': notes,
      'updated_at': updatedAt,
    };
  }
}

class StockItem {
  final String id;
  final String itemName;
  final double quantity;
  final String unit;
  final double minThreshold;
  final String? updatedAt;
  final double latestPrice;
  final double totalAmount;

  StockItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.minThreshold,
    this.updatedAt,
    this.latestPrice = 0.0,
    this.totalAmount = 0.0,
  });

  bool get isLowStock => quantity <= minThreshold;

  factory StockItem.fromJson(Map<String, dynamic> json) {
    return StockItem(
      id: json['id'] ?? '',
      itemName: json['item_name'] ?? '',
      quantity: (json['quantity'] ?? 0).toDouble(),
      unit: json['unit'] ?? 'kg',
      minThreshold: (json['min_threshold'] ?? 0).toDouble(),
      updatedAt: json['updated_at'],
      latestPrice: (json['latest_price'] ?? 0.0).toDouble(),
      totalAmount: (json['total_amount'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_name': itemName,
      'quantity': quantity,
      'unit': unit,
      'min_threshold': minThreshold,
      'updated_at': updatedAt,
      'latest_price': latestPrice,
      'total_amount': totalAmount,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class StockTransaction {
  final String id;
  final String stockId;
  final String transactionType; // 'In' or 'Out'
  final double quantity;
  final String unit;
  final String? remarks;
  final String transactionDate;
  final String? createdAt;
  final String? itemName;
  final String? stockUnit;

  StockTransaction({
    required this.id,
    required this.stockId,
    required this.transactionType,
    required this.quantity,
    required this.unit,
    this.remarks,
    required this.transactionDate,
    this.createdAt,
    this.itemName,
    this.stockUnit,
  });

  factory StockTransaction.fromJson(Map<String, dynamic> json) {
    return StockTransaction(
      id: json['id'] ?? '',
      stockId: json['stock_id'] ?? '',
      transactionType: json['transaction_type'] ?? 'In',
      quantity: (json['quantity'] ?? 0).toDouble(),
      unit: json['unit'] ?? 'kg',
      remarks: json['remarks'],
      transactionDate: json['transaction_date'] ?? '',
      createdAt: json['created_at'],
      itemName: json['item_name'],
      stockUnit: json['stock_unit'],
    );
  }
}

class KitchenExpense {
  final String id;
  final String itemName;
  final double amount;
  final String expenseDate;
  final String? remarks;
  final String? createdAt;

  KitchenExpense({
    required this.id,
    required this.itemName,
    required this.amount,
    required this.expenseDate,
    this.remarks,
    this.createdAt,
  });

  factory KitchenExpense.fromJson(Map<String, dynamic> json) {
    return KitchenExpense(
      id: json['id'] ?? '',
      itemName: json['item_name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      expenseDate: json['expense_date'] ?? '',
      remarks: json['remarks'],
      createdAt: json['created_at'],
    );
  }
}

class MealPlan {
  final String id;
  final String planDate;
  final String mealType;
  final String menuItems;
  final int expectedCount;
  final String status; // 'Planned', 'Prepared', 'Cancelled'
  final String? createdAt;

  MealPlan({
    required this.id,
    required this.planDate,
    required this.mealType,
    required this.menuItems,
    required this.expectedCount,
    required this.status,
    this.createdAt,
  });

  factory MealPlan.fromJson(Map<String, dynamic> json) {
    return MealPlan(
      id: json['id'] ?? '',
      planDate: json['plan_date'] ?? '',
      mealType: json['meal_type'] ?? '',
      menuItems: json['menu_items'] ?? '',
      expectedCount: json['expected_count'] ?? 0,
      status: json['status'] ?? 'Planned',
      createdAt: json['created_at'],
    );
  }
}
