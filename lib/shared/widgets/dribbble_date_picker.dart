import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';

/// A Dribbble-inspired modern date picker with inline Year selection grid (1900-2150),
/// arrow-based Month navigation, and adaptive Mobile BottomSheet & Desktop Dialog views.
class DribbbleDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String title;
  final bool isBottomSheet;

  const DribbbleDatePickerDialog({
    super.key,
    required this.initialDate,
    this.firstDate,
    this.lastDate,
    this.title = 'Select Schedule Date',
    this.isBottomSheet = false,
  });

  static Future<DateTime?> show({
    required BuildContext context,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Select Schedule Date',
  }) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 700;

    final fDate = firstDate ?? DateTime(1900);
    final lDate = lastDate ?? DateTime(2150, 12, 31);

    if (isMobile) {
      return showModalBottomSheet<DateTime>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: DribbbleDatePickerDialog(
            initialDate: initialDate ?? DateTime.now(),
            firstDate: fDate,
            lastDate: lDate,
            title: title,
            isBottomSheet: true,
          ),
        ),
      );
    }

    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => DribbbleDatePickerDialog(
        initialDate: initialDate ?? DateTime.now(),
        firstDate: fDate,
        lastDate: lDate,
        title: title,
        isBottomSheet: false,
      ),
    );
  }

  @override
  State<DribbbleDatePickerDialog> createState() => _DribbbleDatePickerDialogState();
}

class _DribbbleDatePickerDialogState extends State<DribbbleDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _focusedMonth;
  bool _isYearPickerOpen = false;
  late ScrollController _yearScrollController;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _focusedMonth = DateTime(widget.initialDate.year, widget.initialDate.month, 1);

    final yearIndex = (_focusedMonth.year - 1900).clamp(0, 250);
    final initialOffset = (yearIndex ~/ 4) * 44.0;
    _yearScrollController = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _yearScrollController.dispose();
    super.dispose();
  }

  void _selectPreset(DateTime date) {
    setState(() {
      _selectedDate = date;
      _focusedMonth = DateTime(date.year, date.month, 1);
      _isYearPickerOpen = false;
    });
  }

  void _changeMonth(int increment) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + increment, 1);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return _isSameDay(date, now);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700 || widget.isBottomSheet;

    final bodyContent = SafeArea(
      top: false,
      child: Container(
        width: isMobile ? double.infinity : 395,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          borderRadius: widget.isBottomSheet
              ? const BorderRadius.vertical(top: Radius.circular(28))
              : BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── MOBILE BOTTOMSHEET DRAG HANDLE ───
              if (widget.isBottomSheet)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF0F3814),
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white38,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

              // ─── DRIBBBLE GRADIENT HEADER CARD ───
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 18,
                  vertical: isMobile ? 12 : 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF0F3814),
                      Color(0xFF1B5E20),
                      Color(0xFF2E7D32),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            widget.title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.getFontStyle(
                              fontSize: isMobile ? 10 : 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFD4AF37),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tapping Year Badge toggles Inline Year Grid
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isYearPickerOpen = !_isYearPickerOpen;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _isYearPickerOpen ? const Color(0xFFD4AF37) : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isYearPickerOpen ? const Color(0xFFD4AF37) : Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat('yyyy').format(_focusedMonth),
                                  style: AppTheme.getFontStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _isYearPickerOpen ? const Color(0xFF0F3814) : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  _isYearPickerOpen ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                                  size: 16,
                                  color: _isYearPickerOpen ? const Color(0xFF0F3814) : Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, MMM d').format(_selectedDate),
                      style: AppTheme.getFontStyle(
                        fontSize: isMobile ? 19 : 21,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick Preset Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildPresetChip('Today', DateTime.now()),
                          const SizedBox(width: 6),
                          _buildPresetChip('Tomorrow', DateTime.now().add(const Duration(days: 1))),
                          const SizedBox(width: 6),
                          _buildPresetChip('+7 Days', DateTime.now().add(const Duration(days: 7))),
                          const SizedBox(width: 6),
                          _buildPresetChip(
                            'End of Month',
                            DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── MONTH NAVIGATION BAR ───
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 24),
                      splashRadius: 20,
                      onPressed: () => _changeMonth(-1),
                      tooltip: 'Previous Month',
                    ),
                    // Tapping Month/Year Title toggles Inline Year Grid
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _isYearPickerOpen = !_isYearPickerOpen;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isYearPickerOpen
                              ? AppTheme.primaryColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text(
                              DateFormat('MMMM yyyy').format(_focusedMonth),
                              style: AppTheme.getFontStyle(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _isYearPickerOpen ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 24),
                      splashRadius: 20,
                      onPressed: () => _changeMonth(1),
                      tooltip: 'Next Month',
                    ),
                  ],
                ),
              ),

              // ─── BODY: INLINE YEAR GRID OR CALENDAR GRID ───
              if (_isYearPickerOpen)
                Container(
                  height: isMobile ? 240 : 250,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: _buildInlineYearGrid(isDark, isMobile),
                )
              else ...[
                // Weekday Headers
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((day) {
                      final isWeekend = day == 'Sat' || day == 'Sun';
                      return Expanded(
                        child: Text(
                          day,
                          textAlign: TextAlign.center,
                          style: AppTheme.getFontStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isWeekend
                                ? const Color(0xFFE53935)
                                : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Calendar Grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: _buildCalendarGrid(isDark, isMobile),
                ),
              ],

              const Divider(height: 1, thickness: 1),

              // ─── ACTION BUTTONS ───
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: isMobile ? 8 : 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, _selectedDate),
                        icon: Icon(Icons.check_rounded, size: isMobile ? 15 : 18),
                        label: Text(
                          'Confirm Date',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.getFontStyle(
                            fontSize: isMobile ? 11 : 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: isMobile ? 6 : 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.isBottomSheet) {
      return bodyContent;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      child: bodyContent,
    );
  }

  Widget _buildPresetChip(String label, DateTime targetDate) {
    final isSelected = _isSameDay(_selectedDate, targetDate);
    return InkWell(
      onTap: () => _selectPreset(targetDate),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4AF37) : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4AF37) : Colors.white30,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F3814) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildInlineYearGrid(bool isDark, bool isMobile) {
    final currentYear = DateTime.now().year;

    return GridView.builder(
      controller: _yearScrollController,
      physics: const BouncingScrollPhysics(),
      itemCount: 251, // 1900 to 2150
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: isMobile ? 2.2 : 2.4,
      ),
      itemBuilder: (context, index) {
        final year = 1900 + index;
        final isSelected = year == _focusedMonth.year;
        final isCurrentYear = year == currentYear;

        return InkWell(
          onTap: () {
            setState(() {
              _focusedMonth = DateTime(year, _focusedMonth.month, 1);
              _isYearPickerOpen = false;
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor
                  : (isCurrentYear
                      ? (isDark ? AppTheme.primaryColor.withValues(alpha: 0.2) : const Color(0xFFE8F5E9))
                      : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : (isCurrentYear ? AppTheme.primaryColor : Colors.transparent),
                width: isSelected ? 1.5 : (isCurrentYear ? 1 : 0),
              ),
            ),
            child: Text(
              '$year',
              style: AppTheme.getFontStyle(
                fontSize: 13,
                fontWeight: isSelected || isCurrentYear ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white : const Color(0xFF1F2937)),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendarGrid(bool isDark, bool isMobile) {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday; // 1=Mon, 7=Sun
    final prevMonthDays = DateTime(_focusedMonth.year, _focusedMonth.month, 0).day;

    final leadingOffset = firstWeekday - 1; // Mon = 0
    final totalCells = ((leadingOffset + daysInMonth) / 7).ceil() * 7;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: totalCells,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: isMobile ? 3 : 4,
        crossAxisSpacing: isMobile ? 3 : 4,
        childAspectRatio: isMobile ? 1.15 : 1.15,
      ),
      itemBuilder: (context, index) {
        DateTime cellDate;
        bool isCurrentMonth = true;

        if (index < leadingOffset) {
          final day = prevMonthDays - (leadingOffset - index - 1);
          cellDate = DateTime(_focusedMonth.year, _focusedMonth.month - 1, day);
          isCurrentMonth = false;
        } else if (index >= leadingOffset + daysInMonth) {
          final day = index - (leadingOffset + daysInMonth) + 1;
          cellDate = DateTime(_focusedMonth.year, _focusedMonth.month + 1, day);
          isCurrentMonth = false;
        } else {
          final day = index - leadingOffset + 1;
          cellDate = DateTime(_focusedMonth.year, _focusedMonth.month, day);
        }

        final isSelected = _isSameDay(cellDate, _selectedDate);
        final isToday = _isToday(cellDate);

        final isBeforeFirst = widget.firstDate != null && cellDate.isBefore(widget.firstDate!);
        final isAfterLast = widget.lastDate != null && cellDate.isAfter(widget.lastDate!);
        final isDisabled = isBeforeFirst || isAfterLast;

        return InkWell(
          onTap: isDisabled
              ? null
              : () {
                  setState(() {
                    _selectedDate = cellDate;
                    if (!isCurrentMonth) {
                      _focusedMonth = DateTime(cellDate.year, cellDate.month, 1);
                    }
                  });
                },
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: isSelected
                  ? const LinearGradient(
                      colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected
                  ? AppTheme.primaryColor
                  : (isToday
                      ? (isDark ? AppTheme.primaryColor.withValues(alpha: 0.25) : const Color(0xFFE8F5E9))
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFD4AF37)
                    : (isToday ? AppTheme.primaryColor : Colors.transparent),
                width: isSelected ? 1.5 : (isToday ? 1.2 : 0),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${cellDate.day}',
                  style: AppTheme.getFontStyle(
                    fontSize: isMobile ? 12 : 13,
                    fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                    color: isDisabled
                        ? (isDark ? Colors.white24 : Colors.grey.shade300)
                        : (isSelected
                            ? Colors.white
                            : (!isCurrentMonth
                                ? (isDark ? Colors.white30 : Colors.grey.shade400)
                                : (isDark ? Colors.white : const Color(0xFF1F2937)))),
                  ),
                ),
                if (isToday && !isSelected)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A sleek text form field wrapper that displays selected date and launches
/// the Dribbble Date Picker on tap.
class DribbbleDatePickerField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime>? onDateSelected;

  const DribbbleDatePickerField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText = 'DD/MM/YYYY',
    this.firstDate,
    this.lastDate,
    this.onDateSelected,
  });

  Future<void> _openPicker(BuildContext context) async {
    DateTime initial = DateTime.now();
    if (controller.text.isNotEmpty) {
      final txt = controller.text.trim();
      try {
        if (txt.contains('/')) {
          final parts = txt.split('/');
          if (parts.length == 3) {
            initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } else if (txt.contains('-')) {
          initial = DateTime.parse(txt);
        }
      } catch (_) {}
    }

    final picked = await DribbbleDatePickerDialog.show(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      title: labelText,
    );

    if (picked != null) {
      final formatted = DateFormat('dd/MM/yyyy').format(picked);
      controller.text = formatted;
      if (onDateSelected != null) {
        onDateSelected!(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(12),
      child: IgnorePointer(
        child: TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: labelText,
            hintText: hintText,
            prefixIcon: Container(
              padding: const EdgeInsets.all(10),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: AppTheme.primaryColor,
                size: 22,
              ),
            ),
            suffixIcon: const Icon(
              Icons.arrow_drop_down_circle_outlined,
              color: Colors.grey,
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
