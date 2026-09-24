import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

/// A modern, beautiful, and responsive Date Range Picker dialog
/// designed specifically for desktop and mobile layouts.
///
/// Features:
/// - Quick Presets sidebar (Today, Yesterday, Last 7 Days, This Month, Last Month, etc.)
/// - 2-Month side-by-side view on desktop / wide screens
/// - Live range preview with hover highlights
/// - Clear day count badge (e.g. "15 Days Selected")
/// - Islamic/Deep Green theme consistent with the rest of the application
class AppDateRangePicker {
  static Future<DateTimeRange?> show(
    BuildContext context, {
    DateTimeRange? initialDateRange,
    DateTime? firstDate,
    DateTime? lastDate,
    String? title,
    bool showPresets = true,
  }) {
    final now = DateTime.now();
    return showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AppDateRangePickerDialog(
        initialDateRange: initialDateRange,
        firstDate: firstDate ?? DateTime(2015),
        lastDate: lastDate ?? DateTime(now.year + 10, 12, 31),
        title: title,
        showPresets: showPresets,
      ),
    );
  }
}

class AppDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? title;
  final bool showPresets;

  const AppDateRangePickerDialog({
    super.key,
    this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
    this.title,
    this.showPresets = true,
  });

  @override
  State<AppDateRangePickerDialog> createState() => _AppDateRangePickerDialogState();
}

class _AppDateRangePickerDialogState extends State<AppDateRangePickerDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _hoveredDate;
  late DateTime _currentMonth;
  String? _activePreset;

  @override
  void initState() {
    super.initState();
    if (widget.initialDateRange != null) {
      _startDate = _stripTime(widget.initialDateRange!.start);
      _endDate = _stripTime(widget.initialDateRange!.end);
      _currentMonth = DateTime(_startDate!.year, _startDate!.month, 1);
    } else {
      final now = DateTime.now();
      _currentMonth = DateTime(now.year, now.month, 1);
    }
  }

  DateTime _stripTime(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isBetween(DateTime target, DateTime start, DateTime end) {
    return target.isAfter(start) && target.isBefore(end);
  }

  void _onDayTapped(DateTime day) {
    setState(() {
      _activePreset = null;
      if (_startDate == null || (_startDate != null && _endDate != null)) {
        // Start new selection
        _startDate = day;
        _endDate = null;
      } else if (_startDate != null && _endDate == null) {
        if (day.isBefore(_startDate!)) {
          // Clicked day before start -> reset start to this day
          _startDate = day;
          _endDate = null;
        } else {
          // Completed range
          _endDate = day;
        }
      }
    });
  }

  void _applyPreset(String label, DateTime start, DateTime end) {
    setState(() {
      _activePreset = label;
      _startDate = _stripTime(start);
      _endDate = _stripTime(end);
      _currentMonth = DateTime(_startDate!.year, _startDate!.month, 1);
    });
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      if (_currentMonth.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1))) {
        _currentMonth = DateTime(widget.firstDate.year, widget.firstDate.month, 1);
      }
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      if (_currentMonth.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1))) {
        _currentMonth = DateTime(widget.lastDate.year, widget.lastDate.month, 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = screenSize.width >= 750;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 20,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: isDesktop ? 820 : min(440.0, screenSize.width - 32),
        constraints: BoxConstraints(
          maxHeight: min(640.0, screenSize.height - 48),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── 1. HEADER BANNER ─────────────────────────────────────
            _buildHeader(isDark),

            // ─── 2. MAIN BODY (PRESETS + CALENDARS) ───────────────────
            Expanded(
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showPresets) ...[
                          SizedBox(
                            width: 170,
                            child: _buildPresetsSidebar(isDark),
                          ),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: isDark ? Colors.white12 : Colors.grey.shade200,
                          ),
                        ],
                        Expanded(
                          child: _buildCalendarsArea(isDesktop: true, isDark: isDark),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        if (widget.showPresets) _buildPresetsMobileChips(isDark),
                        Expanded(
                          child: _buildCalendarsArea(isDesktop: false, isDark: isDark),
                        ),
                      ],
                    ),
            ),

            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),

            // ─── 3. FOOTER ACTIONS ────────────────────────────────────
            _buildFooter(isDark),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    String rangeText = 'Select Start and End Date';
    int dayCount = 0;

    if (_startDate != null && _endDate != null) {
      final startFmt = DateFormat('dd MMM yyyy').format(_startDate!);
      final endFmt = DateFormat('dd MMM yyyy').format(_endDate!);
      dayCount = _endDate!.difference(_startDate!).inDays + 1;
      rangeText = '$startFmt  ➔  $endFmt';
    } else if (_startDate != null) {
      final startFmt = DateFormat('dd MMM yyyy').format(_startDate!);
      rangeText = '$startFmt  ➔  Pick end date...';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D6B4E), Color(0xFF138A65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.calendar_month_rounded, color: Color(0xFFFACC15), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title ?? 'Select Date Range',
                      style: AppTheme.getFontStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (dayCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFACC15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dayCount == 1 ? '1 Day' : '$dayCount Days',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF064E3B),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  rangeText,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withAlpha(220),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ─── PRESETS SIDEBAR (DESKTOP) ──────────────────────────────────────
  Widget _buildPresetsSidebar(bool isDark) {
    final presets = _getPresetsList();

    return Container(
      color: isDark ? const Color(0xFF1A1A27) : const Color(0xFFF8FAF9),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: ListView.separated(
        itemCount: presets.length,
        separatorBuilder: (context, index) => const SizedBox(height: 3),
        itemBuilder: (context, index) {
          final p = presets[index];
          final isSelected = _activePreset == p.label;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _applyPreset(p.label, p.start, p.end),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryColor.withAlpha(25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      p.icon,
                      size: 15,
                      color: isSelected ? AppTheme.primaryColor : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : (isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.primaryColor),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── PRESETS CHIPS (MOBILE) ─────────────────────────────────────────
  Widget _buildPresetsMobileChips(bool isDark) {
    final presets = _getPresetsList();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: isDark ? const Color(0xFF1A1A27) : const Color(0xFFF8FAF9),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final p = presets[index];
          final isSelected = _activePreset == p.label;

          return ActionChip(
            avatar: Icon(p.icon, size: 14, color: isSelected ? Colors.white : AppTheme.primaryColor),
            label: Text(p.label, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : null)),
            backgroundColor: isSelected ? AppTheme.primaryColor : null,
            visualDensity: VisualDensity.compact,
            onPressed: () => _applyPreset(p.label, p.start, p.end),
          );
        },
      ),
    );
  }

  // ─── CALENDARS AREA ────────────────────────────────────────────────
  Widget _buildCalendarsArea({required bool isDesktop, required bool isDark}) {
    final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);

    return Column(
      children: [
        // Navigation Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 24),
                tooltip: 'Previous Month',
                onPressed: _prevMonth,
              ),
              if (isDesktop)
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            DateFormat('MMMM yyyy').format(_currentMonth),
                            style: AppTheme.getFontStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            DateFormat('MMMM yyyy').format(nextMonth),
                            style: AppTheme.getFontStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  DateFormat('MMMM yyyy').format(_currentMonth),
                  style: AppTheme.getFontStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 24),
                tooltip: 'Next Month',
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),

        // Calendars
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildMonthCalendar(_currentMonth, isDark)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildMonthCalendar(nextMonth, isDark)),
                    ],
                  )
                : _buildMonthCalendar(_currentMonth, isDark),
          ),
        ),
      ],
    );
  }

  // ─── SINGLE MONTH CALENDAR ─────────────────────────────────────────
  Widget _buildMonthCalendar(DateTime month, bool isDark) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7; // Sunday = 0
    final weekdays = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      children: [
        // Weekday header
        Row(
          children: weekdays.map((w) {
            return Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    w,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: w == 'Su' || w == 'Fr' ? Colors.green.shade700 : Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 4),

        // Days Grid
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.15,
            ),
            itemCount: 42, // 6 weeks * 7 days
            itemBuilder: (context, index) {
              final dayNumber = index - firstWeekday + 1;
              if (dayNumber < 1 || dayNumber > daysInMonth) {
                return const SizedBox();
              }

              final date = DateTime(month.year, month.month, dayNumber);
              return _buildDayCell(date, isDark);
            },
          ),
        ),
      ],
    );
  }

  // ─── DAY CELL ───────────────────────────────────────────────────────
  Widget _buildDayCell(DateTime date, bool isDark) {
    final isDisabled = date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate);
    final isToday = _isSameDay(date, DateTime.now());
    final isStart = _isSameDay(date, _startDate);
    final isEnd = _isSameDay(date, _endDate);

    // Range preview with hover
    DateTime? effectiveEnd = _endDate;
    if (_startDate != null && _endDate == null && _hoveredDate != null && _hoveredDate!.isAfter(_startDate!)) {
      effectiveEnd = _hoveredDate;
    }

    final isInRange = _startDate != null &&
        effectiveEnd != null &&
        _isBetween(date, _startDate!, effectiveEnd);

    final isStartOrEnd = isStart || isEnd;

    Color? cellBg;
    if (isStartOrEnd) {
      cellBg = AppTheme.primaryColor;
    } else if (isInRange) {
      cellBg = isDark
          ? const Color(0xFF13422A)
          : const Color(0xFFE8F5E9);
    }

    BorderRadius? borderRadius;
    if (isStart && isEnd) {
      borderRadius = BorderRadius.circular(20);
    } else if (isStart) {
      borderRadius = const BorderRadius.horizontal(left: Radius.circular(20));
    } else if (isEnd) {
      borderRadius = const BorderRadius.horizontal(right: Radius.circular(20));
    } else if (isInRange) {
      borderRadius = BorderRadius.zero;
    }

    return MouseRegion(
      onEnter: (_) {
        if (_startDate != null && _endDate == null && !isDisabled) {
          setState(() => _hoveredDate = date);
        }
      },
      onExit: (_) {
        if (_hoveredDate != null) {
          setState(() => _hoveredDate = null);
        }
      },
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isDisabled ? null : () => _onDayTapped(date),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: cellBg,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: isToday && !isStartOrEnd
                    ? Border.all(color: AppTheme.primaryColor, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isStartOrEnd || isToday ? FontWeight.bold : FontWeight.w500,
                  color: isDisabled
                      ? (isDark ? Colors.white24 : Colors.grey.shade400)
                      : isStartOrEnd
                          ? Colors.white
                          : isInRange
                              ? (isDark ? Colors.white : AppTheme.primaryColor)
                              : (isDark ? Colors.grey.shade200 : Colors.grey.shade900),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── FOOTER ────────────────────────────────────────────────────────
  Widget _buildFooter(bool isDark) {
    final canApply = _startDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Clear / Reset
          TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Reset', style: TextStyle(fontSize: 12.5)),
            onPressed: () {
              setState(() {
                _startDate = null;
                _endDate = null;
                _activePreset = null;
              });
            },
          ),
          const Spacer(),
          // Cancel
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 8),
          // Apply
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 17),
            label: const Text('Apply Range', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: canApply
                ? () {
                    final start = _startDate!;
                    final end = _endDate ?? _startDate!;
                    Navigator.pop(
                      context,
                      DateTimeRange(start: start, end: end),
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ─── PRESET DEFINITIONS ─────────────────────────────────────────────
  List<_DatePreset> _getPresetsList() {
    final now = DateTime.now();
    final today = _stripTime(now);
    final yesterday = today.subtract(const Duration(days: 1));

    // This week (Monday to today)
    final mondayThisWeek = today.subtract(Duration(days: (today.weekday - 1) % 7));

    // Last 7 days
    final last7Days = today.subtract(const Duration(days: 6));

    // This month (1st of this month to today)
    final startThisMonth = DateTime(today.year, today.month, 1);

    // Last month (1st of last month to last day of last month)
    final startLastMonth = DateTime(today.year, today.month - 1, 1);
    final endLastMonth = DateTime(today.year, today.month, 0);

    // Last 30 days
    final last30Days = today.subtract(const Duration(days: 29));

    // This year
    final startThisYear = DateTime(today.year, 1, 1);

    // Last year
    final startLastYear = DateTime(today.year - 1, 1, 1);
    final endLastYear = DateTime(today.year - 1, 12, 31);

    return [
      _DatePreset('Today', today, today, Icons.today_rounded),
      _DatePreset('Yesterday', yesterday, yesterday, Icons.history_rounded),
      _DatePreset('This Week', mondayThisWeek, today, Icons.view_week_rounded),
      _DatePreset('Last 7 Days', last7Days, today, Icons.date_range_rounded),
      _DatePreset('This Month', startThisMonth, today, Icons.calendar_view_month_rounded),
      _DatePreset('Last Month', startLastMonth, endLastMonth, Icons.event_note_rounded),
      _DatePreset('Last 30 Days', last30Days, today, Icons.history_toggle_off_rounded),
      _DatePreset('This Year', startThisYear, today, Icons.calendar_today_rounded),
      _DatePreset('Last Year', startLastYear, endLastYear, Icons.calendar_month_rounded),
    ];
  }
}

class _DatePreset {
  final String label;
  final DateTime start;
  final DateTime end;
  final IconData icon;

  _DatePreset(this.label, this.start, this.end, this.icon);
}
