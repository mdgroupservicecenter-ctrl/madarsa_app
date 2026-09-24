import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Comprehensive keyboard shortcuts handler for Madarsa Desktop App.
class AppKeyboardShortcuts extends StatefulWidget {
  final Widget child;
  final void Function(int index)? onNavigateIndex;
  final void Function(String module)? onNavigateModule;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleTheme;
  final VoidCallback? onToggleLanguage;
  final VoidCallback? onCheckUpdates;
  final FocusNode? searchFocusNode;

  const AppKeyboardShortcuts({
    super.key,
    required this.child,
    this.onNavigateIndex,
    this.onNavigateModule,
    this.onRefresh,
    this.onToggleTheme,
    this.onToggleLanguage,
    this.onCheckUpdates,
    this.searchFocusNode,
  });

  @override
  State<AppKeyboardShortcuts> createState() => _AppKeyboardShortcutsState();
}

class _AppKeyboardShortcutsState extends State<AppKeyboardShortcuts> {
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'AppKeyboardShortcuts');

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final key = event.logicalKey;

    // Check if an input field is currently active
    final primaryFocus = FocusManager.instance.primaryFocus;
    final isTextInputFocused = primaryFocus?.context?.widget is EditableText;

    // ── 1. F1: Help / Shortcuts Cheat Sheet ──
    if (key == LogicalKeyboardKey.f1) {
      KeyboardShortcutsDialog.show(context);
      return KeyEventResult.handled;
    }

    // ── 2. F5: Refresh Current Screen ──
    if (key == LogicalKeyboardKey.f5) {
      widget.onRefresh?.call();
      return KeyEventResult.handled;
    }

    // ── 3. Escape: Unfocus search or input ──
    if (key == LogicalKeyboardKey.escape) {
      if (isTextInputFocused) {
        primaryFocus?.unfocus();
        return KeyEventResult.handled;
      }
    }

    // ── 4. Control key shortcuts ──
    if (isCtrl && !isAlt) {
      // If user is editing text in an input box, preserve native clipboard & undo keys:
      // Ctrl+C, Ctrl+V, Ctrl+X, Ctrl+A, Ctrl+Z, Ctrl+Y
      if (isTextInputFocused) {
        if (key == LogicalKeyboardKey.keyC ||
            key == LogicalKeyboardKey.keyV ||
            key == LogicalKeyboardKey.keyX ||
            key == LogicalKeyboardKey.keyA ||
            key == LogicalKeyboardKey.keyZ ||
            key == LogicalKeyboardKey.keyY) {
          return KeyEventResult.ignored;
        }
      }

      // Help guide via Ctrl + / or Ctrl + ?
      if (key == LogicalKeyboardKey.slash || (isShift && key == LogicalKeyboardKey.slash)) {
        KeyboardShortcutsDialog.show(context);
        return KeyEventResult.handled;
      }

      // Search Focus: Ctrl + F
      if (key == LogicalKeyboardKey.keyF) {
        if (widget.searchFocusNode != null) {
          widget.searchFocusNode!.requestFocus();
          return KeyEventResult.handled;
        }
      }

      // Refresh: Ctrl + R
      if (key == LogicalKeyboardKey.keyR) {
        widget.onRefresh?.call();
        return KeyEventResult.handled;
      }

      // Toggle Theme: Ctrl + T
      if (key == LogicalKeyboardKey.keyT) {
        widget.onToggleTheme?.call();
        return KeyEventResult.handled;
      }

      // Toggle Language: Ctrl + L
      if (key == LogicalKeyboardKey.keyL) {
        widget.onToggleLanguage?.call();
        return KeyEventResult.handled;
      }

      // Check Updates: Ctrl + U
      if (key == LogicalKeyboardKey.keyU) {
        widget.onCheckUpdates?.call();
        return KeyEventResult.handled;
      }

      // Dashboard: Ctrl + D
      if (key == LogicalKeyboardKey.keyD) {
        widget.onNavigateModule?.call('dashboard');
        return KeyEventResult.handled;
      }

      // Settings: Ctrl + Comma
      if (key == LogicalKeyboardKey.comma) {
        widget.onNavigateModule?.call('settings');
        return KeyEventResult.handled;
      }

      // Module navigation: Ctrl + 1 through Ctrl + 9
      if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        widget.onNavigateIndex?.call(0);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        widget.onNavigateIndex?.call(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
        widget.onNavigateIndex?.call(2);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
        widget.onNavigateIndex?.call(3);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
        widget.onNavigateIndex?.call(4);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
        widget.onNavigateIndex?.call(5);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
        widget.onNavigateIndex?.call(6);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
        widget.onNavigateIndex?.call(7);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
        widget.onNavigateIndex?.call(8);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}

/// A modal dialog that displays all available keyboard shortcuts in Madarsa App.
class KeyboardShortcutsDialog extends StatelessWidget {
  const KeyboardShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const KeyboardShortcutsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.keyboard_rounded,
                    color: AppTheme.primaryColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keyboard Shortcuts / کی بورڈ شارٹ کٹس',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ماؤس کے بغیر تیزی سے ایپ استعمال کرنے کے لیے شارٹ کٹس کا استعمال کریں',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close (Esc)',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Content List
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Windows Editing Shortcuts
                    _buildSectionHeader(
                      context,
                      title: 'Clipboard & Text Editing (متن اور کاپی پیسٹ)',
                      icon: Icons.edit_note_rounded,
                      color: const Color(0xFF0F766E),
                    ),
                    const SizedBox(height: 8),
                    _buildShortcutRow(context, keys: ['Ctrl', 'C'], title: 'Copy text', titleUrdu: 'کاپی کریں'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'V'], title: 'Paste text', titleUrdu: 'پیسٹ کریں'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'X'], title: 'Cut text', titleUrdu: 'کٹ کریں'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'A'], title: 'Select all', titleUrdu: 'سب منتخب کریں'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'Z'], title: 'Undo', titleUrdu: 'پہلے جیسا کریں (Undo)'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'Y'], title: 'Redo', titleUrdu: 'دوبارہ کریں (Redo)'),

                    const SizedBox(height: 18),

                    // Section 2: Navigation Shortcuts
                    _buildSectionHeader(
                      context,
                      title: 'Direct Navigation (براہ راست ٹیب نیویگیشن)',
                      icon: Icons.navigation_rounded,
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(height: 8),
                    _buildShortcutRow(context, keys: ['Ctrl', 'D'], title: 'Dashboard', titleUrdu: 'ڈیش بورڈ پر جائیں'),
                    _buildShortcutRow(context, keys: ['Ctrl', '1'], title: 'First Tab (Dashboard)', titleUrdu: 'پہلا ٹیب (ڈیش بورڈ)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '2'], title: 'Second Tab (Students)', titleUrdu: 'دوسرا ٹیب (طلباء)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '3'], title: 'Third Tab (Staff)', titleUrdu: 'تیسرا ٹیب (اسٹاف)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '4'], title: 'Fourth Tab (Classes)', titleUrdu: 'چوتھا ٹیب (کلاسز)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '5'], title: 'Fifth Tab (Exams)', titleUrdu: 'پانچواں ٹیب (امتحانات)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '6'], title: 'Sixth Tab (Attendance)', titleUrdu: 'چھٹا ٹیب (حاضری)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '7'], title: 'Seventh Tab (Fees)', titleUrdu: 'ساتواں ٹیب (فیس)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '8'], title: 'Eighth Tab (Reports)', titleUrdu: 'آٹھواں ٹیب (رپورٹس)'),
                    _buildShortcutRow(context, keys: ['Ctrl', '9'], title: 'Ninth Tab / Settings', titleUrdu: 'نواں ٹیب / سیٹنگز'),
                    _buildShortcutRow(context, keys: ['Ctrl', ','], title: 'Open Settings', titleUrdu: 'سیٹنگز کھولیں'),

                    const SizedBox(height: 18),

                    // Section 3: App Controls
                    _buildSectionHeader(
                      context,
                      title: 'Quick Controls & Tools (فوری کنٹرولز)',
                      icon: Icons.flash_on_rounded,
                      color: const Color(0xFFD97706),
                    ),
                    const SizedBox(height: 8),
                    _buildShortcutRow(context, keys: ['Ctrl', 'F'], title: 'Focus Search Bar', titleUrdu: 'تلاش بار پر فوکس کریں'),
                    _buildShortcutRow(context, keys: ['F5'], title: 'Refresh screen data', titleUrdu: 'ڈیٹا ریفریش کریں', altKeys: ['Ctrl', 'R']),
                    _buildShortcutRow(context, keys: ['Ctrl', 'T'], title: 'Toggle Dark / Light Mode', titleUrdu: 'ڈارک / لائٹ تھیم تبدیل کریں'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'L'], title: 'Switch Language', titleUrdu: 'زبان تبدیل کریں (اردو / انگریزی)'),
                    _buildShortcutRow(context, keys: ['Ctrl', 'U'], title: 'Check for Updates', titleUrdu: 'ایپ اپ ڈیٹ چیک کریں'),
                    _buildShortcutRow(context, keys: ['F1'], title: 'Show this Shortcuts Guide', titleUrdu: 'شارٹ کٹ گائیڈ کھولیں', altKeys: ['Ctrl', '/']),
                    _buildShortcutRow(context, keys: ['Esc'], title: 'Dismiss / Close Dialog / Unfocus', titleUrdu: 'بند کریں یا ان پٹ سے باہر نکلیں'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Footer
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('OK / ٹھیک ہے'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 30 : 15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutRow(
    BuildContext context, {
    required List<String> keys,
    List<String>? altKeys,
    required String title,
    required String titleUrdu,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          // Key Badges
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...keys.map((k) => _buildKeyBadge(k, isDark)),
              if (altKeys != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'or',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                    ),
                  ),
                ),
                ...altKeys.map((k) => _buildKeyBadge(k, isDark)),
              ],
            ],
          ),
          const SizedBox(width: 16),
          // Description
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.grey.shade200 : const Color(0xFF334155),
              ),
            ),
          ),
          // Urdu Description
          Text(
            titleUrdu,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyBadge(String label, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3748) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF4A5568) : const Color(0xFFCBD5E1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
        ),
      ),
    );
  }
}
