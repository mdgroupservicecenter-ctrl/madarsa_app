import 'package:flutter/material.dart';
import '../../data/algorithm/seating_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/urdu_number_helper.dart';

import 'package:flutter/gestures.dart';

class SeatingGridWidget extends StatefulWidget {
  final int rows;
  final int columns;
  final List<SeatAssignment> assignments;
  final List<String> warnings;
  final String primaryMethod;
  final int totalStudents;
  final int placedCount;
  final int tier1Count;
  final int tier2Count;
  final int tier3Count;

  const SeatingGridWidget({
    super.key,
    required this.rows,
    required this.columns,
    required this.assignments,
    this.warnings = const [],
    this.primaryMethod = 'ANTI_ADJACENCY',
    this.totalStudents = 0,
    this.placedCount = 0,
    this.tier1Count = 0,
    this.tier2Count = 0,
    this.tier3Count = 0,
  });

  static const _pastelBookColors = [
    Color(0xFFE0F2F1), // Soft Teal
    Color(0xFFF3E5F5), // Soft Purple / Pink
    Color(0xFFE3F2FD), // Soft Blue
    Color(0xFFE8F5E9), // Soft Green
    Color(0xFFFFF8E1), // Soft Amber / Gold
    Color(0xFFFFEBEE), // Soft Coral
    Color(0xFFF3E5F5), // Soft Lavender
    Color(0xFFEFEBE9), // Soft Warm Grey
  ];

  static const _darkBookColors = [
    Color(0xFF004D40), // Dark Teal
    Color(0xFF4A148C), // Dark Purple
    Color(0xFF0D47A1), // Dark Blue
    Color(0xFF1B5E20), // Dark Green
    Color(0xFFF57F17), // Dark Amber
    Color(0xFFB71C1C), // Dark Red
    Color(0xFF311B92), // Dark Indigo
    Color(0xFF3E2723), // Dark Brown
  ];

  static const _borderBookColors = [
    Color(0xFF00796B),
    Color(0xFF7B1FA2),
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFFF57C00),
    Color(0xFFD32F2F),
    Color(0xFF512DA8),
    Color(0xFF5D4037),
  ];

  @override
  State<SeatingGridWidget> createState() => _SeatingGridWidgetState();
}

class _SeatingGridWidgetState extends State<SeatingGridWidget> {
  final ScrollController _horizController = ScrollController();
  final ScrollController _vertController = ScrollController();
  double _zoomLevel = 1.0;

  @override
  void dispose() {
    _horizController.dispose();
    _vertController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur' || AppTheme.isUrdu;

    final gridMap = <String, SeatAssignment>{};
    final bookColorMap = <String, Color>{};
    final bookBorderMap = <String, Color>{};
    int colorIdx = 0;

    for (final a in widget.assignments) {
      gridMap['${a.seat.row}:${a.seat.col}'] = a;
      final key = a.student.bookId.isNotEmpty ? a.student.bookId : a.student.classId;
      if (!bookColorMap.containsKey(key)) {
        bookColorMap[key] = isDark
            ? SeatingGridWidget._darkBookColors[colorIdx % SeatingGridWidget._darkBookColors.length]
            : SeatingGridWidget._pastelBookColors[colorIdx % SeatingGridWidget._pastelBookColors.length];
        bookBorderMap[key] = SeatingGridWidget._borderBookColors[colorIdx % SeatingGridWidget._borderBookColors.length];
        colorIdx++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── STATS & METHOD BADGES BAR ───
        _buildStatsBar(isDark, isUrdu),
        const SizedBox(height: 12),

        // ─── WARNINGS (IF ANY) ───
        if (widget.warnings.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 100),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final w in widget.warnings)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: w.contains('CRITICAL')
                            ? AppTheme.errorColor.withValues(alpha: isDark ? 0.3 : 0.15)
                            : AppTheme.warningColor.withValues(alpha: isDark ? 0.3 : 0.15),
                        border: Border.all(
                          color: w.contains('CRITICAL')
                              ? AppTheme.errorColor.withValues(alpha: 0.5)
                              : AppTheme.warningColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            w.contains('CRITICAL') ? Icons.error_rounded : Icons.warning_amber_rounded,
                            size: 16,
                            color: w.contains('CRITICAL') ? AppTheme.errorColor : AppTheme.warningColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isUrdu ? UrduNumberHelper.toUrduDigits(w) : w,
                              style: AppTheme.getFontStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ─── SEATING GRID DISPLAY WITH DUAL HORIZONTAL & VERTICAL SCROLLBARS & MOUSE DRAG ───
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final headerWidth = 34.0;
              final gap = 8.0;
              final availableWidthForCells = constraints.maxWidth - headerWidth - 24;
              final baseCellSize = (availableWidthForCells / widget.columns - gap).clamp(170.0, 260.0);
              final dynamicCellSize = baseCellSize * _zoomLevel;

              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                child: Scrollbar(
                  controller: _horizController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: Scrollbar(
                    controller: _vertController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    notificationPredicate: (notif) => notif.depth == 1,
                    child: SingleChildScrollView(
                      controller: _horizController,
                      scrollDirection: Axis.horizontal,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SingleChildScrollView(
                        controller: _vertController,
                        scrollDirection: Axis.vertical,
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24, right: 24),
                          child: _buildGrid(gridMap, bookColorMap, bookBorderMap, isDark, isUrdu, dynamicCellSize, gap),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsBar(bool isDark, bool isUrdu) {
    String fmt(dynamic n) => isUrdu ? UrduNumberHelper.toUrduDigits(n) : '$n';
    final activePlaced = widget.placedCount > 0 ? widget.placedCount : widget.assignments.length;
    final activeTotal = widget.totalStudents > 0 ? widget.totalStudents : widget.assignments.length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          // Total Chip
          _buildStatPill('Total', fmt(activeTotal), Colors.teal, isDark, Icons.people_alt_rounded),
          const SizedBox(width: 8),
          // Placed Chip
          _buildStatPill('Placed', fmt(activePlaced), AppTheme.primaryColor, isDark, Icons.check_circle_rounded),
          const SizedBox(width: 8),
          // Anti-Adj Chip
          _buildStatPill('Anti-Adj', fmt(widget.tier1Count > 0 ? widget.tier1Count : activePlaced), const Color(0xFF0F3814), isDark, Icons.verified_rounded),
          if (widget.tier2Count > 0) ...[
            const SizedBox(width: 8),
            _buildStatPill('Merit', fmt(widget.tier2Count), AppTheme.warningColor, isDark, Icons.star_rounded),
          ],
          if (widget.tier3Count > 0) ...[
            const SizedBox(width: 8),
            _buildStatPill('Random', fmt(widget.tier3Count), AppTheme.errorColor, isDark, Icons.shuffle_rounded),
          ],
          const SizedBox(width: 14),
          // ANTI-ADJACENCY Method Badge Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F3814), Color(0xFF1B5E20)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFD4AF37)),
                const SizedBox(width: 6),
                Text(
                  widget.primaryMethod.replaceAll('_', ' '),
                  style: AppTheme.getFontStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, Color color, bool isDark, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: AppTheme.getFontStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: AppTheme.getFontStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    Map<String, SeatAssignment> gridMap,
    Map<String, Color> bookColorMap,
    Map<String, Color> bookBorderMap,
    bool isDark,
    bool isUrdu,
    double cellSize,
    double gap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Column Headers (C1, C2, C3...) ───
        Row(
          children: [
            const SizedBox(width: 34, height: 26),
            for (int c = 0; c < widget.columns; c++)
              Container(
                width: cellSize,
                margin: EdgeInsets.only(right: gap),
                alignment: Alignment.center,
                child: Text(
                  'C${isUrdu ? UrduNumberHelper.toUrduDigits(c + 1) : c + 1}',
                  style: AppTheme.getFontStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.grey.shade700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),

        // ─── Row Cells (R1, R2, R3...) ───
        for (int r = 0; r < widget.rows; r++)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    'R${isUrdu ? UrduNumberHelper.toUrduDigits(r + 1) : r + 1}',
                    style: AppTheme.getFontStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : Colors.grey.shade700,
                    ),
                  ),
                ),
                for (int c = 0; c < widget.columns; c++)
                  Container(
                    width: cellSize,
                    height: 124,
                    margin: EdgeInsets.only(right: gap),
                    child: _buildCell(r, c, gridMap, bookColorMap, bookBorderMap, isDark, isUrdu),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(
    int row,
    int col,
    Map<String, SeatAssignment> gridMap,
    Map<String, Color> bookColorMap,
    Map<String, Color> bookBorderMap,
    bool isDark,
    bool isUrdu,
  ) {
    final key = '$row:$col';
    final assignment = gridMap[key];
    final seatNumRaw = row * widget.columns + col + 1;
    final seatNumDisplay = isUrdu ? UrduNumberHelper.toUrduDigits(seatNumRaw) : '$seatNumRaw';

    if (assignment == null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade100,
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          seatNumDisplay,
          style: AppTheme.getFontStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white24 : Colors.grey.shade400,
          ),
        ),
      );
    }

    final bookKey = assignment.student.bookId.isNotEmpty ? assignment.student.bookId : assignment.student.classId;
    final bgColor = bookColorMap[bookKey] ?? (isDark ? const Color(0xFF1E1E2C) : const Color(0xFFE8F5E9));
    final borderColor = bookBorderMap[bookKey] ?? AppTheme.primaryColor;

    // GR No (Registration Number)
    final grNoRaw = assignment.student.registrationNumber;
    final grDisplay = isUrdu ? UrduNumberHelper.toUrduDigits(grNoRaw) : grNoRaw;

    // Roll No
    final rollNoRaw = (assignment.student.rollNumber != null && assignment.student.rollNumber!.trim().isNotEmpty)
        ? assignment.student.rollNumber!.trim()
        : '';
    final rollDisplay = (rollNoRaw.isNotEmpty && isUrdu)
        ? UrduNumberHelper.toUrduDigits(rollNoRaw)
        : rollNoRaw;

    final tooltipText =
        'Name: ${assignment.student.studentName}\nGR No: $grDisplay${rollDisplay.isNotEmpty ? '\nRoll No: $rollDisplay' : ''}\nBook: ${assignment.student.bookName}\nClass: ${assignment.student.className}\nMethod: ${assignment.method}';

    return Tooltip(
      message: tooltipText,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3814),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
      textStyle: AppTheme.getFontStyle(fontSize: 11.5, color: Colors.white, height: 1.4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: bgColor,
          border: Border.all(color: borderColor.withValues(alpha: 0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: borderColor.withValues(alpha: 0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Header Bar (Seat Badge Left & Roll No Right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Seat Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: borderColor.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#$seatNumDisplay',
                    style: AppTheme.getFontStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : borderColor,
                    ),
                  ),
                ),

                // Roll No Tag (If available)
                if (rollDisplay.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF57C00).withValues(alpha: isDark ? 0.35 : 0.15),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.5), width: 0.8),
                    ),
                    child: Text(
                      'Roll: $rollDisplay',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.getFontStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFFE65100),
                      ),
                    ),
                  ),
              ],
            ),

            // Row 2: Student's Full Name (Student Name + Father Name + Surname)
            Text(
              assignment.student.studentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.getFontStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF111827),
              ),
            ),

            // Row 3: GR No Tag (Placed below student name)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.3 : 0.12),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Text(
                'GR No: $grDisplay',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.getFontStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppTheme.primaryColor,
                ),
              ),
            ),

            // Row 4: Book & Class Name
            Text(
              '${assignment.student.bookName} (${assignment.student.className})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.getFontStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
