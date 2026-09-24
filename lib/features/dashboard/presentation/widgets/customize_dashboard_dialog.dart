import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/services/dashboard_config_service.dart';
import '../bloc/dashboard_state.dart';

class CustomizeDashboardDialog extends StatefulWidget {
  final List<DashboardCardConfig> currentCards;
  final DashboardLoaded? dashboardState;
  final void Function(List<DashboardCardConfig> updatedCards) onSaved;

  const CustomizeDashboardDialog({
    super.key,
    required this.currentCards,
    required this.onSaved,
    this.dashboardState,
  });

  static Future<void> show({
    required BuildContext context,
    required List<DashboardCardConfig> currentCards,
    required void Function(List<DashboardCardConfig> updatedCards) onSaved,
    DashboardLoaded? dashboardState,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => CustomizeDashboardDialog(
        currentCards: currentCards,
        onSaved: onSaved,
        dashboardState: dashboardState,
      ),
    );
  }

  @override
  State<CustomizeDashboardDialog> createState() => _CustomizeDashboardDialogState();
}

class _CustomizeDashboardDialogState extends State<CustomizeDashboardDialog> {
  late List<DashboardCardConfig> _editableCards;
  String _selectedCategory = 'All';
  String? _editingCardId;
  late TextEditingController _titleCtrl;
  late TextEditingController _subTitleCtrl;

  @override
  void initState() {
    super.initState();
    _editableCards = widget.currentCards
        .map((c) => c.copyWith(
              customTitle: c.customTitle,
              customSubtitle: c.customSubtitle,
              isVisible: c.isVisible,
              order: c.order,
            ))
        .toList();
    _titleCtrl = TextEditingController();
    _subTitleCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subTitleCtrl.dispose();
    super.dispose();
  }

  void _startEditingCard(DashboardCardConfig card) {
    setState(() {
      _editingCardId = card.id;
      _titleCtrl.text = card.customTitle ?? card.defaultTitle;
      _subTitleCtrl.text = card.customSubtitle ?? card.defaultSubtitle;
    });
  }

  void _saveEditingCard(DashboardCardConfig card) {
    setState(() {
      card.customTitle = _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim();
      card.customSubtitle = _subTitleCtrl.text.trim().isEmpty ? null : _subTitleCtrl.text.trim();
      _editingCardId = null;
    });
  }

  Future<void> _handleSave() async {
    await DashboardConfigService.saveCards(_editableCards);
    widget.onSaved(_editableCards);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('reset_confirm_title')),
        content: Text(context.tr('reset_confirm_content')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('reset')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final defaults = await DashboardConfigService.resetToDefault();
      widget.onSaved(defaults);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categories = ['All', 'Administration', 'Finance', 'Academic', 'Facilities'];
    String getCategoryLabel(String cat) {
      switch (cat) {
        case 'All':
          return context.tr('cat_all');
        case 'Administration':
          return context.tr('cat_admin');
        case 'Finance':
          return context.tr('cat_finance');
        case 'Academic':
          return context.tr('cat_academic');
        case 'Facilities':
          return context.tr('cat_facilities');
        default:
          return cat;
      }
    }

    final filteredCards = _selectedCategory == 'All'
        ? _editableCards
        : _editableCards.where((c) => c.category == _selectedCategory).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        width: min(760.0, MediaQuery.of(context).size.width - 40),
        constraints: BoxConstraints(maxHeight: min(720.0, MediaQuery.of(context).size.height - 40)),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.dashboard_customize_rounded, color: Color(0xFF0F766E), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('customize_dashboard_cards'),
                        style: AppTheme.getFontStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('customize_dashboard_desc'),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Category Filter Tabs ──
            RepaintBoundary(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(getCategoryLabel(cat)),
                        selectedColor: const Color(0xFF0F766E),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          setState(() => _selectedCategory = cat);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Cards List ──
            Expanded(
              child: ListView.separated(
                itemCount: filteredCards.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final card = filteredCards[index];
                  final isCurrentlyEditing = _editingCardId == card.id;

                  final previewVal = widget.dashboardState != null
                      ? DashboardConfigService.getCardDisplayValue(card.id, widget.dashboardState!)
                      : '0';

                  return RepaintBoundary(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: card.isVisible
                            ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                            : (isDark ? Colors.white10 : Colors.grey.shade200),
                      ),
                    ),
                    child: isCurrentlyEditing
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${context.tr('customize_edit_card')} (${card.getDisplayTitle(context)})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _titleCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Card Title',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller: _subTitleCtrl,
                                      style: const TextStyle(fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Subtitle / Description',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F766E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _saveEditingCard(card),
                                    child: Text(context.tr('save')),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.cancel_rounded, color: Colors.grey),
                                    onPressed: () => setState(() => _editingCardId = null),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              // Mini Gradient Icon
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: card.gradient,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(card.icon, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 14),

                              // Card Title & Subtitle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          card.getDisplayTitle(context),
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: card.isVisible
                                                ? (isDark ? Colors.white : Colors.black87)
                                                : Colors.grey,
                                          ),
                                        ),
                                        if (card.customTitle != null && card.customTitle!.trim().isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withAlpha(20),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Customized',
                                              style: TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${card.getDisplaySubtitle(context)} • $previewVal',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),

                              // Quick Rename/Edit Button
                              IconButton(
                                icon: const Icon(Icons.edit_note_rounded, size: 20),
                                tooltip: context.tr('customize_edit_card'),
                                onPressed: () => _startEditingCard(card),
                              ),

                              // Visibility Toggle
                              Switch(
                                value: card.isVisible,
                                activeThumbColor: const Color(0xFF0F766E),
                                onChanged: (val) {
                                  setState(() => card.isVisible = val);
                                },
                              ),
                            ],
                          ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Footer Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.restart_alt_rounded, size: 16, color: Colors.red),
                  label: Text(context.tr('reset_to_default'), style: const TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                  onPressed: _handleReset,
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                         backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(context.tr('save_changes'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _handleSave,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}