import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/kitchen_bloc.dart';
import '../../data/models/kitchen_models.dart';
import '../../../purchases/presentation/bloc/purchases_bloc.dart';
import '../../../purchases/data/models/purchases_models.dart';
import '../../../purchases/presentation/screens/purchases_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> with SingleTickerProviderStateMixin {
  Widget _buildResponsiveRow(BuildContext context, Widget child1, Widget child2) {
    if (context.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child1,
          const SizedBox(height: 12),
          child2,
        ],
      );
    } else {
      return Row(
        children: [
          Expanded(child: child1),
          const SizedBox(width: 12),
          Expanded(child: child2),
        ],
      );
    }
  }

  late TabController _tabController;
  String _searchQuery = '';
  String _kitchenSubTab = 'menu'; // 'menu', 'stock', 'expenses'
  String _generalSubTab = 'stock'; // 'stock', 'expenses'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<KitchenBloc>().add(LoadKitchenData());
    context.read<PurchasesBloc>().add(LoadPurchasesData());
    
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _searchCtrl.clear();
          _searchQuery = '';
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MultiBlocListener(
      listeners: [
        BlocListener<KitchenBloc, KitchenState>(
          listener: (context, state) {
            if (state is KitchenLoaded && state.actionMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.actionMessage!),
                  backgroundColor: AppTheme.primaryColor,
                ),
              );
            }
          },
        ),
        BlocListener<PurchasesBloc, PurchasesState>(
          listener: (context, state) {
            if (state is PurchasesLoaded) {
              // Refresh kitchen stock levels when transactions (purchases/sales) update
              context.read<KitchenBloc>().add(LoadKitchenData());
              if (state.actionMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.actionMessage!),
                    backgroundColor: AppTheme.primaryColor,
                  ),
                );
              }
            }
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 20),
              _buildTabBarContainer(isDark),
              const SizedBox(height: 20),
              Expanded(
                child: BlocBuilder<KitchenBloc, KitchenState>(
                  builder: (context, kitchenState) {
                    return BlocBuilder<PurchasesBloc, PurchasesState>(
                      builder: (context, purchasesState) {
                        if (kitchenState is KitchenLoading || purchasesState is PurchasesLoading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (kitchenState is KitchenError) {
                          return _buildErrorState(kitchenState.message);
                        }
                        if (purchasesState is PurchasesError) {
                          return _buildErrorState(purchasesState.message);
                        }
                        if (kitchenState is KitchenLoaded && purchasesState is PurchasesLoaded) {
                          return TabBarView(
                            controller: _tabController,
                            children: [
                              _buildKitchenTab(kitchenState, purchasesState, isDark),
                              _buildGeneralTab(kitchenState, purchasesState, isDark),
                              _buildSellTab(kitchenState, purchasesState, isDark),
                            ],
                          );
                        }
                        return const SizedBox();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('expense_tracking'),
                style: AppTheme.getFontStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                context.tr('expense_tracking_subtitle'),
                style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBarContainer(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark
            ? Colors.grey.shade400
            : Colors.grey.shade600,
        labelStyle: AppTheme.getFontStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTheme.getFontStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        tabs: [
          Tab(text: context.tr('kitchen')),
          Tab(text: context.tr('general')),
          Tab(text: context.tr('sell')),
        ],
      ),
    );
  }

  Widget _buildKitchenTab(KitchenLoaded kitchenState, PurchasesLoaded purchasesState, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        final purchasedItemNames = purchasesState.transactions
            .where((t) => t.type == 'Purchase' && t.category.toLowerCase() == 'ration')
            .expand((t) => t.items.map((i) => i.itemName.toLowerCase().trim()))
            .toSet();

        final activeRationItems = kitchenState.stockItems.where((item) {
          return purchasedItemNames.contains(item.itemName.toLowerCase().trim());
        }).toList();

        final totalExpenses = kitchenState.expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
        final totalRationValuation = activeRationItems.fold<double>(0.0, (sum, item) => sum + item.totalAmount);
        final rationCount = activeRationItems.length;
        final lowRationCount = activeRationItems.where((item) => item.quantity <= item.minThreshold).length;

        final stats = [
          (
            label: context.tr('kitchen_expenses'),
            value: '₹${totalExpenses.toStringAsFixed(0)}',
            icon: Icons.kitchen_rounded,
            color: const Color(0xFF0D6B4E),
          ),
          (
            label: context.tr('ration_value'),
            value: '₹${totalRationValuation.toStringAsFixed(0)}',
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFF1565C0),
          ),
          (
            label: context.tr('ration_items'),
            value: rationCount.toString(),
            icon: Icons.food_bank_rounded,
            color: const Color(0xFF6A1B9A),
          ),
          (
            label: context.tr('low_stock'),
            value: lowRationCount.toString(),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFE65100),
          ),
        ];

        Widget headerAction;
        String title = '';
        String subtitle = '';
        
        if (_kitchenSubTab == 'menu') {
          title = context.tr('daily_food_menu');
          subtitle = context.tr('daily_food_menu_desc');
          headerAction = FilledButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AddEditMenuDialog(
                  meal: null,
                  stockItems: kitchenState.stockItems,
                  bloc: context.read<KitchenBloc>(),
                ),
              );
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(context.tr('add_menu_item'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else if (_kitchenSubTab == 'stock') {
          title = context.tr('ration_stock');
          subtitle = context.tr('ration_stock_desc');
          headerAction = const SizedBox.shrink();
        } else {
          title = context.tr('kitchen_expenses');
          subtitle = context.tr('kitchen_expenses_desc');
          headerAction = FilledButton.icon(
            onPressed: () => _showLogKitchenConsumptionDialog(kitchenState),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(context.tr('log_kitchen_expense'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSubTabChip(
                  context: context,
                  label: context.tr('daily_food_menu'),
                  isSelected: _kitchenSubTab == 'menu',
                  onSelected: () => setState(() => _kitchenSubTab = 'menu'),
                  isDark: isDark,
                ),
                _buildSubTabChip(
                  context: context,
                  label: context.tr('ration_stock'),
                  isSelected: _kitchenSubTab == 'stock',
                  onSelected: () => setState(() => _kitchenSubTab = 'stock'),
                  isDark: isDark,
                ),
                _buildSubTabChip(
                  context: context,
                  label: context.tr('kitchen_expenses'),
                  isSelected: _kitchenSubTab == 'expenses',
                  onSelected: () => setState(() => _kitchenSubTab = 'expenses'),
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.getFontStyle(
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                headerAction,
              ],
            ),
            const SizedBox(height: 16),

            isCompact
                ? GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: stats
                        .map(
                          (s) => _MiniStat(
                            label: s.label,
                            value: s.value,
                            icon: s.icon,
                            color: s.color,
                            isDark: isDark,
                          ),
                        )
                        .toList(),
                  )
                : Row(
                    children: stats
                        .map(
                          (s) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _MiniStat(
                                label: s.label,
                                value: s.value,
                                icon: s.icon,
                                color: s.color,
                                isDark: isDark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 16),

            Expanded(
              child: _kitchenSubTab == 'menu'
                  ? _buildDailyMenuTab(kitchenState, isDark)
                  : _kitchenSubTab == 'stock'
                      ? _buildRationStockTab(kitchenState, purchasesState, isDark)
                      : _buildExpensesTab(kitchenState, isDark),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGeneralTab(KitchenLoaded kitchenState, PurchasesLoaded purchasesState, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        final purchasedGeneralItemNames = purchasesState.transactions
            .where((t) => t.type == 'Purchase' && t.category.toLowerCase() != 'ration')
            .expand((t) => t.items.map((i) => i.itemName.toLowerCase().trim()))
            .toSet();

        final activeGeneralItems = purchasesState.generalStock.where((item) {
          return purchasedGeneralItemNames.contains(item.itemName.toLowerCase().trim());
        }).toList();

        final totalConsumption = purchasesState.transactions
            .where((t) => t.type == 'Issue')
            .fold<double>(0.0, (sum, t) => sum + t.totalPrice);
        final totalGeneralValuation = activeGeneralItems
            .fold<double>(0.0, (sum, item) => sum + item.totalAmount);
        final generalCount = activeGeneralItems.length;
        final lowGeneralCount = activeGeneralItems
            .where((item) => item.quantity <= item.minThreshold)
            .length;

        final stats = [
          (
            label: context.tr('general_expenses'),
            value: '₹${totalConsumption.toStringAsFixed(0)}',
            icon: Icons.outbox_rounded,
            color: const Color(0xFFC62828),
          ),
          (
            label: context.tr('stock_value'),
            value: '₹${totalGeneralValuation.toStringAsFixed(0)}',
            icon: Icons.inventory_rounded,
            color: const Color(0xFF1565C0),
          ),
          (
            label: context.tr('general_assets'),
            value: generalCount.toString(),
            icon: Icons.widgets_rounded,
            color: const Color(0xFF6A1B9A),
          ),
          (
            label: context.tr('low_assets'),
            value: lowGeneralCount.toString(),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFE65100),
          ),
        ];

        Widget headerAction;
        String title = '';
        String subtitle = '';

        if (_generalSubTab == 'stock') {
          title = context.tr('general_stock');
          subtitle = context.tr('general_stock_desc');
          headerAction = const SizedBox.shrink();
        } else {
          title = context.tr('general_expenses');
          subtitle = context.tr('general_expenses_desc');
          headerAction = FilledButton.icon(
            onPressed: () => _showLogConsumptionDialog(purchasesState),
            icon: const Icon(Icons.outbox_rounded, size: 18),
            label: Text(context.tr('log_general_expense'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildSubTabChip(
                  context: context,
                  label: context.tr('general_stock'),
                  isSelected: _generalSubTab == 'stock',
                  onSelected: () => setState(() => _generalSubTab = 'stock'),
                  isDark: isDark,
                ),
                _buildSubTabChip(
                  context: context,
                  label: context.tr('general_expenses'),
                  isSelected: _generalSubTab == 'expenses',
                  onSelected: () => setState(() => _generalSubTab = 'expenses'),
                  isDark: isDark,
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.getFontStyle(
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                headerAction,
              ],
            ),
            const SizedBox(height: 16),

            isCompact
                ? GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: stats
                        .map(
                          (s) => _MiniStat(
                            label: s.label,
                            value: s.value,
                            icon: s.icon,
                            color: s.color,
                            isDark: isDark,
                          ),
                        )
                        .toList(),
                  )
                : Row(
                    children: stats
                        .map(
                          (s) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _MiniStat(
                                label: s.label,
                                value: s.value,
                                icon: s.icon,
                                color: s.color,
                                isDark: isDark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 16),

            Expanded(
              child: _generalSubTab == 'stock'
                  ? _buildGeneralStockTab(purchasesState, isDark)
                  : _buildGeneralExpensesTab(purchasesState, isDark),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGeneralStockTab(PurchasesLoaded purchasesState, bool isDark) {
    final purchasedItemNames = purchasesState.transactions
        .where((t) => t.type == 'Purchase' && t.category.toLowerCase() != 'ration')
        .expand((t) => t.items.map((i) => i.itemName.toLowerCase().trim()))
        .toSet();

    final stock = purchasesState.generalStock.where((item) {
      final itemNameLower = item.itemName.toLowerCase().trim();
      if (!purchasedItemNames.contains(itemNameLower)) return false;

      final q = _searchQuery.toLowerCase();
      return item.itemName.toLowerCase().contains(q) || item.category.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        _buildSearchBar(isDark, 'Search general stock...'),
        const SizedBox(height: 16),
        Expanded(
          child: stock.isEmpty
              ? _buildEmptyState('No general stock items registered.\n(Register items automatically by logging a Purchase of category other than Ration.)')
              : SingleChildScrollView(
                  child: _buildCardTable(
                    columns: ['Item Name', 'Category', 'Qty', 'Unit', 'Price / Unit', 'Total Price', 'Actions'],
                    rows: stock.map((item) => [
                      item.itemName,
                      item.category,
                      item.quantity.toStringAsFixed(1),
                      item.unit,
                      '₹${item.latestPrice.toStringAsFixed(1)}',
                      '₹${item.totalAmount.toStringAsFixed(0)}',
                    ]).toList(),
                    rowsBuilder: (index) {
                      final item = stock[index];
                      final isLow = item.quantity <= item.minThreshold;
                      return [
                        DataCell(Text(item.itemName, style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        DataCell(Text(item.category, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isLow ? Colors.red.withAlpha(20) : Colors.green.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.quantity.toStringAsFixed(1),
                              style: AppTheme.getFontStyle(
                                fontWeight: FontWeight.bold, 
                                color: isLow ? Colors.red.shade800 : Colors.green.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(item.unit, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${item.latestPrice.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${item.totalAmount.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.orange),
                                tooltip: context.tr('edit'),
                                onPressed: () => _showEditGeneralStockItemDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                tooltip: 'Print Stock Report PDF',
                                onPressed: () => _printGeneralStockPdf(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                tooltip: context.tr('delete'),
                                onPressed: () => _confirmDelete(
                                  'Delete "${item.itemName}" and all its logs?',
                                  () => context.read<PurchasesBloc>().add(DeleteGeneralStockItemEvent(item.id)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGeneralExpensesTab(PurchasesLoaded purchasesState, bool isDark) {
    final List<_FlattenedTransactionRow> flatRows = [];

    final transactions = purchasesState.transactions.where((t) {
      if (t.type != 'Issue') return false;
      final q = _searchQuery.toLowerCase();
      final itemsSummary = t.items.map((i) => i.itemName).join(', ').toLowerCase();
      return t.receiptNo.toLowerCase().contains(q) ||
             t.category.toLowerCase().contains(q) ||
             itemsSummary.contains(q) ||
             (t.remarks ?? '').toLowerCase().contains(q);
    }).toList();

    for (var t in transactions) {
      for (var i in t.items) {
        flatRows.add(_FlattenedTransactionRow(transaction: t, item: i));
      }
    }

    return Column(
      children: [
        _buildSearchBar(isDark, 'Search general expenses...'),
        const SizedBox(height: 16),
        Expanded(
          child: flatRows.isEmpty
              ? _buildEmptyState('No general expenses logged.')
              : SingleChildScrollView(
                  child: _buildCardTable(
                    columns: ['Date', 'Item Name', 'Qty', 'Unit', 'Price / Unit', 'Total Price', 'Category', 'Remarks / Purpose', 'Actions'],
                    rows: flatRows.map((row) => [
                      row.transaction.transactionDate,
                      row.item.itemName,
                      row.item.quantity.toStringAsFixed(1),
                      row.item.unit,
                      '₹${row.item.pricePerUnit.toStringAsFixed(1)}',
                      '₹${row.item.totalPrice.toStringAsFixed(0)}',
                      row.transaction.category,
                      row.transaction.remarks ?? '-',
                    ]).toList(),
                    rowsBuilder: (index) {
                      final row = flatRows[index];
                      final t = row.transaction;
                      return [
                        DataCell(Text(t.transactionDate, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(row.item.itemName, style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        DataCell(Text(row.item.quantity.toStringAsFixed(1), style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(row.item.unit, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${row.item.pricePerUnit.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${row.item.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
                        DataCell(Text(t.category, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(t.remarks ?? '-', style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                                tooltip: context.tr('edit_log'),
                                onPressed: () => _showEditTransactionDialog(purchasesState, t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                tooltip: 'Print PDF Receipt',
                                onPressed: () => _printPdfInvoice(t),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                tooltip: context.tr('delete_consumption_log'),
                                onPressed: () => _confirmDelete(
                                  t.items.length > 1
                                      ? 'Delete "${row.item.itemName}" from this consumption log? Stock levels will be added back.'
                                      : 'Delete this entire consumption log? Stock levels will be added back.',
                                  () => context.read<PurchasesBloc>().add(DeleteTransactionEvent(t.id, itemName: row.item.itemName)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSellTab(KitchenLoaded kitchenState, PurchasesLoaded purchasesState, bool isDark) {
    final sells = purchasesState.transactions.where((t) {
      if (t.type != 'Sell') return false;
      final q = _searchQuery.toLowerCase();
      final itemsSummary = t.items.map((i) => i.itemName).join(', ').toLowerCase();
      return t.receiptNo.toLowerCase().contains(q) ||
             itemsSummary.contains(q) ||
             (t.contactPerson ?? '').toLowerCase().contains(q) ||
             (t.remarks ?? '').toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        double totalSales = 0.0;
        double totalNafa = 0.0;
        double totalKhot = 0.0;
        for (var t in sells) {
          totalSales += t.totalPrice;
          if (t.items.isNotEmpty) {
            final item = t.items.first;
            final cost = item.costPricePerUnit ?? 0.0;
            final sell = item.pricePerUnit;
            final diff = (sell - cost) * item.quantity;
            if (diff > 0) {
              totalNafa += diff;
            } else if (diff < 0) {
              totalKhot += diff.abs();
            }
          }
        }

        final stats = [
          (
            label: context.tr('total_sales'),
            value: '₹${totalSales.toStringAsFixed(0)}',
            icon: Icons.sell_rounded,
            color: const Color(0xFF1565C0),
          ),
          (
            label: context.tr('total_profit'),
            value: '₹${totalNafa.toStringAsFixed(0)}',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF0D6B4E),
          ),
          (
            label: context.tr('total_loss'),
            value: '₹${totalKhot.toStringAsFixed(0)}',
            icon: Icons.trending_down_rounded,
            color: const Color(0xFFC62828),
          ),
          (
            label: context.tr('sales_count_2'),
            value: sells.length.toString(),
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF6A1B9A),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consolidated Sales',
                        style: AppTheme.getFontStyle(
                          fontSize: isCompact ? 18 : 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      Text(
                        'Track profit margins on school goods and assets sold internally or externally',
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => LogSellEntryDialog(
                        rationItems: kitchenState.stockItems,
                        generalItems: purchasesState.generalStock,
                        units: purchasesState.units,
                        purchasesBloc: context.read<PurchasesBloc>(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sell_rounded, size: 18),
                  label: Text(context.tr('log_sell_entry'), style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            isCompact
                ? GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.5,
                    children: stats
                        .map(
                          (s) => _MiniStat(
                            label: s.label,
                            value: s.value,
                            icon: s.icon,
                            color: s.color,
                            isDark: isDark,
                          ),
                        )
                        .toList(),
                  )
                : Row(
                    children: stats
                        .map(
                          (s) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _MiniStat(
                                label: s.label,
                                value: s.value,
                                icon: s.icon,
                                color: s.color,
                                isDark: isDark,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
            const SizedBox(height: 16),

            _buildSearchBar(isDark, 'Search sales logs by customer, items...'),
            const SizedBox(height: 16),

            Expanded(
              child: sells.isEmpty
                  ? _buildEmptyState('No sales recorded.')
                  : SingleChildScrollView(
                      child: _buildCardTable(
                        columns: ['Date', 'Buyer / Customer', 'Item Name', 'Qty', 'Unit', 'Price / Unit', 'Total Price', 'Cost Price/Unit', 'Profit / Loss', 'Actions'],
                        rows: sells.map((t) {
                          final item = t.items.isNotEmpty ? t.items.first : TransactionItem(itemName: '-', quantity: 0, unit: '', pricePerUnit: 0, totalPrice: 0);
                          final cost = item.costPricePerUnit ?? 0.0;
                          final sell = item.pricePerUnit;
                          final profitLoss = item.profitLoss ?? (sell - cost) * item.quantity;
                          return [
                            t.transactionDate,
                            t.contactPerson ?? '-',
                            item.itemName,
                            item.quantity.toStringAsFixed(1),
                            item.unit,
                            '₹${sell.toStringAsFixed(1)}',
                            '₹${item.totalPrice.toStringAsFixed(0)}',
                            '₹${cost.toStringAsFixed(1)}',
                            '₹${profitLoss.toStringAsFixed(1)}',
                          ];
                        }).toList(),
                        rowsBuilder: (index) {
                          final t = sells[index];
                          final item = t.items.isNotEmpty ? t.items.first : TransactionItem(itemName: '-', quantity: 0, unit: '', pricePerUnit: 0, totalPrice: 0);
                          final cost = item.costPricePerUnit ?? 0.0;
                          final sell = item.pricePerUnit;
                          final profitLoss = item.profitLoss ?? (sell - cost) * item.quantity;

                          return [
                            DataCell(Text(t.transactionDate, style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text(t.contactPerson ?? '-', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                            DataCell(Text(item.itemName, style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text(item.quantity.toStringAsFixed(1), style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text(item.unit, style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text('₹${sell.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text('₹${item.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                            DataCell(Text('₹${cost.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: profitLoss >= 0 ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  profitLoss >= 0 
                                    ? 'Profit: +₹${profitLoss.toStringAsFixed(0)}' 
                                    : 'Loss: -₹${profitLoss.abs().toStringAsFixed(0)}',
                                  style: AppTheme.getFontStyle(
                                    fontWeight: FontWeight.bold,
                                    color: profitLoss >= 0 ? Colors.green.shade800 : Colors.red.shade800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                                    tooltip: context.tr('edit_sale_entry'),
                                    onPressed: () => _showEditTransactionDialog(purchasesState, t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                    tooltip: 'Print PDF Receipt',
                                    onPressed: () => _printPdfInvoice(t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                    tooltip: context.tr('delete_sale_log'),
                                    onPressed: () => _confirmDelete(
                                      'Delete this sales log? Stock levels will be added back.',
                                      () => context.read<PurchasesBloc>().add(DeleteTransactionEvent(t.id)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _printPdfInvoice(PurchaseSellTransaction t) async {
    final List<Map<String, dynamic>> itemsList = t.items.map((i) => {
      'item_name': i.itemName,
      'quantity': i.quantity,
      'unit': i.unit,
      'price_per_unit': i.pricePerUnit,
      'total_price': i.totalPrice,
    }).toList();

    await ReceiptPdfGenerator.printPurchaseSellInvoice(
      receiptNo: t.receiptNo,
      type: t.type,
      category: t.category,
      contactPerson: t.contactPerson ?? '-',
      date: t.transactionDate,
      items: itemsList,
      totalAmount: t.totalPrice,
      remarks: t.remarks,
    );
  }

  // ── DAILY FOOD MENU TAB ─────────────────────────────────────────
  Widget _buildDailyMenuTab(KitchenLoaded state, bool isDark) {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    // Dynamically retrieve all meal types from seeded/user data
    final mealTypes = state.menuItems.map((m) => m.mealType).toSet().toList();
    if (!mealTypes.contains('Breakfast')) mealTypes.add('Breakfast');
    if (!mealTypes.contains('Lunch')) mealTypes.add('Lunch');
    if (!mealTypes.contains('Dinner')) mealTypes.add('Dinner');

    // Sort meal types standardly
    mealTypes.sort((a, b) {
      final order = {'Breakfast': 0, 'Lunch': 1, 'Dinner': 2};
      final orderA = order[a] ?? 99;
      final orderB = order[b] ?? 99;
      return orderA.compareTo(orderB);
    });

    final todayDayName = DateFormat('EEEE').format(DateTime.now());

    return Column(
      children: [
        // Issue Today's Menu Ration Header Card
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark 
                ? [const Color(0xFF1E1E2F), const Color(0xFF252538)] 
                : [Colors.orange.shade50, Colors.orange.shade100.withAlpha(120)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withAlpha(10) : Colors.orange.shade200.withAlpha(120)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.restaurant_rounded, color: Colors.orange, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today is $todayDayName (आज का दिन)', style: AppTheme.getFontStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Issue Daily Menu Ration to Stock', style: AppTheme.getFontStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _confirmAndIssueTodayMenuRation(state, todayDayName),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: Text(context.tr('issue_today_ration_pdf')),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            itemCount: days.length,
            itemBuilder: (context, dayIndex) {
              final day = days[dayIndex];
              final dayMeals = state.menuItems.where((item) => item.dayOfWeek == day).toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day Title Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withAlpha(15),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            day,
                            style: AppTheme.getFontStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppTheme.primaryColor, size: 18),
                            tooltip: context.tr('issue_ration_print_pdf'),
                            onPressed: () => _confirmAndIssueTodayMenuRation(state, day),
                          ),
                        ],
                      ),
                    ),
                    
                    // Meals Wrap layout inside the Day card
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: mealTypes.map((mealType) {
                          final meal = dayMeals.firstWhere(
                            (m) => m.mealType == mealType,
                            orElse: () => KitchenMenuItem(id: '', dayOfWeek: day, mealType: mealType, items: 'Not Scheduled'),
                          );

                          IconData mealIcon;
                          Color iconColor;
                          if (mealType == 'Breakfast') {
                            mealIcon = Icons.free_breakfast_rounded;
                            iconColor = Colors.orange;
                          } else if (mealType == 'Lunch') {
                            mealIcon = Icons.lunch_dining_rounded;
                            iconColor = Colors.blue;
                          } else if (mealType == 'Dinner') {
                            mealIcon = Icons.dinner_dining_rounded;
                            iconColor = Colors.deepPurple;
                          } else {
                            mealIcon = Icons.restaurant_rounded;
                            iconColor = Colors.teal;
                          }

                          return Container(
                            width: 320,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(mealIcon, color: iconColor, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      mealType,
                                      style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, size: 14, color: Colors.grey),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AddEditMenuDialog(
                                            meal: meal.id.isNotEmpty ? meal : null,
                                            stockItems: state.stockItems,
                                            bloc: context.read<KitchenBloc>(),
                                          ),
                                        );
                                      },
                                      tooltip: context.tr('edit_menu'),
                                    ),
                                    if (meal.id.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.delete_rounded, size: 14, color: Colors.red),
                                        onPressed: () => _confirmDelete(
                                          'Delete this menu session "${meal.mealType}" for ${meal.dayOfWeek}?',
                                          () => context.read<KitchenBloc>().add(DeleteMenuItemEvent(meal.id)),
                                        ),
                                        tooltip: context.tr('delete_menu'),
                                      ),
                                    ],
                                  ],
                                ),
                                const Divider(height: 16),
                                
                                // Render plain text or recipe sub-items JSON
                                Builder(
                                  builder: (context) {
                                    if (meal.items.startsWith('[')) {
                                      try {
                                        final List parsed = jsonDecode(meal.items);
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: parsed.map((item) {
                                            final name = item['name'] ?? '';
                                            final List ings = item['ingredients'] ?? [];
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 6.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                  ),
                                                  if (ings.isNotEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(left: 10.0, top: 2.0),
                                                      child: Text(
                                                        'Ingredients: ' + ings.map((ing) => '${ing['item_name']} (${ing['quantity']} ${ing['unit']})').join(', '),
                                                        style: AppTheme.getFontStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      } catch (e) {
                                        // Ignore and fallback
                                      }
                                    }
                                    return Text(
                                      meal.items,
                                      style: AppTheme.getFontStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: meal.items == 'Not Scheduled' ? Colors.grey : (isDark ? Colors.grey.shade300 : Colors.black87),
                                      ),
                                    );
                                  },
                                ),
                                
                                if (meal.notes != null && meal.notes!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '* ${meal.notes}',
                                    style: AppTheme.getFontStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ).copyWith(fontStyle: FontStyle.italic),
                                  ),
                                ]
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── RATION STOCK TAB ────────────────────────────────────────────
  Widget _buildRationStockTab(KitchenLoaded state, PurchasesLoaded purchasesState, bool isDark) {
    final purchasedItemNames = purchasesState.transactions
        .where((t) => t.type == 'Purchase' && t.category.toLowerCase() == 'ration')
        .expand((t) => t.items.map((i) => i.itemName.toLowerCase().trim()))
        .toSet();

    final filtered = state.stockItems.where((item) {
      final itemNameLower = item.itemName.toLowerCase().trim();
      if (!purchasedItemNames.contains(itemNameLower)) return false;

      final q = _searchQuery.toLowerCase();
      return item.itemName.toLowerCase().contains(q) || item.unit.toLowerCase().contains(q);
    }).toList();

    return Column(
      children: [
        _buildSearchBar(isDark, 'Search ration items by name (e.g. Rice)...'),
        const SizedBox(height: 16),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState('No ration items found.')
              : SingleChildScrollView(
                  child: _buildCardTable(
                    columns: ['Item Name', 'Qty', 'Unit', 'Price / Unit', 'Total Price', 'Alert Threshold', 'Alert Status', 'Actions'],
                    rows: filtered.map((item) => [
                      item.itemName,
                      item.quantity.toStringAsFixed(1),
                      item.unit,
                      '₹${item.latestPrice.toStringAsFixed(0)}',
                      '₹${item.totalAmount.toStringAsFixed(0)}',
                      item.minThreshold.toStringAsFixed(1),
                    ]).toList(),
                    rowsBuilder: (index) {
                      final item = filtered[index];
                      final isLow = item.isLowStock;
                      return [
                        DataCell(Text(item.itemName, style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        DataCell(Text(item.quantity.toStringAsFixed(1), style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(item.unit, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${item.latestPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${item.totalAmount.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.blue.shade300 : Colors.blue.shade700))),
                        DataCell(Text(item.minThreshold.toStringAsFixed(1), style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isLow ? Colors.red.withAlpha(20) : Colors.green.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isLow ? 'Low Stock' : 'Good Stock',
                              style: AppTheme.getFontStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isLow ? Colors.red.shade800 : Colors.green.shade800,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.swap_vert_rounded, size: 18, color: Colors.blue),
                                tooltip: context.tr('inflow_outflow'),
                                onPressed: () => _showRecordTransactionDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.orange),
                                tooltip: context.tr('edit'),
                                onPressed: () => _showEditStockItemDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                tooltip: 'Print PDF Report',
                                onPressed: () => _printRationStockPdf(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                tooltip: context.tr('delete'),
                                onPressed: () => _confirmDelete(
                                  'Delete "${item.itemName}" and all its logs?',
                                  () => context.read<KitchenBloc>().add(DeleteStockItemEvent(item.id)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ),
        ),
      ],
    );
  }



  // ── EXPENSE TRACKING TAB ────────────────────────────────────────
  Widget _buildExpensesTab(KitchenLoaded state, bool isDark) {
    final filtered = state.expenses.where((e) {
      final q = _searchQuery.toLowerCase();
      return e.itemName.toLowerCase().contains(q) || (e.remarks ?? '').toLowerCase().contains(q);
    }).toList();

    final List<_FlattenedKitchenExpenseRow> flatRows = [];
    for (var e in filtered) {
      final remarks = e.remarks;
      if (remarks != null && remarks.startsWith('Consumed:')) {
        try {
          final splitOnRemarks = remarks.split(RegExp(r'\.\s*Remarks:'));
          final consumedSection = splitOnRemarks[0];
          final content = consumedSection.substring('Consumed:'.length).trim();
          final cleanContent = content.endsWith('.') ? content.substring(0, content.length - 1).trim() : content;
          final items = cleanContent.split(RegExp(r',\s*(?=[a-zA-Z0-9])'));
          final regex = RegExp(r'^(.+?)\s*\(\s*([\d.]+)\s*([a-zA-Z\s]+)\s*-\s*cost\s*₹\s*([\d.]+)\s*\)$', caseSensitive: false);
          bool parsedAny = false;
          for (var itemStr in items) {
            final match = regex.firstMatch(itemStr.trim());
            if (match != null) {
              final name = match.group(1)!.trim();
              final qty = double.tryParse(match.group(2)!) ?? 1.0;
              final unit = match.group(3)!.trim();
              final total = double.tryParse(match.group(4)!) ?? 0.0;
              final pricePerUnit = qty > 0 ? total / qty : total;
              
              flatRows.add(_FlattenedKitchenExpenseRow(
                originalExpense: e,
                itemName: name,
                qty: qty,
                unit: unit,
                pricePerUnit: pricePerUnit,
                totalPrice: total,
                displayRemarks: 'Auto-issued menu/meal',
              ));
              parsedAny = true;
            }
          }
          if (parsedAny) continue;
        } catch (_) {
          // Fallback
        }
      }
      
      flatRows.add(_FlattenedKitchenExpenseRow(
        originalExpense: e,
        itemName: e.itemName,
        qty: 1.0,
        unit: 'Unit',
        pricePerUnit: e.amount,
        totalPrice: e.amount,
        displayRemarks: e.remarks ?? '-',
      ));
    }

    return Column(
      children: [
        _buildSearchBar(isDark, 'Search kitchen bills by item, notes...'),
        const SizedBox(height: 16),
        Expanded(
          child: flatRows.isEmpty
              ? _buildEmptyState('No kitchen expense bills logged.')
              : SingleChildScrollView(
                  child: _buildCardTable(
                    columns: ['Date', 'Item Name', 'Qty', 'Unit', 'Price / Unit', 'Total Price', 'Remarks', 'Actions'],
                    rows: flatRows.map((row) => [
                      row.originalExpense.expenseDate,
                      row.itemName,
                      row.qty.toStringAsFixed(1),
                      row.unit,
                      '₹${row.pricePerUnit.toStringAsFixed(1)}',
                      '₹${row.totalPrice.toStringAsFixed(0)}',
                      row.displayRemarks,
                    ]).toList(),
                    rowsBuilder: (index) {
                      final row = flatRows[index];
                      final e = row.originalExpense;
                      return [
                        DataCell(Text(e.expenseDate, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(row.itemName, style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                        DataCell(Text(row.qty.toStringAsFixed(1), style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text(row.unit, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${row.pricePerUnit.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(Text('₹${row.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, color: Colors.green.shade800, fontWeight: FontWeight.bold))),
                        DataCell(Text(row.displayRemarks, style: AppTheme.getFontStyle(fontSize: 13))),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                tooltip: 'Print PDF',
                                onPressed: () => _printExpensePdf(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                tooltip: context.tr('delete_expense'),
                                onPressed: () => _confirmDelete(
                                  e.remarks?.startsWith('Consumed:') == true
                                      ? 'Delete ${row.itemName} from this issued meal?'
                                      : 'Delete this expense record?',
                                  () => context.read<KitchenBloc>().add(
                                    DeleteKitchenExpenseEvent(
                                      e.id,
                                      itemName: e.remarks?.startsWith('Consumed:') == true ? row.itemName : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                  ),
                ),
        ),
      ],
    );
  }



  // ─── SEARCH BAR ─────────────────────────────────────────────────
  Widget _buildSearchBar(bool isDark, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(12) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppTheme.getFontStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: AppTheme.getFontStyle(
                  fontSize: 13,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              onPressed: () {
                setState(() {
                  _searchCtrl.clear();
                  _searchQuery = '';
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  // ─── DATA TABLE WIDGET ──────────────────────────────────────────
  Widget _buildCardTable({
    required List<String> columns,
    required List<List<String>> rows,
    List<DataCell> Function(int index)? rowsBuilder,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade100),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50),
          columns: columns
              .map((c) {
                final key = c.toLowerCase().trim()
                    .replaceAll(' / ', '_')
                    .replaceAll('/', '_')
                    .replaceAll(' ', '_')
                    .replaceAll("'", "")
                    .replaceAll('-', '_');
                return DataColumn(
                  label: Text(
                    context.tr(key),
                    style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                );
              })
              .toList(),
          rows: rows.asMap().entries.map((entry) {
            final index = entry.key;
            if (rowsBuilder != null) {
              return DataRow(cells: rowsBuilder(index));
            }
            return DataRow(cells: [
              ...entry.value.map((cell) => DataCell(Text(cell, style: AppTheme.getFontStyle(fontSize: 13)))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ─── ADD/EDIT DAILY FOOD MENU DIALOG ────────────────────────────




  // ─── EDIT RATION STOCK ITEM DIALOG ───────────────────────────────
  void _showEditStockItemDialog(StockItem item) {
    final bloc = context.read<KitchenBloc>();
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item.itemName);
    final thresholdController = TextEditingController(text: item.minThreshold.toString());
    final qtyController = TextEditingController(text: item.quantity.toString());
    String unit = item.unit;

    showDialog(
      context: context,
      builder: (dContext) => BlocProvider.value(
        value: bloc,
        child: StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Edit Ration Item Details', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: context.tr('item_name')),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildResponsiveRow(
                    context,
                    TextFormField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      style: AppTheme.getFontStyle(fontSize: 14),
                      validator: (val) => (val == null || double.tryParse(val) == null) ? 'Enter valid number' : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: ['kg', 'litre', 'bag', 'packet', 'tin', 'pc']
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => unit = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.tr('min_alert_threshold')),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) => (val == null || double.tryParse(val) == null) ? 'Enter valid number' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dContext), child: Text(context.tr('cancel'))),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    bloc.add(UpdateStockItemEvent(
                      id: item.id,
                      itemName: nameController.text.trim(),
                      quantity: double.parse(qtyController.text),
                      unit: unit,
                      minThreshold: double.parse(thresholdController.text),
                    ));
                    Navigator.pop(dContext);
                  }
                },
                child: Text(context.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditGeneralStockItemDialog(GeneralStockItem item) {
    final bloc = context.read<PurchasesBloc>();
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item.itemName);
    final thresholdController = TextEditingController(text: item.minThreshold.toString());
    final qtyController = TextEditingController(text: item.quantity.toString());
    String unit = item.unit;
    String category = item.category;

    showDialog(
      context: context,
      builder: (dContext) => BlocProvider.value(
        value: bloc,
        child: StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Edit General Stock Item', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: context.tr('item_name')),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _buildResponsiveRow(
                    context,
                    TextFormField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      style: AppTheme.getFontStyle(fontSize: 14),
                      validator: (val) => (val == null || double.tryParse(val) == null) ? 'Enter valid number' : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: ['kg', 'litre', 'bag', 'packet', 'tin', 'pc', 'meter', 'box', 'unit']
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => unit = val);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.tr('min_alert_threshold')),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) => (val == null || double.tryParse(val) == null) ? 'Enter valid number' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dContext), child: Text(context.tr('cancel'))),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    bloc.add(UpdateGeneralStockItemEvent(
                      id: item.id,
                      itemName: nameController.text.trim(),
                      quantity: double.parse(qtyController.text),
                      unit: unit,
                      minThreshold: double.parse(thresholdController.text),
                      category: category,
                    ));
                    Navigator.pop(dContext);
                  }
                },
                child: Text(context.tr('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── RECORD TRANSACTION (STOCK IN/OUT) DIALOG ───────────────────
  void _showRecordTransactionDialog(StockItem item) {
    final bloc = context.read<KitchenBloc>();
    final formKey = GlobalKey<FormState>();
    final qtyController = TextEditingController();
    final remarksController = TextEditingController();
    String transType = 'Out'; // Outflow is default

    showDialog(
      context: context,
      builder: (dContext) => BlocProvider.value(
        value: bloc,
        child: StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Stock Transaction — ${item.itemName}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: transType,
                    decoration: const InputDecoration(labelText: 'Transaction Type'),
                    items: [DropdownMenuItem(value: 'In', child: Text(context.tr('check_in_receive_buy'))),
                      DropdownMenuItem(value: 'Out', child: Text(context.tr('check_out_consume_use'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => transType = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Quantity (${item.unit})'),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      final numVal = double.tryParse(val);
                      if (numVal == null || numVal <= 0) return context.tr('enter_positive_number');
                      if (transType == 'Out' && numVal > item.quantity) {
                        return 'Not enough stock (Max: ${item.quantity})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: remarksController,
                    decoration: const InputDecoration(labelText: 'Remarks / Notes (Optional)', hintText: 'e.g. Prepared Monday Dinner'),
                    style: AppTheme.getFontStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dContext), child: Text(context.tr('cancel'))),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    bloc.add(RecordStockTransactionEvent(
                      stockId: item.id,
                      transactionType: transType,
                      quantity: double.parse(qtyController.text),
                      remarks: remarksController.text.trim().isEmpty ? null : remarksController.text.trim(),
                    ));
                    Navigator.pop(dContext);
                  }
                },
                child: Text(context.tr('log_transaction')),
              ),
            ],
          ),
        ),
      ),
    );
  }



  void _showLogKitchenConsumptionDialog(KitchenLoaded state) {
    showDialog(
      context: context,
      builder: (ctx) => _LogKitchenConsumptionDialog(
        rationItems: state.stockItems,
        bloc: context.read<KitchenBloc>(),
      ),
    );
  }

  // ─── PRINT KITCHEN EXPENSE PDF ────────────────────────────────────
  void _printExpensePdf(KitchenExpense e) async {
    await ReceiptPdfGenerator.printPurchaseSellInvoice(
      receiptNo: 'EXP-${e.id.substring(0, 6).toUpperCase()}',
      type: 'Kitchen Expense',
      category: 'Kitchen',
      contactPerson: '-',
      date: e.expenseDate,
      items: [
        {
          'item_name': e.itemName,
          'quantity': 1,
          'unit': 'bill',
          'price_per_unit': e.amount,
          'total_price': e.amount,
        }
      ],
      totalAmount: e.amount,
      remarks: e.remarks,
    );
  }

  // ─── PRINT RATION STOCK ITEM PDF ──────────────────────────────────
  void _printRationStockPdf(StockItem item) async {
    await ReceiptPdfGenerator.printPurchaseSellInvoice(
      receiptNo: 'STK-${item.id.substring(0, 6).toUpperCase()}',
      type: 'Stock Report',
      category: 'Ration',
      contactPerson: '-',
      date: DateTime.now().toIso8601String().split('T')[0],
      items: [
        {
          'item_name': item.itemName,
          'quantity': item.quantity,
          'unit': item.unit,
          'price_per_unit': item.latestPrice,
          'total_price': item.totalAmount,
        }
      ],
      totalAmount: item.totalAmount,
      remarks: 'Status: ${item.isLowStock ? "LOW STOCK" : "Good Stock"} | Threshold: ${item.minThreshold}',
    );
  }

  // ─── PRINT GENERAL STOCK ITEM PDF ─────────────────────────────────
  void _printGeneralStockPdf(GeneralStockItem item) async {
    await ReceiptPdfGenerator.printPurchaseSellInvoice(
      receiptNo: 'GEN-${item.id.substring(0, 6).toUpperCase()}',
      type: 'Stock Report',
      category: item.category,
      contactPerson: '-',
      date: DateTime.now().toIso8601String().split('T')[0],
      items: [
        {
          'item_name': item.itemName,
          'quantity': item.quantity,
          'unit': item.unit,
          'price_per_unit': item.latestPrice,
          'total_price': item.totalAmount,
        }
      ],
      totalAmount: item.totalAmount,
      remarks: 'Category: ${item.category}',
    );
  }

  // ─── EDIT SELL/ISSUE TRANSACTION DIALOG ────────────────────────────
  void _showEditTransactionDialog(PurchasesLoaded purchasesState, PurchaseSellTransaction t) {
    final bloc = context.read<PurchasesBloc>();
    showDialog(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: bloc,
        child: LogEntryDialog(
          units: purchasesState.units,
          categories: purchasesState.categories,
          transaction: t,
          bloc: bloc,
          defaultType: t.type,
          defaultCategory: t.category,
        ),
      ),
    );
  }

  // ─── PLAN A MEAL DIALOG ─────────────────────────────────────────


  // ─── CONFIRM DELETE DIALOG ──────────────────────────────────────
  void _confirmDelete(String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.tr('confirm_delete')),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  // ─── EMPTY STATE WIDGET ─────────────────────────────────────────
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_rounded, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(message, style: AppTheme.getFontStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ─── ERROR STATE WIDGET ─────────────────────────────────────────
  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(message, style: AppTheme.getFontStyle(color: Colors.red)),
        ],
      ),
    );
  }



  void _confirmAndIssueTodayMenuRation(KitchenLoaded state, String dayName) {
    final todayMeals = state.menuItems.where((item) => item.dayOfWeek.toLowerCase() == dayName.toLowerCase()).toList();
    final List<Map<String, dynamic>> todayIngredientsList = [];
    for (var meal in todayMeals) {
      if (meal.items.startsWith('[')) {
        try {
          final List parsed = jsonDecode(meal.items);
          for (var item in parsed) {
            final List ings = item['ingredients'] ?? [];
            for (var ing in ings) {
              final String itemName = ing['item_name'] ?? '';
              final double qty = (ing['quantity'] ?? 0.0).toDouble();
              
              // Find matching StockItem in current stock to get price per unit!
              final stockItem = state.stockItems.firstWhere(
                (s) => s.itemName.toLowerCase().trim() == itemName.toLowerCase().trim(),
                orElse: () => StockItem(id: '', itemName: '', quantity: 0, unit: '', minThreshold: 0, latestPrice: 0.0, totalAmount: 0.0),
              );
              final double pricePerUnit = stockItem.latestPrice;
              final double totalPrice = qty * pricePerUnit;

              todayIngredientsList.add({
                'meal_type': meal.mealType,
                'food_item': item['name'] ?? '',
                'item_name': itemName,
                'quantity': qty,
                'unit': ing['unit'] ?? 'kg',
                'price_per_unit': pricePerUnit,
                'total_price': totalPrice,
              });
            }
          }
        } catch (e) {
          // Skip
        }
      }
    }

    if (todayIngredientsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No structured recipes/ingredients defined in today\'s ($dayName) menu meals.', style: AppTheme.getFontStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Confirm Today\'s Menu Issue ($dayName)', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Container(constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The following stock quantities will be automatically deducted from Ration Stock & logged as an expense:', style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int idx = 0; idx < todayIngredientsList.length; idx++) ...[
                          Builder(
                            builder: (lCtx) {
                              final item = todayIngredientsList[idx];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${item['item_name']} - ${item['quantity']} ${item['unit']} '
                                  '(@ ₹${item['price_per_unit'].toStringAsFixed(1)} = ₹${item['total_price'].toStringAsFixed(0)})',
                                  style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Text('For ${item['food_item']} (${item['meal_type']})', style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey)),
                                leading: const Icon(Icons.arrow_right_rounded, color: Colors.orange),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Save to download & print the daily menu issue receipt PDF.', style: AppTheme.getFontStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                
                final issueDate = DateTime.now().toIso8601String().split('T')[0];
                context.read<KitchenBloc>().add(IssueTodayMenuRationEvent(
                  dayOfWeek: dayName,
                  issueDate: issueDate,
                  onSuccess: (result) async {
                    final List ingList = result['ingredients'] ?? [];
                    final double totalCost = (result['total_cost'] ?? 0.0).toDouble();

                    try {
                      await ReceiptPdfGenerator.printDailyMenuRationIssue(
                        dayOfWeek: dayName,
                        date: issueDate,
                        ingredients: ingList.map((i) => Map<String, dynamic>.from(i)).toList(),
                        totalCost: totalCost,
                        remarks: 'Automated daily menu issue.',
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error printing PDF: $e', style: AppTheme.getFontStyle(color: Colors.white)), backgroundColor: Colors.redAccent),
                      );
                    }
                  },
                ));
              },
              child: Text(context.tr('confirm_print_pdf')),
            ),
          ],
        );
      },
    );
  }


  void _showLogConsumptionDialog(PurchasesLoaded state) {
    if (state.generalStock.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No general stock items available to consume. Log a Purchase of non-ration items first to add to stock.', style: AppTheme.getFontStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => _LogConsumptionDialog(
        stockItems: state.generalStock,
        categories: state.categories,
        bloc: context.read<PurchasesBloc>(),
      ),
    );
  }
}

// ─── ISSUE MEAL RATION DIALOG (ENCAPSULATED STATEFUL WIDGET FOR SOLID LIFECYCLE) ───
class IssueRationDialog extends StatefulWidget {
  final List<StockItem> stockItems;
  final KitchenBloc bloc;

  const IssueRationDialog({
    super.key,
    required this.stockItems,
    required this.bloc,
  });

  @override
  State<IssueRationDialog> createState() => _IssueRationDialogState();
}

class _IssueRationDialogState extends State<IssueRationDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _mealNameController;
  late TextEditingController _dateController;
  late TextEditingController _remarksController;
  final List<_IssueItemRowData> _itemRows = [];

  @override
  void initState() {
    super.initState();
    _mealNameController = TextEditingController(text: 'Lunch');
    _dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);
    _remarksController = TextEditingController();

    // Start with 1 empty row
    if (widget.stockItems.isNotEmpty) {
      _itemRows.add(_IssueItemRowData(selectedItem: widget.stockItems.first));
    }
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    _dateController.dispose();
    _remarksController.dispose();
    for (var r in _itemRows) {
      r.dispose();
    }
    super.dispose();
  }

  double _calculateTotalCost() {
    double sum = 0.0;
    for (var r in _itemRows) {
      sum += double.tryParse(r.costController.text) ?? 0.0;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Issue Ration for Meal (खर्च/Meal Cons.)', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Container(constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Meal name, Date
                context.isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _mealNameController,
                            decoration: InputDecoration(labelText: context.tr('meal_recipe_name'), hintText: 'e.g. Lunch (Rice & Dal)'),
                            style: AppTheme.getFontStyle(fontSize: 13),
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _dateController,
                            decoration: InputDecoration(labelText: context.tr('issue_date')),
                            style: AppTheme.getFontStyle(fontSize: 13),
                            readOnly: true,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setState(() {
                                  _dateController.text = picked.toIso8601String().split('T')[0];
                                });
                              }
                            },
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _mealNameController,
                              decoration: InputDecoration(labelText: context.tr('meal_recipe_name'), hintText: 'e.g. Lunch (Rice & Dal)'),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              decoration: InputDecoration(labelText: context.tr('issue_date')),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              readOnly: true,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _dateController.text = picked.toIso8601String().split('T')[0];
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 12),
                
                // Remarks
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks / Notes', hintText: 'e.g. Issued for Saturday noon'),
                  style: AppTheme.getFontStyle(fontSize: 13),
                ),
                const SizedBox(height: 20),

                // List header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Consuming Items List', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                    if (widget.stockItems.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _itemRows.add(_IssueItemRowData(selectedItem: widget.stockItems.first));
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(context.tr('add_item')),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                if (widget.stockItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('No items in Ration Stock to issue. Purchase ration first.', style: AppTheme.getFontStyle(color: Colors.red, fontSize: 13))),
                  )
                else
                  Column(
                    children: [
                      for (int idx = 0; idx < _itemRows.length; idx++) ...[
                        Builder(
                          builder: (ctx) {
                            final row = _itemRows[idx];

                            return Container(
                              key: ObjectKey(row),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Stock Item selection dropdown
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<StockItem>(
                                      value: row.selectedItem,
                                      decoration: const InputDecoration(labelText: 'Stock Item', isDense: true),
                                      items: widget.stockItems.map((item) {
                                        return DropdownMenuItem<StockItem>(
                                          value: item,
                                          child: Text(
                                            '${item.itemName} (${item.quantity.toStringAsFixed(1)} ${item.unit} available)',
                                            style: AppTheme.getFontStyle(fontSize: 12),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() {
                                            row.selectedItem = val;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Quantity to consume
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      controller: row.qtyController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Qty (${row.selectedItem.unit})', 
                                        isDense: true
                                      ),
                                      style: AppTheme.getFontStyle(fontSize: 13),
                                      validator: (val) {
                                        if (val == null || double.tryParse(val) == null || double.parse(val) <= 0) {
                                          return 'Required';
                                        }
                                        final inputQty = double.parse(val);
                                        if (inputQty > row.selectedItem.quantity) {
                                          return 'Max ${row.selectedItem.quantity.toStringAsFixed(0)}';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Cost of this item
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: row.costController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(labelText: context.tr('estimated_cost_inr'), isDense: true),
                                      style: AppTheme.getFontStyle(fontSize: 13),
                                      onChanged: (_) => setState(() {}),
                                      validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) < 0) ? 'Required' : null,
                                    ),
                                  ),

                                  // Delete row button
                                  if (_itemRows.length > 1) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          _itemRows.removeAt(idx);
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 16),

                // Combined total cost display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withAlpha(30)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Meal Expense Cost:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('₹${_calculateTotalCost().toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange.shade800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: widget.stockItems.isEmpty ? null : () {
            if (_formKey.currentState!.validate()) {
              final List<Map<String, dynamic>> itemsList = _itemRows.map((r) => {
                'stock_id': r.selectedItem.id,
                'quantity': double.parse(r.qtyController.text),
                'estimated_cost': double.parse(r.costController.text),
              }).toList();

              widget.bloc.add(IssueMealRationEvent(
                mealName: _mealNameController.text.trim(),
                issueDate: _dateController.text.trim(),
                items: itemsList,
                remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
              ));

              Navigator.pop(context);
            }
          },
          child: Text(context.tr('issue_save_expense')),
        ),
      ],
    );
  }
}

class _IssueItemRowData {
  StockItem selectedItem;
  final TextEditingController qtyController = TextEditingController(text: '1.0');
  final TextEditingController costController = TextEditingController(text: '0');

  _IssueItemRowData({required this.selectedItem});

  void dispose() {
    qtyController.dispose();
    costController.dispose();
  }
}

// ─── ADD/EDIT DAILY FOOD MENU DIALOG WITH INGREDIENTS ─────────────────
class AddEditMenuDialog extends StatefulWidget {
  final KitchenMenuItem? meal;
  final List<StockItem> stockItems;
  final KitchenBloc bloc;

  const AddEditMenuDialog({
    super.key,
    required this.meal,
    required this.stockItems,
    required this.bloc,
  });

  @override
  State<AddEditMenuDialog> createState() => _AddEditMenuDialogState();
}

class _AddEditMenuDialogState extends State<AddEditMenuDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _selectedDay;
  late String _selectedMealType;
  late TextEditingController _customMealTypeController;
  late TextEditingController _timeController;
  late String _amPm;

  final List<_FoodItemRowData> _foodItems = [];

  @override
  void initState() {
    super.initState();
    final defaultMealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snacks', 'Other'];
    
    _selectedDay = widget.meal?.dayOfWeek ?? 'Monday';
    _selectedMealType = widget.meal != null 
        ? (defaultMealTypes.contains(widget.meal!.mealType) ? widget.meal!.mealType : 'Other')
        : 'Breakfast';
        
    _customMealTypeController = TextEditingController(
      text: widget.meal != null && !defaultMealTypes.contains(widget.meal!.mealType) ? widget.meal!.mealType : ''
    );

    String timeText = '';
    _amPm = 'AM';
    if (widget.meal?.notes != null) {
      final match = RegExp(r'(\d+:\d+)\s*(AM|PM)', caseSensitive: false).firstMatch(widget.meal!.notes!);
      if (match != null) {
        timeText = match.group(1) ?? '';
        _amPm = (match.group(2) ?? 'AM').toUpperCase();
      } else {
        timeText = widget.meal!.notes!;
      }
    }
    if (timeText.isEmpty) {
      timeText = '08:00';
    }
    _timeController = TextEditingController(text: timeText);

    if (widget.meal != null && widget.meal!.items != 'Not Scheduled') {
      try {
        if (widget.meal!.items.startsWith('[')) {
          final List list = jsonDecode(widget.meal!.items);
          for (var item in list) {
            final name = item['name'] ?? '';
            final List jsonIngs = item['ingredients'] ?? [];
            
            final rowData = _FoodItemRowData(nameText: name);
            for (var jsonIng in jsonIngs) {
              final stockId = jsonIng['stock_id'];
              final quantity = (jsonIng['quantity'] ?? 1.0).toDouble();
              
              final match = widget.stockItems.firstWhere(
                (s) => s.id == stockId,
                orElse: () => widget.stockItems.isNotEmpty 
                    ? widget.stockItems.first 
                    : StockItem(id: '', itemName: jsonIng['item_name'] ?? 'Unknown', quantity: 0.0, unit: jsonIng['unit'] ?? 'kg', minThreshold: 0.0),
              );
              rowData.ingredients.add(_RecipeIngredientRowData(selectedItem: match, quantity: quantity));
            }
            _foodItems.add(rowData);
          }
        } else {
          final itemsList = widget.meal!.items.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          for (var item in itemsList) {
            _foodItems.add(_FoodItemRowData(nameText: item));
          }
        }
      } catch (e) {
        final itemsList = widget.meal!.items.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        for (var item in itemsList) {
          _foodItems.add(_FoodItemRowData(nameText: item));
        }
      }
    }

    if (_foodItems.isEmpty) {
      _foodItems.add(_FoodItemRowData());
    }
  }

  @override
  void dispose() {
    _customMealTypeController.dispose();
    _timeController.dispose();
    for (var f in _foodItems) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOtherType = _selectedMealType == 'Other';
    final defaultMealTypes = ['Breakfast', 'Lunch', 'Dinner', 'Snacks', 'Other'];
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.meal == null ? 'Add Daily Food Menu' : 'Update Daily Food Menu',
        style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      content: Container(constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedDay,
                  decoration: const InputDecoration(labelText: 'Select Day'),
                  items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                  onChanged: widget.meal != null ? null : (val) {
                    if (val != null) setState(() => _selectedDay = val);
                  },
                ),
                const SizedBox(height: 12),
                
                DropdownButtonFormField<String>(
                  value: _selectedMealType,
                  decoration: InputDecoration(labelText: context.tr('food_type_meal_session')),
                  items: defaultMealTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMealType = val);
                  },
                ),
                if (isOtherType) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customMealTypeController,
                    decoration: InputDecoration(labelText: context.tr('enter_custom_food_type'), hintText: 'e.g. Snacks, High Tea'),
                    style: AppTheme.getFontStyle(fontSize: 14),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _timeController,
                        decoration: const InputDecoration(labelText: 'Time (HH:MM)', hintText: 'e.g. 08:30'),
                        style: AppTheme.getFontStyle(fontSize: 14),
                        readOnly: true,
                        onTap: () async {
                          final tod = await showTimePicker(
                            context: context,
                            initialTime: const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (tod != null) {
                            final hourStr = tod.hourOfPeriod.toString().padLeft(2, '0');
                            final minStr = tod.minute.toString().padLeft(2, '0');
                            setState(() {
                              _timeController.text = '$hourStr:$minStr';
                              _amPm = tod.period == DayPeriod.am ? 'AM' : 'PM';
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: _amPm,
                        decoration: InputDecoration(labelText: context.tr('am_pm')),
                        items: [DropdownMenuItem(value: 'AM', child: Text('AM')),
                          DropdownMenuItem(value: 'PM', child: Text('PM')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _amPm = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Food Items & Recipe List', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryColor)),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _foodItems.add(_FoodItemRowData());
                        });
                      },
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Add Food Item', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Column(
                  children: [
                    for (int idx = 0; idx < _foodItems.length; idx++) ...[
                      Builder(
                        builder: (ctx) {
                          final food = _foodItems[idx];

                          return Container(
                            key: ObjectKey(food),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: food.nameController,
                                        decoration: InputDecoration(
                                          labelText: 'Food Item #${idx + 1}',
                                          hintText: 'e.g. Roti, Chai, Sabzi',
                                          isDense: true,
                                        ),
                                        style: AppTheme.getFontStyle(fontSize: 13),
                                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                                      ),
                                    ),
                                    if (_foodItems.length > 1) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _foodItems.removeAt(idx);
                                          });
                                        },
                                      ),
                                    ]
                                  ],
                                ),
                                const SizedBox(height: 8),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Ingredients (Sub-Items):', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    if (widget.stockItems.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () {
                                          setState(() {
                                            food.ingredients.add(_RecipeIngredientRowData(selectedItem: widget.stockItems.first));
                                          });
                                        },
                                        icon: const Icon(Icons.add, size: 12),
                                        label: const Text('Add Ingredient', style: TextStyle(fontSize: 10)),
                                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      ),
                                  ],
                                ),
                                
                                if (food.ingredients.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Text('No ingredients (logs item name only).', style: AppTheme.getFontStyle(fontSize: 10, color: Colors.grey).copyWith(fontStyle: FontStyle.italic)),
                                  )
                                else
                                  Column(
                                    children: [
                                      for (int iIdx = 0; iIdx < food.ingredients.length; iIdx++) ...[
                                        Builder(
                                          builder: (iCtx) {
                                            final ing = food.ingredients[iIdx];

                                            return Padding(
                                              key: ObjectKey(ing),
                                              padding: const EdgeInsets.only(bottom: 6.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  Expanded(
                                                    flex: 3,
                                                    child: DropdownButtonFormField<StockItem>(
                                                      value: ing.selectedItem,
                                                      decoration: const InputDecoration(labelText: 'Ration Item', isDense: true),
                                                      items: widget.stockItems.map((item) {
                                                        return DropdownMenuItem<StockItem>(
                                                          value: item,
                                                          child: Text('${item.itemName} (${item.unit})', style: AppTheme.getFontStyle(fontSize: 11)),
                                                        );
                                                      }).toList(),
                                                      onChanged: (val) {
                                                        if (val != null) {
                                                          setState(() {
                                                            ing.selectedItem = val;
                                                          });
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),

                                                  Expanded(
                                                    flex: 1,
                                                    child: TextFormField(
                                                      controller: ing.qtyController,
                                                      keyboardType: TextInputType.number,
                                                      decoration: InputDecoration(
                                                        labelText: 'Qty (${ing.selectedItem.unit})', 
                                                        isDense: true
                                                      ),
                                                      style: AppTheme.getFontStyle(fontSize: 11),
                                                      validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) <= 0) ? 'Required' : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),

                                                  IconButton(
                                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 16),
                                                    onPressed: () {
                                                      setState(() {
                                                        food.ingredients.removeAt(iIdx);
                                                      });
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final finalMealType = isOtherType ? _customMealTypeController.text.trim() : _selectedMealType;
              final finalTime = '${_timeController.text} $_amPm';

              final List<Map<String, dynamic>> menuItemsJson = _foodItems.map((food) {
                return {
                  'name': food.nameController.text.trim(),
                  'ingredients': food.ingredients.map((ing) => {
                    'stock_id': ing.selectedItem.id,
                    'item_name': ing.selectedItem.itemName,
                    'quantity': double.parse(ing.qtyController.text),
                    'unit': ing.selectedItem.unit
                  }).toList()
                };
              }).toList();

              widget.bloc.add(UpdateMenuItemEvent(
                dayOfWeek: _selectedDay,
                mealType: finalMealType,
                items: jsonEncode(menuItemsJson),
                notes: finalTime,
              ));

              Navigator.pop(context);
            }
          },
          child: Text(widget.meal == null ? 'Add Menu' : 'Save Changes'),
        ),
      ],
    );
  }
}

class _FoodItemRowData {
  final TextEditingController nameController;
  final List<_RecipeIngredientRowData> ingredients = [];

  _FoodItemRowData({String nameText = ''}) : nameController = TextEditingController(text: nameText);

  void dispose() {
    nameController.dispose();
    for (var i in ingredients) {
      i.dispose();
    }
  }
}

class _RecipeIngredientRowData {
  StockItem selectedItem;
  final TextEditingController qtyController;

  _RecipeIngredientRowData({
    required this.selectedItem,
    double quantity = 1.0,
  }) : qtyController = TextEditingController(text: quantity.toStringAsFixed(1));

  void dispose() {
    qtyController.dispose();
  }
}

class _ConsumptionRowData {
  GeneralStockItem selectedItem;
  final TextEditingController qtyController = TextEditingController(text: '1.0');
  final TextEditingController pricePerUnitController = TextEditingController();
  final TextEditingController totalPriceController = TextEditingController();

  _ConsumptionRowData({required this.selectedItem}) {
    pricePerUnitController.text = selectedItem.latestPrice.toStringAsFixed(1);
    totalPriceController.text = (1.0 * selectedItem.latestPrice).toStringAsFixed(0);
  }

  void updateItem(GeneralStockItem item) {
    selectedItem = item;
    pricePerUnitController.text = item.latestPrice.toStringAsFixed(1);
    final double qty = double.tryParse(qtyController.text) ?? 0.0;
    totalPriceController.text = (qty * item.latestPrice).toStringAsFixed(0);
  }

  void updateQty(String val) {
    final double qty = double.tryParse(val) ?? 0.0;
    totalPriceController.text = (qty * selectedItem.latestPrice).toStringAsFixed(0);
  }

  void dispose() {
    qtyController.dispose();
    pricePerUnitController.dispose();
    totalPriceController.dispose();
  }
}

class _LogConsumptionDialog extends StatefulWidget {
  final List<GeneralStockItem> stockItems;
  final List<CategoryModel> categories;
  final PurchasesBloc bloc;

  const _LogConsumptionDialog({
    required this.stockItems,
    required this.categories,
    required this.bloc,
  });

  @override
  State<_LogConsumptionDialog> createState() => _LogConsumptionDialogState();
}

class _LogConsumptionDialogState extends State<_LogConsumptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_ConsumptionRowData> _itemRows = [];
  final _remarksController = TextEditingController();
  final _dateController = TextEditingController(
    text: DateTime.now().toIso8601String().split('T')[0]
  );
  late List<GeneralStockItem> _availableItems;

  @override
  void initState() {
    super.initState();
    _availableItems = widget.stockItems.where((item) => item.quantity > 0).toList();
    if (_availableItems.isNotEmpty) {
      _itemRows.add(_ConsumptionRowData(selectedItem: _availableItems.first));
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _dateController.dispose();
    for (var row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  double _calculateTotalCost() {
    double sum = 0.0;
    for (var row in _itemRows) {
      final double qty = double.tryParse(row.qtyController.text) ?? 0.0;
      sum += qty * row.selectedItem.latestPrice;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Log Item Consumption (In Use)', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_availableItems.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _itemRows.add(_ConsumptionRowData(selectedItem: _availableItems.first));
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('add_row')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
      content: Container(constraints: const BoxConstraints(maxWidth: 720),
        child: _availableItems.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No general stock items available with quantity > 0.',
                    style: AppTheme.getFontStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Date & Remarks
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              decoration: InputDecoration(labelText: context.tr('consumption_date'), suffixIcon: Icon(Icons.calendar_today_rounded, size: 16)),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              readOnly: true,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _dateController.text = picked.toIso8601String().split('T')[0];
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _remarksController,
                              decoration: const InputDecoration(
                                labelText: 'Remarks / Location / Purpose',
                                hintText: 'e.g. repairs, wiring'
                              ),
                              style: AppTheme.getFontStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Rows title
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Consumed Stock Items', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                      ),
                      const SizedBox(height: 8),

                      // Multi rows list
                      Column(
                        children: [
                          for (int idx = 0; idx < _itemRows.length; idx++) ...[
                            Builder(
                              builder: (ctx) {
                                final row = _itemRows[idx];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Dropdown Item Name
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButtonFormField<GeneralStockItem>(
                                          isExpanded: true,
                                          value: row.selectedItem,
                                          decoration: const InputDecoration(labelText: 'Select Item', isDense: true),
                                          items: _availableItems.map((item) {
                                            return DropdownMenuItem<GeneralStockItem>(
                                              value: item,
                                              child: Text('${item.itemName} (${item.quantity.toStringAsFixed(1)} ${item.unit} avail.)', style: AppTheme.getFontStyle(fontSize: 12)),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                row.updateItem(val);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Quantity
                                      Expanded(
                                        flex: 1,
                                        child: TextFormField(
                                          controller: row.qtyController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(labelText: 'Qty (${row.selectedItem.unit})', isDense: true),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.updateQty(val);
                                            });
                                          },
                                          validator: (val) {
                                            if (val == null || double.tryParse(val) == null) return 'Required';
                                            final double qty = double.parse(val);
                                            if (qty <= 0) return 'Must be > 0';
                                            if (qty > row.selectedItem.quantity) return 'Exceeds stock';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Price / Unit
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.pricePerUnitController,
                                          decoration: const InputDecoration(labelText: 'Price/Unit', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          readOnly: true,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Total Price
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.totalPriceController,
                                          decoration: const InputDecoration(labelText: 'Total Price', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          readOnly: true,
                                        ),
                                      ),

                                      // Delete row
                                      if (_itemRows.length > 1) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              _itemRows.removeAt(idx);
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Grand Total
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withAlpha(30)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Grand Total Consumption Valuation:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('₹${_calculateTotalCost().toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange.shade800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        if (_availableItems.isNotEmpty)
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate() && _itemRows.isNotEmpty) {
                final randomReceipt = 'USE-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
                final List<Map<String, dynamic>> itemsList = _itemRows.map((r) {
                  return {
                    'stock_id': r.selectedItem.id,
                    'quantity': double.parse(r.qtyController.text),
                  };
                }).toList();

                // Use the category of the first item in general stock consumption
                final String itemCategory = _itemRows.first.selectedItem.category;

                widget.bloc.add(IssueGeneralStockEvent(
                  receiptNo: randomReceipt,
                  transactionDate: _dateController.text.trim(),
                  category: itemCategory,
                  contactPerson: 'Internal Use',
                  remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
                  items: itemsList,
                ));

                Navigator.pop(context);
              }
            },
            child: Text(context.tr('confirm_log_use')),
          ),
      ],
    );
  }
}

// ─── LOG SELL ENTRY DIALOG (CONSOLIDATED SALES MODULE) ───
class _SellRowData {
  dynamic selectedItem; // StockItem or GeneralStockItem
  final TextEditingController qtyController = TextEditingController(text: '1.0');
  final TextEditingController sellPriceController = TextEditingController(text: '0.0');
  final TextEditingController sellTotalController = TextEditingController(text: '0.0');
  final TextEditingController discountController = TextEditingController(text: '0');
  double discountPercent = 0.0;
  double costPricePerUnit = 0.0;
  double profitLoss = 0.0;
  double availableQty = 0.0;
  String unit = '';

  _SellRowData({required this.selectedItem}) {
    if (selectedItem != null) {
      availableQty = selectedItem.quantity;
      unit = selectedItem.unit;
      costPricePerUnit = selectedItem.latestPrice;
      sellPriceController.text = costPricePerUnit.toStringAsFixed(1);
      final double qty = double.tryParse(qtyController.text) ?? 1.0;
      sellTotalController.text = (qty * costPricePerUnit).toStringAsFixed(1);
      profitLoss = 0.0;
    }
  }

  void updateItem(dynamic item) {
    selectedItem = item;
    if (item != null) {
      availableQty = item.quantity;
      unit = item.unit;
      costPricePerUnit = item.latestPrice;
      sellPriceController.text = costPricePerUnit.toStringAsFixed(1);
      final double qty = double.tryParse(qtyController.text) ?? 1.0;
      final double sellPrice = double.tryParse(sellPriceController.text) ?? 0.0;
      final double discount = double.tryParse(discountController.text) ?? 0.0;
      final double baseTotal = qty * sellPrice;
      final double finalTotal = baseTotal - discount;
      sellTotalController.text = finalTotal.toStringAsFixed(1);
      profitLoss = finalTotal - (qty * costPricePerUnit);
      if (baseTotal > 0) {
        discountPercent = (discount / baseTotal) * 100;
      } else {
        discountPercent = 0.0;
      }
    }
  }

  void calculatePrices() {
    final double qty = double.tryParse(qtyController.text) ?? 0.0;
    final double sellPrice = double.tryParse(sellPriceController.text) ?? 0.0;
    final double discount = double.tryParse(discountController.text) ?? 0.0;
    final double baseTotal = qty * sellPrice;
    final double finalTotal = baseTotal - discount;
    sellTotalController.text = finalTotal.toStringAsFixed(1);
    profitLoss = finalTotal - (qty * costPricePerUnit);
    if (baseTotal > 0) {
      discountPercent = (discount / baseTotal) * 100;
    } else {
      discountPercent = 0.0;
    }
  }

  void calculateUnitFromTotal() {
    final double qty = double.tryParse(qtyController.text) ?? 0.0;
    final double sellTotal = double.tryParse(sellTotalController.text) ?? 0.0;
    final double discount = double.tryParse(discountController.text) ?? 0.0;
    final double baseTotal = sellTotal + discount;
    if (qty > 0) {
      final double sellPrice = baseTotal / qty;
      sellPriceController.text = sellPrice.toStringAsFixed(1);
      profitLoss = sellTotal - (qty * costPricePerUnit);
      if (baseTotal > 0) {
        discountPercent = (discount / baseTotal) * 100;
      } else {
        discountPercent = 0.0;
      }
    }
  }

  void dispose() {
    qtyController.dispose();
    sellPriceController.dispose();
    sellTotalController.dispose();
    discountController.dispose();
  }
}

class LogSellEntryDialog extends StatefulWidget {
  final List<StockItem> rationItems;
  final List<GeneralStockItem> generalItems;
  final List<UnitModel> units;
  final PurchasesBloc purchasesBloc;

  const LogSellEntryDialog({
    super.key,
    required this.rationItems,
    required this.generalItems,
    required this.units,
    required this.purchasesBloc,
  });

  @override
  State<LogSellEntryDialog> createState() => _LogSellEntryDialogState();
}

class _LogSellEntryDialogState extends State<LogSellEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  String _stockType = 'Kitchen'; // 'Kitchen' or 'General'
  final List<_SellRowData> _itemRows = [];
  final _customerController = TextEditingController();
  final _remarksController = TextEditingController();
  final _dateController = TextEditingController(text: DateTime.now().toIso8601String().split('T')[0]);

  @override
  void initState() {
    super.initState();
    _resetItemSelection();
  }

  void _resetItemSelection() {
    _itemRows.clear();
    if (_stockType == 'Kitchen') {
      final filtered = widget.rationItems.where((i) => i.quantity > 0).toList();
      if (filtered.isNotEmpty) {
        _itemRows.add(_SellRowData(selectedItem: filtered.first));
      }
    } else {
      // Exclude items that also exist in kitchen_stock (by name, case-insensitive)
      final kitchenNames = widget.rationItems.map((r) => r.itemName.toLowerCase().trim()).toSet();
      final filtered = widget.generalItems
          .where((g) => g.quantity > 0 && !kitchenNames.contains(g.itemName.toLowerCase().trim()))
          .toList();
      if (filtered.isNotEmpty) {
        _itemRows.add(_SellRowData(selectedItem: filtered.first));
      }
    }
  }

  List<dynamic> _getFilteredItems() {
    if (_stockType == 'Kitchen') {
      return widget.rationItems.where((i) => i.quantity > 0).toList();
    } else {
      final kitchenNames = widget.rationItems.map((r) => r.itemName.toLowerCase().trim()).toSet();
      return widget.generalItems
          .where((g) => g.quantity > 0 && !kitchenNames.contains(g.itemName.toLowerCase().trim()))
          .toList();
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _remarksController.dispose();
    _dateController.dispose();
    for (var r in _itemRows) {
      r.dispose();
    }
    super.dispose();
  }

  double _calculateTotalSellAmount() {
    double sum = 0.0;
    for (var r in _itemRows) {
      sum += double.tryParse(r.sellTotalController.text) ?? 0.0;
    }
    return sum;
  }

  double _calculateTotalCostAmount() {
    double sum = 0.0;
    for (var r in _itemRows) {
      final double qty = double.tryParse(r.qtyController.text) ?? 0.0;
      sum += qty * r.costPricePerUnit;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final double totalSell = _calculateTotalSellAmount();
    final double totalCost = _calculateTotalCostAmount();
    final double netProfitLoss = totalSell - totalCost;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Log Sales Entry (बेचे)', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ElevatedButton.icon(
            onPressed: () {
              final items = _getFilteredItems();
              if (items.isNotEmpty) {
                setState(() {
                  _itemRows.add(_SellRowData(selectedItem: items.first));
                });
              }
            },
            icon: const Icon(Icons.add, size: 16),
            label: Text(context.tr('add_row')),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
      content: Container(constraints: const BoxConstraints(maxWidth: 800),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source Selector, Customer Name, Date
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _stockType,
                        decoration: const InputDecoration(labelText: 'Stock Source', isDense: true),
                        items: [DropdownMenuItem(value: 'Kitchen', child: Text(context.tr('kitchen_stock_ration'))),
                          DropdownMenuItem(value: 'General', child: Text(context.tr('general_stock_assets'))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _stockType = val;
                              _resetItemSelection();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _customerController,
                        decoration: InputDecoration(labelText: context.tr('customer_buyer_name'), hintText: 'e.g. Maulana Arshad', isDense: true),
                        style: AppTheme.getFontStyle(fontSize: 13),
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _dateController,
                        decoration: const InputDecoration(labelText: 'Sale Date (YYYY-MM-DD)', isDense: true),
                        style: AppTheme.getFontStyle(fontSize: 13),
                        readOnly: true,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _dateController.text = picked.toIso8601String().split('T')[0];
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Remarks
                TextFormField(
                  controller: _remarksController,
                  decoration: const InputDecoration(labelText: 'Remarks / Notes (Optional)', isDense: true),
                  style: AppTheme.getFontStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Section title
                Text('Sales Items List', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                const SizedBox(height: 8),

                // Multi row list builder
                if (_itemRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('No items to sell. Please select a stock source.', style: AppTheme.getFontStyle(color: Colors.redAccent))),
                  )
                else
                  Column(
                    children: [
                      for (int idx = 0; idx < _itemRows.length; idx++) ...[
                        Builder(
                          builder: (ctx) {
                            final row = _itemRows[idx];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Dropdown Item Name
                                      Expanded(
                                        flex: 4,
                                        child: DropdownButtonFormField<dynamic>(
                                          isExpanded: true,
                                          value: row.selectedItem,
                                          decoration: const InputDecoration(labelText: 'Select Item', isDense: true),
                                          items: _getFilteredItems().map<DropdownMenuItem<dynamic>>((item) {
                                              return DropdownMenuItem<dynamic>(
                                                value: item,
                                                child: Text('${item.itemName} (${item.quantity.toStringAsFixed(1)} ${item.unit} avail.)', style: AppTheme.getFontStyle(fontSize: 12)),
                                              );
                                            }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                row.updateItem(val);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Unit (Read-only)
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          initialValue: row.unit.isEmpty ? 'Unit' : row.unit,
                                          key: ValueKey('${idx}_${row.unit}'),
                                          readOnly: true,
                                          decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Quantity
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.qtyController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Qty', isDense: true),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.calculatePrices();
                                            });
                                          },
                                          validator: (val) {
                                            if (val == null || double.tryParse(val) == null) return 'Required';
                                            final double qty = double.parse(val);
                                            if (qty <= 0) return 'Must be > 0';
                                            if (qty > row.availableQty) return 'Exceeds stock';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Sell Price / Unit
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.sellPriceController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Price/Unit', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.calculatePrices();
                                            });
                                          },
                                          validator: (val) => (val == null || double.tryParse(val) == null) ? 'Required' : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Total Sell Price
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.sellTotalController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(labelText: 'Total Price', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.calculateUnitFromTotal();
                                            });
                                          },
                                          validator: (val) => (val == null || double.tryParse(val) == null) ? 'Required' : null,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Discount (₹)
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.discountController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            labelText: context.tr('discount_inr'),
                                            isDense: true,
                                            suffixText: row.discountPercent > 0 
                                                ? '${row.discountPercent.toStringAsFixed(0)}%' 
                                                : null,
                                            suffixStyle: AppTheme.getFontStyle(fontSize: 10, color: Colors.green),
                                          ),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.calculatePrices();
                                            });
                                          },
                                        ),
                                      ),

                                      // Delete row
                                      if (_itemRows.length > 1) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              _itemRows.removeAt(idx);
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 16),

                // Profit / Loss and Grand Totals Display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: netProfitLoss >= 0 ? Colors.green.withAlpha(15) : Colors.red.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: netProfitLoss >= 0 ? Colors.green.withAlpha(30) : Colors.red.withAlpha(30)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Cost Value of Items Sold:', style: AppTheme.getFontStyle(fontSize: 13)),
                          Text('₹${totalCost.toStringAsFixed(1)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Grand Total Invoice Amount:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('₹${totalSell.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 18, color: netProfitLoss >= 0 ? Colors.green.shade800 : Colors.red.shade800)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Net Profit / Loss:', style: AppTheme.getFontStyle(fontSize: 13)),
                          Text(
                            netProfitLoss >= 0 
                              ? '+₹${netProfitLoss.toStringAsFixed(1)} (Profit)' 
                              : '-₹${netProfitLoss.abs().toStringAsFixed(1)} (Loss)',
                            style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: netProfitLoss >= 0 ? Colors.green.shade800 : Colors.red.shade800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate() && _itemRows.isNotEmpty) {
              final randomReceipt = 'SAL-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
              final List<Map<String, dynamic>> itemsList = _itemRows.map((r) {
                final double qty = double.parse(r.qtyController.text);
                final double sellPrice = double.parse(r.sellPriceController.text);
                final double sellTotal = double.parse(r.sellTotalController.text);
                return {
                  'item_name': r.selectedItem.itemName,
                  'quantity': qty,
                  'unit': r.unit,
                  'price_per_unit': sellPrice,
                  'total_price': sellTotal,
                  'cost_price_per_unit': r.costPricePerUnit,
                  'cost_total_price': qty * r.costPricePerUnit,
                  'profit_loss': r.profitLoss,
                  'discount_amount': double.tryParse(r.discountController.text) ?? 0.0,
                  'discount_percent': r.discountPercent,
                };
              }).toList();

              // Use the category of the first item
              final String itemCategory = _stockType == 'Kitchen' ? 'Ration' : _itemRows.first.selectedItem.category;

              widget.purchasesBloc.add(AddTransactionEvent(
                receiptNo: randomReceipt,
                type: 'Sell',
                category: itemCategory,
                transactionDate: _dateController.text.trim(),
                contactPerson: _customerController.text.trim(),
                remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
                items: itemsList,
              ));

              Navigator.pop(context);
            }
          },
          child: Text(context.tr('confirm_sell')),
        ),
      ],
    );
  }
}

Widget _buildSubTabChip({
  required BuildContext context,
  required String label,
  required bool isSelected,
  required VoidCallback onSelected,
  required bool isDark,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(
        context.tr(label.toLowerCase().trim().replaceAll(' ', '_')),
        style: AppTheme.getFontStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? Colors.white : null,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppTheme.primaryColor,
      checkmarkColor: Colors.white,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
      side: BorderSide(
        color: isSelected
            ? AppTheme.primaryColor
            : isDark
            ? Colors.white.withAlpha(15)
            : Colors.grey.shade200,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final bool isDark;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = label.toLowerCase().contains('low') && (int.tryParse(value) ?? 0) > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E1E2E), const Color(0xFF1A1A2A), color.withOpacity(0.05)]
              : [Colors.white, color.withOpacity(0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : color.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: isDark ? color.withOpacity(0.05) : color.withOpacity(0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.12),
          width: 1.2,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.04),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: color.withOpacity(isDark ? 0.16 : 0.10),
                  border: Border.all(
                    color: color.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon, 
                    color: color, 
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            style: AppTheme.getFontStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                              height: 1.1,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasAlert) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(label.toLowerCase().trim().replaceAll(' ', '_')),
                      style: AppTheme.getFontStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlattenedTransactionRow {
  final PurchaseSellTransaction transaction;
  final TransactionItem item;
  _FlattenedTransactionRow({required this.transaction, required this.item});
}

class _FlattenedKitchenExpenseRow {
  final KitchenExpense originalExpense;
  final String itemName;
  final double qty;
  final String unit;
  final double pricePerUnit;
  final double totalPrice;
  final String displayRemarks;

  _FlattenedKitchenExpenseRow({
    required this.originalExpense,
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.pricePerUnit,
    required this.totalPrice,
    required this.displayRemarks,
  });
}

class _KitchenConsumptionRowData {
  StockItem selectedItem;
  final TextEditingController qtyController = TextEditingController(text: '1.0');
  final TextEditingController pricePerUnitController = TextEditingController();
  final TextEditingController totalPriceController = TextEditingController();

  _KitchenConsumptionRowData({required this.selectedItem}) {
    pricePerUnitController.text = selectedItem.latestPrice.toStringAsFixed(1);
    totalPriceController.text = (1.0 * selectedItem.latestPrice).toStringAsFixed(0);
  }

  void updateItem(StockItem item) {
    selectedItem = item;
    pricePerUnitController.text = item.latestPrice.toStringAsFixed(1);
    final double qty = double.tryParse(qtyController.text) ?? 0.0;
    totalPriceController.text = (qty * item.latestPrice).toStringAsFixed(0);
  }

  void updateQty(String val) {
    final double qty = double.tryParse(val) ?? 0.0;
    totalPriceController.text = (qty * selectedItem.latestPrice).toStringAsFixed(0);
  }

  void dispose() {
    qtyController.dispose();
    pricePerUnitController.dispose();
    totalPriceController.dispose();
  }
}

class _LogKitchenConsumptionDialog extends StatefulWidget {
  final List<StockItem> rationItems;
  final KitchenBloc bloc;

  const _LogKitchenConsumptionDialog({
    required this.rationItems,
    required this.bloc,
  });

  @override
  State<_LogKitchenConsumptionDialog> createState() => _LogKitchenConsumptionDialogState();
}

class _LogKitchenConsumptionDialogState extends State<_LogKitchenConsumptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_KitchenConsumptionRowData> _itemRows = [];
  final _remarksController = TextEditingController();
  final _dateController = TextEditingController(
    text: DateTime.now().toIso8601String().split('T')[0]
  );
  late List<StockItem> _availableItems;

  @override
  void initState() {
    super.initState();
    _availableItems = widget.rationItems.where((item) => item.quantity > 0).toList();
    if (_availableItems.isNotEmpty) {
      _itemRows.add(_KitchenConsumptionRowData(selectedItem: _availableItems.first));
    }
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _dateController.dispose();
    for (var row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  double _calculateTotalCost() {
    double sum = 0.0;
    for (var row in _itemRows) {
      final double qty = double.tryParse(row.qtyController.text) ?? 0.0;
      sum += qty * row.selectedItem.latestPrice;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Log Kitchen Consumption', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_availableItems.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _itemRows.add(_KitchenConsumptionRowData(selectedItem: _availableItems.first));
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: Text(context.tr('add_row')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
      content: Container(constraints: const BoxConstraints(maxWidth: 720),
        child: _availableItems.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No kitchen stock items available with quantity > 0.',
                    style: AppTheme.getFontStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                ),
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Date & Remarks
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              decoration: InputDecoration(labelText: context.tr('consumption_date'), suffixIcon: Icon(Icons.calendar_today_rounded, size: 16)),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              readOnly: true,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _dateController.text = picked.toIso8601String().split('T')[0];
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _remarksController,
                              decoration: const InputDecoration(
                                labelText: 'Remarks / Notes (Optional)',
                                hintText: 'e.g. daily menu backup, emergency meal'
                              ),
                              style: AppTheme.getFontStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Rows title
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Consumed Ration Items', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                      ),
                      const SizedBox(height: 8),

                      // Multi rows list
                      Column(
                        children: [
                          for (int idx = 0; idx < _itemRows.length; idx++) ...[
                            Builder(
                              builder: (ctx) {
                                final row = _itemRows[idx];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      // Dropdown Item Name
                                      Expanded(
                                        flex: 3,
                                        child: DropdownButtonFormField<StockItem>(
                                          isExpanded: true,
                                          value: row.selectedItem,
                                          decoration: const InputDecoration(labelText: 'Select Item', isDense: true),
                                          items: _availableItems.map((item) {
                                            return DropdownMenuItem<StockItem>(
                                              value: item,
                                              child: Text('${item.itemName} (${item.quantity.toStringAsFixed(1)} ${item.unit} avail.)', style: AppTheme.getFontStyle(fontSize: 12)),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() {
                                                row.updateItem(val);
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Quantity
                                      Expanded(
                                        flex: 1,
                                        child: TextFormField(
                                          controller: row.qtyController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(labelText: 'Qty (${row.selectedItem.unit})', isDense: true),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          onChanged: (val) {
                                            setState(() {
                                              row.updateQty(val);
                                            });
                                          },
                                          validator: (val) {
                                            if (val == null || double.tryParse(val) == null) return 'Required';
                                            final double qty = double.parse(val);
                                            if (qty <= 0) return 'Must be > 0';
                                            if (qty > row.selectedItem.quantity) return 'Exceeds stock';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Price / Unit
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.pricePerUnitController,
                                          decoration: const InputDecoration(labelText: 'Price/Unit', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          readOnly: true,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Total Price
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: row.totalPriceController,
                                          decoration: const InputDecoration(labelText: 'Total Price', isDense: true, prefixText: '₹'),
                                          style: AppTheme.getFontStyle(fontSize: 13),
                                          readOnly: true,
                                        ),
                                      ),

                                      // Delete row
                                      if (_itemRows.length > 1) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                          onPressed: () {
                                            setState(() {
                                              _itemRows.removeAt(idx);
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Grand Total
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withAlpha(30)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Grand Total Kitchen Consumption:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text('₹${_calculateTotalCost().toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.orange.shade800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        if (_availableItems.isNotEmpty)
          FilledButton(
            onPressed: () {
              if (_formKey.currentState!.validate() && _itemRows.isNotEmpty) {
                final List<Map<String, dynamic>> itemsList = _itemRows.map((r) {
                  final double qty = double.parse(r.qtyController.text);
                  return {
                    'stock_id': r.selectedItem.id,
                    'quantity': qty,
                    'estimated_cost': qty * r.selectedItem.latestPrice,
                  };
                }).toList();

                widget.bloc.add(IssueMealRationEvent(
                  mealName: 'Kitchen Consumption',
                  issueDate: _dateController.text.trim(),
                  remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
                  items: itemsList,
                ));

                Navigator.pop(context);
              }
            },
            child: Text(context.tr('confirm_log_consumption')),
          ),
      ],
    );
  }
}

