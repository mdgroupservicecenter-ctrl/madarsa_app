import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/platform_utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/receipt_pdf_generator.dart';
import '../bloc/purchases_bloc.dart';
import '../../data/models/purchases_models.dart';
import '../../../kitchen/data/repositories/kitchen_repository.dart';
import '../../../../core/network/api_client.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String? _activeCategoryFilter;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    context.read<PurchasesBloc>().add(LoadPurchasesData());
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

    return BlocListener<PurchasesBloc, PurchasesState>(
      listener: (context, state) {
        if (state is PurchasesLoaded && state.actionMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(state.actionMessage!),
                ],
              ),
              backgroundColor: AppTheme.primaryColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else if (state is PurchasesError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(state.message)),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      },
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
                child: BlocBuilder<PurchasesBloc, PurchasesState>(
                  builder: (context, state) {
                    if (state is PurchasesLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is PurchasesError) {
                      return _buildErrorState(state.message);
                    }
                    if (state is PurchasesLoaded) {
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPurchasesLedgerTab(state, isDark),
                          _buildUnitsTab(state, isDark),
                          _buildCategoriesTab(state, isDark),
                        ],
                      );
                    }
                    return const SizedBox();
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 900;

        final buttons = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildHeaderAction(Icons.folder_open_rounded, 'Add Category', Colors.orange, () {
              _showAddCategoryDialog();
            }),
            _buildHeaderAction(Icons.category_rounded, 'Add Unit', Colors.teal, () {
              _showAddUnitDialog();
            }),
            FilledButton.icon(
              onPressed: () {
                final state = context.read<PurchasesBloc>().state;
                if (state is PurchasesLoaded) {
                  _showLogEntryDialog(state.units, state.categories);
                }
              },
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
              label: Text('Log Purchase Entry', style: AppTheme.getFontStyle(fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );

        if (isSmallScreen) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchases',
                style: AppTheme.getFontStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Track all purchases with stock units, custom categories, and live pricing logs',
                style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 16),
              buttons,
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Purchases',
                    style: AppTheme.getFontStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Track all purchases with stock units, custom categories, and live pricing logs',
                    style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            buttons,
          ],
        );
      },
    );
  }

  Widget _buildHeaderAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: color.withAlpha(80)),
      ),
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
        tabs: [Tab(text: 'Purchases'),
          Tab(text: context.tr('manage_unit_options')),
          Tab(text: context.tr('manage_category_options')),
        ],
      ),
    );
  }

  // ─── PURCHASES LEDGER TAB ─────────────────────────────────────────────
  Widget _buildPurchasesLedgerTab(PurchasesLoaded state, bool isDark) {
    final filtered = state.transactions.where((t) {
      if (t.type != 'Purchase') return false;

      // Filter by category
      if (_activeCategoryFilter != null && t.category != _activeCategoryFilter) return false;

      final q = _searchQuery.toLowerCase();
      final itemsSummary = t.items.map((i) => i.itemName).join(', ').toLowerCase();
      return t.receiptNo.toLowerCase().contains(q) ||
             t.category.toLowerCase().contains(q) ||
             itemsSummary.contains(q) ||
             (t.contactPerson ?? '').toLowerCase().contains(q) ||
             (t.remarks ?? '').toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 700;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats ────────────────────────────────────────────────
            _buildStats(state, isDark, isCompact),
            const SizedBox(height: 16),

            // ── Category Filter Chips ────────────────────────────────
            _buildFilterChips(state, isDark),
            const SizedBox(height: 14),

            // ── Search Bar (Full Width) ──────────────────────────────
            _buildSearchBar(isDark, 'Search purchases by Bill No, Category, items, Supplier...'),
            const SizedBox(height: 16),

            // ── Ledger Table/Cards ───────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _buildEmptyState('No purchase transactions logged.')
                  : SingleChildScrollView(
                      child: _buildCardTable(
                        columns: ['Date', 'Bill No', 'Category', 'Supplier Name', 'Items Summary', 'Grand Total', 'Remarks', 'Actions'],
                        rows: filtered.map((t) => [
                          t.transactionDate,
                          t.receiptNo,
                          t.category,
                          t.contactPerson ?? '-',
                          t.items.map((i) => '${i.itemName} (${i.quantity.toStringAsFixed(1)} ${i.unit} @ ₹${i.pricePerUnit.toStringAsFixed(0)})').join(', '),
                          '₹${t.totalPrice.toStringAsFixed(0)}',
                          t.remarks ?? '-',
                        ]).toList(),
                        rowsBuilder: (index) {
                          final t = filtered[index];
                          
                          // Format items summary nicely
                          final summaryText = t.items.map((i) => '${i.itemName} (${i.quantity.toStringAsFixed(1)} ${i.unit} @ ₹${i.pricePerUnit.toStringAsFixed(0)})').join(', ');
                          final displaySummary = summaryText.length > 50 ? '${summaryText.substring(0, 47)}...' : summaryText;

                          return [
                            DataCell(Text(t.transactionDate, style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(Text(t.receiptNo, style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withAlpha(20),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  t.category,
                                  style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                ),
                              ),
                            ),
                            DataCell(Text(t.contactPerson ?? '-', style: AppTheme.getFontStyle(fontSize: 13))),
                            DataCell(
                              Tooltip(
                                message: summaryText,
                                child: Text(displaySummary, style: AppTheme.getFontStyle(fontSize: 13)),
                              )
                            ),
                            DataCell(Text('₹${t.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                            DataCell(Text(t.remarks ?? '-', style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500))),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.info_outline_rounded, size: 18, color: Colors.teal),
                                    tooltip: 'View Bill Items',
                                    onPressed: () => _showBillDetailsDialog(t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                                    tooltip: context.tr('edit_bill_log'),
                                    onPressed: () => _showLogEntryDialog(state.units, state.categories, transaction: t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                                    tooltip: 'Print PDF Receipt',
                                    onPressed: () => _printPdfInvoice(t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                    tooltip: context.tr('delete_bill_log'),
                                    onPressed: () => _confirmDelete(
                                      'Delete this purchase bill? Stock levels will be reversed.',
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

  Widget _buildStats(PurchasesLoaded state, bool isDark, bool isCompact) {
    final purchases = state.transactions.where((t) => t.type == 'Purchase').toList();
    final totalAmount = purchases.fold<double>(0, (sum, t) => sum + t.totalPrice);
    final totalBills = purchases.length;
    final totalCategories = state.categories.length;
    final totalUnits = state.units.length;

    final stats = [
      (
        label: context.tr('total_purchases'),
        value: '₹${totalAmount.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF0D6B4E),
      ),
      (
        label: context.tr('total_bills'),
        value: totalBills.toString(),
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF1565C0),
      ),
      (
        label: context.tr('categories'),
        value: totalCategories.toString(),
        icon: Icons.category_rounded,
        color: const Color(0xFF6A1B9A),
      ),
      (
        label: context.tr('units_registered'),
        value: totalUnits.toString(),
        icon: Icons.scale_rounded,
        color: const Color(0xFFE65100),
      ),
    ];

    return isCompact
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
          );
  }

  Widget _buildFilterChips(PurchasesLoaded state, bool isDark) {
    final categories = ['All', ...state.categories.map((c) => c.name)];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isActive =
              (cat == 'All' && _activeCategoryFilter == null) ||
              _activeCategoryFilter == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                cat,
                style: AppTheme.getFontStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? Colors.white : null,
                ),
              ),
              selected: isActive,
              onSelected: (_) {
                setState(() {
                  _activeCategoryFilter = cat == 'All' ? null : cat;
                });
              },
              selectedColor: AppTheme.primaryColor,
              checkmarkColor: Colors.white,
              backgroundColor: isDark
                  ? const Color(0xFF1E1E2E)
                  : Colors.grey.shade100,
              side: BorderSide(
                color: isActive
                    ? AppTheme.primaryColor
                    : isDark
                    ? Colors.white.withAlpha(15)
                    : Colors.grey.shade200,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── UNIT OPTIONS MANAGEMENT TAB ────────────────────────────────────
  Widget _buildUnitsTab(PurchasesLoaded state, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Active measurement unit options for products, foods, and stocks:',
            style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: state.units.isEmpty
              ? _buildEmptyState('No measurement units registered.')
              : SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: state.units.map((unit) {
                        return Chip(
                          backgroundColor: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                          side: BorderSide(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                          label: Text(
                            unit.name,
                            style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16, color: Colors.red),
                          onDeleted: () => _confirmDelete(
                            'Delete the unit option "${unit.name}"?',
                            () => context.read<PurchasesBloc>().add(DeleteUnitEvent(unit.id)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // ─── CATEGORY OPTIONS MANAGEMENT TAB ────────────────────────────────
  Widget _buildCategoriesTab(PurchasesLoaded state, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Active classification categories for transactions (e.g. Ration, Construction):',
            style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: state.categories.isEmpty
              ? _buildEmptyState('No transaction categories registered.')
              : SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.grey.shade200),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: state.categories.map((cat) {
                        return Chip(
                          backgroundColor: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                          side: BorderSide(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade300),
                          label: Text(
                            cat.name,
                            style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16, color: Colors.red),
                          onDeleted: () => _confirmDelete(
                            'Delete the category option "${cat.name}"?',
                            () => context.read<PurchasesBloc>().add(DeleteCategoryEvent(cat.id)),
                          ),
                        );
                      }).toList(),
                    ),
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
              .map((c) => DataColumn(label: Text(c, style: AppTheme.getFontStyle(fontWeight: FontWeight.w600, fontSize: 13))))
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

  // ─── CONFIRM DELETE DIALOG ──────────────────────────────────────
  void _confirmDelete(String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Deletion', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message, style: AppTheme.getFontStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
  }

  // ─── VIEW BILL DETAILS DIALOG ───────────────────────────────────
  void _showBillDetailsDialog(PurchaseSellTransaction t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Bill No: ${t.receiptNo}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Container(constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${t.transactionDate}', style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade500)),
              Text('Type: ${t.type}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.type == 'Purchase' ? Colors.green : Colors.blue)),
              Text('Category: ${t.category}', style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              Text(t.type == 'Purchase' ? 'Supplier: ${t.contactPerson ?? "-"}' : 'Customer: ${t.contactPerson ?? "-"}', style: AppTheme.getFontStyle(fontSize: 13)),
              if (t.remarks != null && t.remarks!.isNotEmpty)
                Text('Remarks: ${t.remarks}', style: AppTheme.getFontStyle(fontSize: 13, color: Colors.grey.shade600)),
              const Divider(height: 24),
              Text('Items List', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int idx = 0; idx < t.items.length; idx++) ...[
                        Builder(
                          builder: (context) {
                            final item = t.items[idx];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF151522) : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.itemName, style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      Text('Quantity: ${item.quantity.toStringAsFixed(1)} ${item.unit}', style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500)),
                                      Text('Unit Price: ₹${item.pricePerUnit.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontSize: 12, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                  Text('₹${item.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('₹${t.totalPrice.toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16, color: t.type == 'Purchase' ? Colors.green : Colors.blue)),
                ],
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('close'))),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _printPdfInvoice(t);
            },
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
            label: Text(context.tr('print_pdf')),
          ),
        ],
      ),
    );
  }

  // ─── PRINT PDF INVOICE RECEIPT ───────────────────────────────────
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



  // ─── LOG / EDIT PURCHASE / SALE DIALOG (MULTI-ITEM LOG WITH BILLING) ────
  void _showLogEntryDialog(
    List<UnitModel> units, 
    List<CategoryModel> categories, 
    {PurchaseSellTransaction? transaction,
    String? defaultType,
    String? defaultCategory}
  ) {
    showDialog(
      context: context,
      builder: (ctx) => LogEntryDialog(
        units: units,
        categories: categories,
        transaction: transaction,
        bloc: context.read<PurchasesBloc>(),
        defaultType: defaultType,
        defaultCategory: defaultCategory,
      ),
    );
  }

  void _showAddUnitDialog() {
    showDialog(
      context: context,
      builder: (dContext) => AddUnitDialog(bloc: context.read<PurchasesBloc>()),
    );
  }

  void _showAddCategoryDialog() {
    showDialog(
      context: context,
      builder: (dContext) => AddCategoryDialog(bloc: context.read<PurchasesBloc>()),
    );
  }

  // ─── EMPTY STATE WIDGET ──────────────────────────────────────────
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_rounded, size: 64, color: Colors.grey.shade400),
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
}

// ─── LOG ENTRY DIALOG (ENCAPSULATED STATEFUL WIDGET FOR SOLID LIFECYCLE) ───
class LogEntryDialog extends StatefulWidget {
  final List<UnitModel> units;
  final List<CategoryModel> categories;
  final PurchaseSellTransaction? transaction;
  final PurchasesBloc bloc;
  final String? defaultType;
  final String? defaultCategory;

  const LogEntryDialog({
    super.key,
    required this.units,
    required this.categories,
    this.transaction,
    required this.bloc,
    this.defaultType,
    this.defaultCategory,
  });

  @override
  State<LogEntryDialog> createState() => _LogEntryDialogState();
}

class _LogEntryDialogState extends State<LogEntryDialog> {
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

  final _formKey = GlobalKey<FormState>();
  late String _type;
  late String _selectedCategory;
  late TextEditingController _receiptNoController;
  late TextEditingController _contactController;
  late TextEditingController _remarksController;
  late TextEditingController _dateController;
  final List<_FormItemRowData> _itemRows = [];
  List<String> _stockItemNames = [];

  @override
  void initState() {
    super.initState();
    final isEditMode = widget.transaction != null;
    _type = isEditMode ? widget.transaction!.type : (widget.defaultType ?? 'Purchase');
    
    if (isEditMode) {
      _selectedCategory = widget.transaction!.category;
    } else if (widget.defaultCategory != null) {
      final exists = widget.categories.any((c) => c.name.toLowerCase() == widget.defaultCategory!.toLowerCase());
      if (exists) {
        _selectedCategory = widget.categories.firstWhere((c) => c.name.toLowerCase() == widget.defaultCategory!.toLowerCase()).name;
      } else {
        _selectedCategory = widget.categories.isNotEmpty ? widget.categories.first.name : 'Other';
      }
    } else {
      _selectedCategory = widget.categories.isNotEmpty ? widget.categories.first.name : 'Other';
    }

    _receiptNoController = TextEditingController(
      text: isEditMode 
          ? widget.transaction!.receiptNo 
          : 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'
    );
    _contactController = TextEditingController(
      text: isEditMode ? widget.transaction!.contactPerson : ''
    );
    _remarksController = TextEditingController(
      text: isEditMode ? widget.transaction!.remarks : ''
    );
    _dateController = TextEditingController(
      text: isEditMode ? widget.transaction!.transactionDate : DateTime.now().toIso8601String().split('T')[0]
    );

    if (isEditMode) {
      for (var item in widget.transaction!.items) {
        final row = _FormItemRowData(
          selectedUnit: item.unit,
          initialName: item.itemName,
          initialQty: item.quantity,
          initialPricePerUnit: item.pricePerUnit,
          initialTotalPrice: item.totalPrice,
          initialDiscount: item.discountAmount,
        );
        _itemRows.add(row);
      }
    } else {
      _itemRows.add(_FormItemRowData(
        selectedUnit: widget.units.isNotEmpty ? widget.units.first.name : 'kg'
      ));
    }

    _loadStockItemNames();
  }

  Future<void> _loadStockItemNames() async {
    try {
      final kitchenRepo = KitchenRepository(ApiClient());
      final stockItems = await kitchenRepo.getStock();
      if (mounted) {
        setState(() {
          _stockItemNames = stockItems.map((item) => item.itemName).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load kitchen stock items for dropdown: $e');
    }
  }

  @override
  void dispose() {
    _receiptNoController.dispose();
    _contactController.dispose();
    _remarksController.dispose();
    _dateController.dispose();
    for (var row in _itemRows) {
      row.dispose();
    }
    super.dispose();
  }

  List<String> get _uniqueCategories {
    final list = <String>[];
    for (var c in widget.categories) {
      final name = c.name.trim();
      if (name.isNotEmpty && !list.any((item) => item.toLowerCase() == name.toLowerCase())) {
        list.add(name);
      }
    }
    if (list.isEmpty) {
      list.add('General');
    }
    if (!list.any((item) => item.toLowerCase() == _selectedCategory.toLowerCase())) {
      list.add(_selectedCategory);
    }
    return list;
  }

  List<String> get _uniqueUnits {
    final list = <String>[];
    for (var u in widget.units) {
      final name = u.name.trim();
      if (name.isNotEmpty && !list.any((item) => item.toLowerCase() == name.toLowerCase())) {
        list.add(name);
      }
    }
    if (list.isEmpty) {
      list.addAll(['kg', 'litre', 'pcs', 'box', 'meter', 'gram']);
    }
    return list;
  }

  double _calculateGrandTotal() {
    double sum = 0.0;
    for (var row in _itemRows) {
      final price = double.tryParse(row.priceController.text) ?? 0.0;
      sum += price;
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditMode = widget.transaction != null;
    final categoriesList = _uniqueCategories;
    if (!categoriesList.contains(_selectedCategory)) {
      _selectedCategory = categoriesList.firstWhere(
        (c) => c.toLowerCase() == _selectedCategory.toLowerCase(),
        orElse: () => categoriesList.first,
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEditMode ? 'Edit Purchase Entry' : 'Log Purchase (Multi-Item Entry)', 
        style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)
      ),
      content: Container(constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Receipt No, Category, Date
                context.isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _receiptNoController,
                            decoration: const InputDecoration(labelText: 'Receipt / Bill No.', hintText: 'e.g. INV-1002'),
                            style: AppTheme.getFontStyle(fontSize: 13),
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            decoration: InputDecoration(labelText: context.tr('category')),
                            items: categoriesList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppTheme.getFontStyle(fontSize: 13)))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCategory = val);
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _dateController,
                            decoration: const InputDecoration(labelText: 'Transaction Date'),
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
                              controller: _receiptNoController,
                              decoration: const InputDecoration(labelText: 'Receipt / Bill No.', hintText: 'e.g. INV-1002'),
                              style: AppTheme.getFontStyle(fontSize: 13),
                              validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              decoration: InputDecoration(labelText: context.tr('category')),
                              items: categoriesList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: AppTheme.getFontStyle(fontSize: 13)))).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedCategory = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              decoration: const InputDecoration(labelText: 'Transaction Date'),
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

                // Contact Person & Remarks
                _buildResponsiveRow(
                  context,
                  TextFormField(
                    controller: _contactController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name',
                      hintText: 'e.g. Al-Madina Traders',
                    ),
                    style: AppTheme.getFontStyle(fontSize: 13),
                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(labelText: 'Remarks / Notes'),
                    style: AppTheme.getFontStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),

                // Section header for billing items list
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Billing Items List', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _itemRows.add(_FormItemRowData(
                            selectedUnit: widget.units.isNotEmpty ? widget.units.first.name : 'kg'
                          ));
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
                const SizedBox(height: 8),

                // Dynamic Item rows
                Column(
                  children: [
                    for (int idx = 0; idx < _itemRows.length; idx++) ...[
                      Builder(
                        builder: (ctx) {
                          final row = _itemRows[idx];
                          final rowUnitsList = List<String>.from(_uniqueUnits);
                          if (!rowUnitsList.contains(row.selectedUnit)) {
                            rowUnitsList.add(row.selectedUnit);
                          }

                          return Container(
                            key: ObjectKey(row), // Crucial fix for element identity
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
                                _buildResponsiveRow(
                                  context,
                                  Autocomplete<String>(
                                    initialValue: TextEditingValue(text: row.initialName),
                                    optionsBuilder: (TextEditingValue textEditingValue) {
                                      if (textEditingValue.text.isEmpty) {
                                        return _stockItemNames;
                                      }
                                      return _stockItemNames.where((option) =>
                                          option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                                    },
                                    onSelected: (String selection) {
                                      if (row.nameController != null) {
                                        row.nameController!.text = selection;
                                      }
                                    },
                                    fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                                      row.nameController = textController;

                                      return TextFormField(
                                        controller: textController,
                                        focusNode: focusNode,
                                        decoration: InputDecoration(
                                          labelText: context.tr('item_name'),
                                          hintText: 'e.g. Rice',
                                          isDense: true,
                                        ),
                                        style: AppTheme.getFontStyle(fontSize: 13),
                                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                                      );
                                    },
                                  ),
                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: row.selectedUnit,
                                    decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                                    items: rowUnitsList.map((u) => DropdownMenuItem(value: u, child: Text(u, style: AppTheme.getFontStyle(fontSize: 12)))).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => row.selectedUnit = val);
                                    },
                                  ),
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
                                          final double qty = double.tryParse(val) ?? 0.0;
                                          final double pUnit = double.tryParse(row.pricePerUnitController.text) ?? 0.0;
                                          final double discount = double.tryParse(row.discountController.text) ?? 0.0;
                                          
                                          final double baseTotal = qty * pUnit;
                                          final double finalTotal = baseTotal - discount;
                                          row.priceController.text = finalTotal.toStringAsFixed(0);
                                          if (baseTotal > 0) {
                                            setState(() {
                                              row.discountPercent = (discount / baseTotal) * 100;
                                            });
                                          }
                                        },
                                        validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) <= 0) ? 'Required' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Price / Unit
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.pricePerUnitController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(labelText: 'Price/Unit', isDense: true),
                                        style: AppTheme.getFontStyle(fontSize: 13),
                                        onChanged: (val) {
                                          final double qty = double.tryParse(row.qtyController.text) ?? 1.0;
                                          final double pUnit = double.tryParse(val) ?? 0.0;
                                          final double discount = double.tryParse(row.discountController.text) ?? 0.0;
                                          
                                          final double baseTotal = qty * pUnit;
                                          final double finalTotal = baseTotal - discount;
                                          row.priceController.text = finalTotal.toStringAsFixed(0);
                                          if (baseTotal > 0) {
                                            setState(() {
                                              row.discountPercent = (discount / baseTotal) * 100;
                                            });
                                          }
                                        },
                                        validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) < 0) ? 'Required' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Total Price
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: row.priceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(labelText: 'Total Price', isDense: true),
                                        style: AppTheme.getFontStyle(fontSize: 13),
                                        onChanged: (val) {
                                          final double qty = double.tryParse(row.qtyController.text) ?? 1.0;
                                          final double finalTotal = double.tryParse(val) ?? 0.0;
                                          final double discount = double.tryParse(row.discountController.text) ?? 0.0;
                                          
                                          final double baseTotal = finalTotal + discount;
                                          final double pUnit = qty > 0 ? baseTotal / qty : 0.0;
                                          row.pricePerUnitController.text = pUnit.toStringAsFixed(1);
                                          if (baseTotal > 0) {
                                            setState(() {
                                              row.discountPercent = (discount / baseTotal) * 100;
                                            });
                                          }
                                        },
                                        validator: (val) => (val == null || double.tryParse(val) == null || double.parse(val) < 0) ? 'Required' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Discount
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
                                          final double qty = double.tryParse(row.qtyController.text) ?? 1.0;
                                          final double pUnit = double.tryParse(row.pricePerUnitController.text) ?? 0.0;
                                          final double discount = double.tryParse(val) ?? 0.0;
                                          
                                          final double baseTotal = qty * pUnit;
                                          final double finalTotal = baseTotal - discount;
                                          row.priceController.text = finalTotal.toStringAsFixed(0);
                                          if (baseTotal > 0) {
                                            setState(() {
                                              row.discountPercent = (discount / baseTotal) * 100;
                                            });
                                          }
                                        },
                                      ),
                                    ),

                                    // Delete item row icon
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
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // Grand Total Display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _type == 'Purchase' ? Colors.green.withAlpha(15) : Colors.blue.withAlpha(15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _type == 'Purchase' ? Colors.green.withAlpha(30) : Colors.blue.withAlpha(30)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Grand Total Invoice Amount:', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('₹${_calculateGrandTotal().toStringAsFixed(0)}', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _type == 'Purchase' ? Colors.green.shade800 : Colors.blue.shade800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text(context.tr('cancel'))
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final List<Map<String, dynamic>> itemsList = _itemRows.map((r) {
                final double qty = double.tryParse(r.qtyController.text) ?? 1.0;
                final double totalPrice = double.tryParse(r.priceController.text) ?? 0.0;
                final double pricePerUnit = double.tryParse(r.pricePerUnitController.text) ?? 0.0;
                final double discountAmount = double.tryParse(r.discountController.text) ?? 0.0;
                final double discountPercent = r.discountPercent;
                return {
                  'item_name': r.nameController?.text.trim() ?? r.initialName,
                  'quantity': qty,
                  'unit': r.selectedUnit,
                  'price_per_unit': pricePerUnit,
                  'total_price': totalPrice,
                  'discount_amount': discountAmount,
                  'discount_percent': discountPercent,
                };
              }).toList();

              Navigator.pop(context);

              if (isEditMode) {
                widget.bloc.add(UpdateTransactionEvent(
                  id: widget.transaction!.id,
                  receiptNo: _receiptNoController.text.trim(),
                  type: _type,
                  category: _selectedCategory,
                  transactionDate: _dateController.text.trim(),
                  contactPerson: _contactController.text.trim(),
                  remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
                  items: itemsList,
                ));
              } else {
                widget.bloc.add(AddTransactionEvent(
                  receiptNo: _receiptNoController.text.trim(),
                  type: _type,
                  category: _selectedCategory,
                  transactionDate: _dateController.text.trim(),
                  contactPerson: _contactController.text.trim(),
                  remarks: _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
                  items: itemsList,
                ));
              }
            }
          },
          child: Text(isEditMode ? 'Update Entry' : 'Save & Log Entry'),
        ),
      ],
    );
  }
}

// Stateful row data representation for Log entry form fields list
class _FormItemRowData {
  TextEditingController? nameController;
  final TextEditingController qtyController = TextEditingController(text: '1.0');
  final TextEditingController pricePerUnitController = TextEditingController(text: '0');
  final TextEditingController priceController = TextEditingController(text: '0'); // Total Price
  final TextEditingController discountController = TextEditingController(text: '0');
  double discountPercent = 0.0;
  String initialName;
  String selectedUnit;

  _FormItemRowData({
    required this.selectedUnit, 
    this.initialName = '',
    double? initialQty,
    double? initialPricePerUnit,
    double? initialTotalPrice,
    double? initialDiscount,
  }) {
    if (initialQty != null) qtyController.text = initialQty.toStringAsFixed(1);
    if (initialPricePerUnit != null) pricePerUnitController.text = initialPricePerUnit.toStringAsFixed(1);
    if (initialTotalPrice != null) priceController.text = initialTotalPrice.toStringAsFixed(0);
    if (initialDiscount != null) {
      discountController.text = initialDiscount.toStringAsFixed(0);
      final double qty = initialQty ?? 1.0;
      final double pUnit = initialPricePerUnit ?? 0.0;
      final double baseTotal = qty * pUnit;
      if (baseTotal > 0) {
        discountPercent = (initialDiscount / baseTotal) * 100;
      }
    }
  }

  void dispose() {
    qtyController.dispose();
    pricePerUnitController.dispose();
    priceController.dispose();
    discountController.dispose();
  }
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(isDark ? 35 : 18),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTheme.getFontStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppTheme.getFontStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddUnitDialog extends StatefulWidget {
  final PurchasesBloc bloc;
  const AddUnitDialog({super.key, required this.bloc});

  @override
  State<AddUnitDialog> createState() => _AddUnitDialogState();
}

class _AddUnitDialogState extends State<AddUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add New Unit Option', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Unit Name', hintText: 'e.g. box, dozen, meter'),
          style: AppTheme.getFontStyle(fontSize: 14),
          validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final val = _nameController.text.trim();
              Navigator.pop(context);
              widget.bloc.add(AddUnitEvent(val));
            }
          },
          child: Text(context.tr('add')),
        ),
      ],
    );
  }
}

class AddCategoryDialog extends StatefulWidget {
  final PurchasesBloc bloc;
  const AddCategoryDialog({super.key, required this.bloc});

  @override
  State<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add New Category Option', style: AppTheme.getFontStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          decoration: InputDecoration(labelText: context.tr('category_name'), hintText: 'e.g. Construction, Stationery'),
          style: AppTheme.getFontStyle(fontSize: 14),
          validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final val = _nameController.text.trim();
              Navigator.pop(context);
              widget.bloc.add(AddCategoryEvent(val));
            }
          },
          child: Text(context.tr('add')),
        ),
      ],
    );
  }
}
