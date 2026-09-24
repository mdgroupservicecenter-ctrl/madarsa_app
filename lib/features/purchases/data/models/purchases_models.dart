class PurchaseSellTransaction {
  final String id;
  final String receiptNo;
  final String type; // 'Purchase' or 'Sell'
  final String category;
  final String transactionDate;
  final String? contactPerson;
  final double totalPrice;
  final String? remarks;
  final List<TransactionItem> items;
  final String? createdAt;

  PurchaseSellTransaction({
    required this.id,
    required this.receiptNo,
    required this.type,
    required this.category,
    required this.transactionDate,
    this.contactPerson,
    required this.totalPrice,
    this.remarks,
    required this.items,
    this.createdAt,
  });

  factory PurchaseSellTransaction.fromJson(Map<String, dynamic> json) {
    var list = json['items'] as List? ?? [];
    List<TransactionItem> itemList = list.map((i) => TransactionItem.fromJson(i)).toList();

    return PurchaseSellTransaction(
      id: json['id']?.toString() ?? '',
      receiptNo: json['receipt_no']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Purchase',
      category: json['category']?.toString() ?? 'Other',
      transactionDate: json['transaction_date']?.toString() ?? '',
      contactPerson: json['contact_person']?.toString(),
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0') ?? 0.0,
      remarks: json['remarks']?.toString(),
      items: itemList,
      createdAt: json['created_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'receipt_no': receiptNo,
      'type': type,
      'category': category,
      'transaction_date': transactionDate,
      'contact_person': contactPerson,
      'total_price': totalPrice,
      'remarks': remarks,
      'items': items.map((i) => i.toJson()).toList(),
      'created_at': createdAt,
    };
  }
}

class TransactionItem {
  final String itemName;
  final double quantity;
  final String unit;
  final double pricePerUnit;
  final double totalPrice;
  final double? costPricePerUnit;
  final double? costTotalPrice;
  final double? profitLoss;
  final double? discountAmount;
  final double? discountPercent;

  TransactionItem({
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.totalPrice,
    this.costPricePerUnit,
    this.costTotalPrice,
    this.profitLoss,
    this.discountAmount,
    this.discountPercent,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      itemName: json['item_name']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0.0,
      unit: json['unit']?.toString() ?? '',
      pricePerUnit: double.tryParse(json['price_per_unit']?.toString() ?? '0') ?? 0.0,
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0') ?? 0.0,
      costPricePerUnit: json['cost_price_per_unit'] != null 
          ? double.tryParse(json['cost_price_per_unit'].toString()) 
          : null,
      costTotalPrice: json['cost_total_price'] != null 
          ? double.tryParse(json['cost_total_price'].toString()) 
          : null,
      profitLoss: json['profit_loss'] != null 
          ? double.tryParse(json['profit_loss'].toString()) 
          : null,
      discountAmount: json['discount_amount'] != null 
          ? double.tryParse(json['discount_amount'].toString()) 
          : null,
      discountPercent: json['discount_percent'] != null 
          ? double.tryParse(json['discount_percent'].toString()) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'item_name': itemName,
      'quantity': quantity,
      'unit': unit,
      'price_per_unit': pricePerUnit,
      'total_price': totalPrice,
      if (costPricePerUnit != null) 'cost_price_per_unit': costPricePerUnit,
      if (costTotalPrice != null) 'cost_total_price': costTotalPrice,
      if (profitLoss != null) 'profit_loss': profitLoss,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (discountPercent != null) 'discount_percent': discountPercent,
    };
  }
}

class UnitModel {
  final String id;
  final String name;

  UnitModel({
    required this.id,
    required this.name,
  });

  factory UnitModel.fromJson(Map<String, dynamic> json) {
    return UnitModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class CategoryModel {
  final String id;
  final String name;

  CategoryModel({
    required this.id,
    required this.name,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

class GeneralStockItem {
  final String id;
  final String itemName;
  final double quantity;
  final String unit;
  final String category;
  final double minThreshold;
  final double latestPrice;
  final double totalAmount;

  GeneralStockItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.category,
    required this.minThreshold,
    this.latestPrice = 0.0,
    this.totalAmount = 0.0,
  });

  factory GeneralStockItem.fromJson(Map<String, dynamic> json) {
    return GeneralStockItem(
      id: json['id']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0.0,
      unit: json['unit']?.toString() ?? 'pcs',
      category: json['category']?.toString() ?? 'General',
      minThreshold: double.tryParse(json['min_threshold']?.toString() ?? '0') ?? 0.0,
      latestPrice: double.tryParse(json['latest_price']?.toString() ?? '0') ?? 0.0,
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'item_name': itemName,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'min_threshold': minThreshold,
      'latest_price': latestPrice,
      'total_amount': totalAmount,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneralStockItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
