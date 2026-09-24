import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A Dribbble-inspired modern Time Picker featuring a Single Dynamic Keypad,
/// Auto-Advancing Digit Slots (HH : MM), and adaptive Mobile/Desktop layouts.
class DribbbleTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String title;
  final bool use24HourFormat;
  final bool isBottomSheet;

  const DribbbleTimePickerDialog({
    super.key,
    required this.initialTime,
    this.title = 'Select Time',
    this.use24HourFormat = false,
    this.isBottomSheet = false,
  });

  static Future<TimeOfDay?> show({
    required BuildContext context,
    TimeOfDay? initialTime,
    String title = 'Select Time',
    bool use24HourFormat = false,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 700;

    if (isMobile) {
      return showModalBottomSheet<TimeOfDay>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: DribbbleTimePickerDialog(
            initialTime: initialTime ?? TimeOfDay.now(),
            title: title,
            use24HourFormat: use24HourFormat,
            isBottomSheet: true,
          ),
        ),
      );
    }

    return showDialog<TimeOfDay>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => DribbbleTimePickerDialog(
        initialTime: initialTime ?? TimeOfDay.now(),
        title: title,
        use24HourFormat: use24HourFormat,
        isBottomSheet: false,
      ),
    );
  }

  @override
  State<DribbbleTimePickerDialog> createState() => _DribbbleTimePickerDialogState();
}

class _DribbbleTimePickerDialogState extends State<DribbbleTimePickerDialog> {
  // 4 Digit Slots: [0] = Hour Tens, [1] = Hour Units, [2] = Minute Tens, [3] = Minute Units
  late List<int> _digits;
  int _activeDigitIndex = 0; // 0..3
  late DayPeriod _selectedPeriod; // am or pm

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    _selectedPeriod = hour >= 12 ? DayPeriod.pm : DayPeriod.am;
    int hour12 = hour % 12 == 0 ? 12 : hour % 12;
    int minute = widget.initialTime.minute;

    _digits = [
      hour12 ~/ 10,
      hour12 % 10,
      minute ~/ 10,
      minute % 10,
    ];
  }

  TimeOfDay get _currentTimeOfDay {
    int hour12 = _digits[0] * 10 + _digits[1];
    if (hour12 == 0) hour12 = 12;
    if (hour12 > 12) hour12 = 12;

    int minute = _digits[2] * 10 + _digits[3];
    if (minute > 59) minute = 59;

    int hour24 = hour12 % 12;
    if (_selectedPeriod == DayPeriod.pm) {
      hour24 += 12;
    }
    return TimeOfDay(hour: hour24, minute: minute);
  }

  void _onNumpadPressed(int digit) {
    setState(() {
      if (_activeDigitIndex == 0) {
        // Typing 1st digit of Hour (Tens)
        if (digit > 1) {
          // If user types 2..9 -> automatically format as 0X and jump to Minute Tens (Index 2)
          _digits[0] = 0;
          _digits[1] = digit;
          _activeDigitIndex = 2;
        } else {
          _digits[0] = digit;
          _activeDigitIndex = 1;
        }
      } else if (_activeDigitIndex == 1) {
        // Typing 2nd digit of Hour (Units)
        int h = _digits[0] * 10 + digit;
        if (h > 12) h = 12;
        if (h == 0) h = 12;
        _digits[0] = h ~/ 10;
        _digits[1] = h % 10;
        _activeDigitIndex = 2; // Auto-shift to Minute Tens
      } else if (_activeDigitIndex == 2) {
        // Typing 1st digit of Minute (Tens, 0..5)
        if (digit > 5) {
          // If user types 6..9 -> format as 0X and jump to Minute Units (Index 3)
          _digits[2] = 0;
          _digits[3] = digit;
          _activeDigitIndex = 3;
        } else {
          _digits[2] = digit;
          _activeDigitIndex = 3; // Auto-shift to Minute Units
        }
      } else if (_activeDigitIndex == 3) {
        // Typing 2nd digit of Minute (Units, 0..9)
        _digits[3] = digit;
      }
    });
  }

  void _onBackspacePressed() {
    setState(() {
      _digits[_activeDigitIndex] = 0;
      if (_activeDigitIndex > 0) {
        _activeDigitIndex--;
      }
    });
  }

  void _onClearPressed() {
    final now = TimeOfDay.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    setState(() {
      _digits = [
        hour12 ~/ 10,
        hour12 % 10,
        now.minute ~/ 10,
        now.minute % 10,
      ];
      _selectedPeriod = now.hour >= 12 ? DayPeriod.pm : DayPeriod.am;
      _activeDigitIndex = 0;
    });
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
        width: isMobile ? double.infinity : 360,
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
                  horizontal: isMobile ? 14 : 18,
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
                        const SizedBox(width: 6),
                        // AM / PM Segmented Switcher
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildAmPmToggle('AM', DayPeriod.am),
                              _buildAmPmToggle('PM', DayPeriod.pm),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ─── 4 AUTO-ADVANCING DIGIT SLOTS (HH : MM) ───
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Hour Box (Slots 0 & 1)
                          _buildDigitSlotGroup('HOUR', [0, 1], isDark),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              ':',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                          ),
                          // Minute Box (Slots 2 & 3)
                          _buildDigitSlotGroup('MINUTE', [2, 3], isDark),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ─── SINGLE DYNAMIC NUMERIC KEYPAD (0-9) ───
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: isMobile ? 10 : 12,
                ),
                child: _buildSingleKeypad(isDark, isMobile),
              ),

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
                        onPressed: () => Navigator.pop(context, _currentTimeOfDay),
                        icon: Icon(Icons.check_rounded, size: isMobile ? 15 : 18),
                        label: Text(
                          'Confirm Time',
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

  Widget _buildDigitSlotGroup(String label, List<int> slotIndices, bool isDark) {
    return Column(
      children: [
        Row(
          children: slotIndices.map((idx) => _buildSingleDigitSlot(idx, isDark)).toList(),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildSingleDigitSlot(int slotIndex, bool isDark) {
    final isActive = _activeDigitIndex == slotIndex;
    final digitValue = _digits[slotIndex];

    return GestureDetector(
      onTap: () {
        setState(() {
          _activeDigitIndex = slotIndex;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        width: 38,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0xFFD4AF37) : Colors.white30,
            width: isActive ? 2.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Text(
          '$digitValue',
          style: AppTheme.getFontStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isActive ? const Color(0xFF0F3814) : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleKeypad(bool isDark, bool isMobile) {
    final keypadItems = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      'C', '0', 'BACK'
    ];

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 12,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: isMobile ? 6 : 6,
        crossAxisSpacing: isMobile ? 8 : 10,
        childAspectRatio: isMobile ? 2.2 : 2.4,
      ),
      itemBuilder: (context, index) {
        final key = keypadItems[index];

        if (key == 'BACK') {
          return InkWell(
            onTap: _onBackspacePressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? Colors.red.withValues(alpha: 0.15) : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.backspace_outlined,
                color: Color(0xFFE53935),
                size: 20,
              ),
            ),
          );
        }

        if (key == 'C') {
          return InkWell(
            onTap: _onClearPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'C',
                style: AppTheme.getFontStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ),
          );
        }

        final digit = int.parse(key);
        return InkWell(
          onTap: () => _onNumpadPressed(digit),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            child: Text(
              key,
              style: AppTheme.getFontStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1F2937),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAmPmToggle(String label, DayPeriod period) {
    final isSelected = _selectedPeriod == period;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isSelected ? const Color(0xFF0F3814) : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// A sleek text form field wrapper that displays selected time and launches
/// the Dribbble Time Picker on tap.
class DribbbleTimePickerField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final ValueChanged<TimeOfDay>? onTimeSelected;
  final bool output24HourFormat;

  const DribbbleTimePickerField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText = '09:00 AM',
    this.onTimeSelected,
    this.output24HourFormat = false,
  });

  Future<void> _openPicker(BuildContext context) async {
    TimeOfDay initial = TimeOfDay.now();

    if (controller.text.isNotEmpty) {
      try {
        final txt = controller.text.trim();
        final parts = txt.split(':');
        if (parts.length >= 2) {
          int h = int.parse(parts[0]);
          final minuteParts = parts[1].trim().split(' ');
          int m = int.parse(minuteParts[0]);
          final isPm = txt.toLowerCase().contains('pm');
          final isAm = txt.toLowerCase().contains('am');

          if (isPm && h < 12) h += 12;
          if (isAm && h == 12) h = 0;
          initial = TimeOfDay(hour: h, minute: m);
        }
      } catch (_) {}
    }

    final picked = await DribbbleTimePickerDialog.show(
      context: context,
      initialTime: initial,
      title: labelText,
    );

    if (picked != null) {
      String formatted;
      if (output24HourFormat) {
        final h = picked.hour.toString().padLeft(2, '0');
        final m = picked.minute.toString().padLeft(2, '0');
        formatted = '$h:$m';
      } else {
        final periodStr = picked.period == DayPeriod.am ? 'AM' : 'PM';
        int hour12 = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        final h = hour12.toString().padLeft(2, '0');
        final m = picked.minute.toString().padLeft(2, '0');
        formatted = '$h:$m $periodStr';
      }

      controller.text = formatted;
      if (onTimeSelected != null) {
        onTimeSelected!(picked);
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
                Icons.access_time_filled_rounded,
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
