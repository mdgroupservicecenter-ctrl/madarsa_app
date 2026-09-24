import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/services/clock_theme_service.dart';

/// Hardware-accelerated GPU canvas painter for authentic Digital Clock designs.
/// Replicates the exact physical brass squircle bezel with 4 corner screws,
/// authentic 7-segment LED displays with unlit segment ghosting,
/// green leaf emblem, status icons, and MD GROUP typography.
class DigitalClockPainter extends CustomPainter {
  final DateTime dateTime;
  final bool isDark;
  final ClockDesign design;
  final bool showSeconds;
  final bool is24Hour;

  const DigitalClockPainter({
    required this.dateTime,
    required this.isDark,
    required this.design,
    this.showSeconds = false,
    this.is24Hour = false,
  });

  // 7-segment truth table for digits 0-9: [A, B, C, D, E, F, G]
  static const Map<int, List<bool>> _digitSegments = {
    0: [true, true, true, true, true, true, false],
    1: [false, true, true, false, false, false, false],
    2: [true, true, false, true, true, false, true],
    3: [true, true, true, true, false, false, true],
    4: [false, true, true, false, false, true, true],
    5: [true, false, true, true, false, true, true],
    6: [true, false, true, true, true, true, true],
    7: [true, true, true, false, false, false, false],
    8: [true, true, true, true, true, true, true],
    9: [true, true, true, true, false, true, true],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width, size.height) / 140.0;

    switch (design.id) {
      case 'digital_cyan_weather_schedule':
      case 'digital_white_led_status':
        _paintCyanDualDashboard(canvas, size, scale);
        break;
      case 'digital_amber_nixie_tube':
        _paintAmberNixieTube(canvas, size, scale);
        break;
      case 'digital_emerald_gold_lcd':
        _paintEmeraldGoldLcd(canvas, size, scale);
        break;
      case 'digital_crimson_carbon_matrix':
        _paintCrimsonCarbonMatrix(canvas, size, scale);
        break;
      case 'digital_monochrome_bauhaus':
        _paintMonochromeBauhaus(canvas, size, scale);
        break;
      case 'digital_cyber_violet_neon':
        _paintCyberVioletNeon(canvas, size, scale);
        break;
      case 'digital_ice_blue_crystal':
        _paintIceBlueCrystal(canvas, size, scale);
        break;
      case 'digital_dot_matrix_white':
      case 'digital_red_led_leaf_md':
      default:
        _paintDotMatrixWhite(canvas, size, scale);
        break;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // COMMON: CUSTOMIZABLE SQUIRCLE BEZEL WITH 4 CORNER SCREWS
  // ══════════════════════════════════════════════════════════════
  void _paintSquircleBezelWithScrews(
    Canvas canvas,
    Size size,
    double scale, {
    List<Color>? bezelColors,
    Color? rimHighlightColor,
    Color? grooveColor,
    Color dialBg = const Color(0xFF0D0E11),
    Color dialBgEnd = const Color(0xFF07080A),
    Color? innerShadowColor,
    List<Color>? screwColors,
    Color? slotColor,
  }) {
    final outerRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final outerRadius = 20.0 * scale;
    final outerRRect = RRect.fromRectAndRadius(outerRect, Radius.circular(outerRadius));

    final effectiveBezelColors = bezelColors ??
        const [
          Color(0xFFEBD08B),
          Color(0xFFD4AF37),
          Color(0xFFA57D2C),
          Color(0xFF6E4D14),
          Color(0xFFB58E3A),
        ];

    // 1. Outer Bezel Gradient
    final bezelPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: effectiveBezelColors,
        stops: effectiveBezelColors.length == 5 ? const [0.0, 0.25, 0.6, 0.85, 1.0] : null,
      ).createShader(outerRect);
    canvas.drawRRect(outerRRect, bezelPaint);

    // 2. Bezel Highlights & Edge Rim
    final rimHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale
      ..color = rimHighlightColor ?? const Color(0xFFFFF2BD).withAlpha(160);
    canvas.drawRRect(outerRRect.deflate(0.5 * scale), rimHighlight);

    // 3. Inner Dark Groove
    final grooveRect = outerRect.deflate(5.0 * scale);
    final grooveRRect = RRect.fromRectAndRadius(grooveRect, Radius.circular(16.0 * scale));
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * scale
      ..color = grooveColor ?? const Color(0xFF281C09);
    canvas.drawRRect(grooveRRect, groovePaint);

    // 4. Dial Face (Matte obsidian black with subtle radial gradient)
    final dialRect = outerRect.deflate(8.0 * scale);
    final dialRRect = RRect.fromRectAndRadius(dialRect, Radius.circular(13.5 * scale));
    final dialPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [dialBg, dialBgEnd],
      ).createShader(dialRect);
    canvas.drawRRect(dialRRect, dialPaint);

    // 5. Inner Dial Drop Shadow
    final innerShadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..color = innerShadowColor ?? Colors.black.withAlpha(140);
    canvas.drawRRect(dialRRect.deflate(0.8 * scale), innerShadowPaint);

    // 6. 4 Realistic Corner Screws
    final screwInset = 11.5 * scale;
    final screwRadius = 2.8 * scale;
    final screwCenters = [
      Offset(screwInset, screwInset),
      Offset(size.width - screwInset, screwInset),
      Offset(screwInset, size.height - screwInset),
      Offset(size.width - screwInset, size.height - screwInset),
    ];

    for (int i = 0; i < screwCenters.length; i++) {
      final sc = screwCenters[i];
      _paintCornerScrew(
        canvas,
        sc,
        screwRadius,
        scale,
        angle: (i * 40.0 + 35.0) * pi / 180.0,
        screwColors: screwColors,
        slotColor: slotColor,
      );
    }
  }

  void _paintBrassBezelWithScrews(
    Canvas canvas,
    Size size,
    double scale, {
    Color dialBg = const Color(0xFF0D0E11),
    Color dialBgEnd = const Color(0xFF07080A),
  }) {
    _paintSquircleBezelWithScrews(
      canvas,
      size,
      scale,
      dialBg: dialBg,
      dialBgEnd: dialBgEnd,
    );
  }

  void _paintCornerScrew(
    Canvas canvas,
    Offset center,
    double radius,
    double scale, {
    double angle = 0.6,
    List<Color>? screwColors,
    Color? slotColor,
  }) {
    final effectiveScrewColors = screwColors ??
        const [
          Color(0xFFEBD292),
          Color(0xFF99752C),
          Color(0xFF5E4010),
        ];

    // Screw Bezel Ring
    final headRect = Rect.fromCircle(center: center, radius: radius);
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: effectiveScrewColors,
      ).createShader(headRect);
    canvas.drawCircle(center, radius, headPaint);

    // Slot Indentation
    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85 * scale
      ..strokeCap = StrokeCap.round
      ..color = slotColor ?? const Color(0xFF281C06);

    final dx = cos(angle) * (radius * 0.7);
    final dy = sin(angle) * (radius * 0.7);
    canvas.drawLine(center - Offset(dx, dy), center + Offset(dx, dy), slotPaint);

    // Screw Rim Highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * scale;
    canvas.drawArc(headRect, -pi * 0.75, pi * 0.5, false, highlightPaint);
  }


  // ══════════════════════════════════════════════════════════════
  // COMMON 7-SEGMENT TIME ROW RENDERER (HH:MM + GHOSTING)
  // ══════════════════════════════════════════════════════════════
  void _paint7SegmentRow(
    Canvas canvas,
    Offset center,
    double scale, {
    required int hour,
    required int minute,
    required Color litColor,
    required Color unlitColor,
    required double digitWidth,
    required double digitHeight,
    required double thickness,
    required double digitGap,
    required double colonGap,
  }) {
    final d1 = hour ~/ 10;
    final d2 = hour % 10;
    final d3 = minute ~/ 10;
    final d4 = minute % 10;

    final totalW = (digitWidth * 4) + (digitGap * 2) + colonGap;
    var startX = center.dx - totalW / 2;
    final topY = center.dy - digitHeight / 2;

    // Digit 1 (Hour tens)
    _paintSingle7SegmentDigit(
      canvas,
      Rect.fromLTWH(startX, topY, digitWidth, digitHeight),
      d1,
      litColor,
      unlitColor,
      thickness,
    );
    startX += digitWidth + digitGap;

    // Digit 2 (Hour units)
    _paintSingle7SegmentDigit(
      canvas,
      Rect.fromLTWH(startX, topY, digitWidth, digitHeight),
      d2,
      litColor,
      unlitColor,
      thickness,
    );
    startX += digitWidth;

    // Colon Separator
    final colonCenterX = startX + colonGap / 2;
    final dotSize = thickness * 0.95;
    final colonPaint = Paint()
      ..color = litColor
      ..style = PaintingStyle.fill;

    // Top dot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(colonCenterX, center.dy - digitHeight * 0.2),
          width: dotSize,
          height: dotSize,
        ),
        Radius.circular(dotSize * 0.25),
      ),
      colonPaint,
    );
    // Bottom dot
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(colonCenterX, center.dy + digitHeight * 0.2),
          width: dotSize,
          height: dotSize,
        ),
        Radius.circular(dotSize * 0.25),
      ),
      colonPaint,
    );

    startX += colonGap;

    // Digit 3 (Minute tens)
    _paintSingle7SegmentDigit(
      canvas,
      Rect.fromLTWH(startX, topY, digitWidth, digitHeight),
      d3,
      litColor,
      unlitColor,
      thickness,
    );
    startX += digitWidth + digitGap;

    // Digit 4 (Minute units)
    _paintSingle7SegmentDigit(
      canvas,
      Rect.fromLTWH(startX, topY, digitWidth, digitHeight),
      d4,
      litColor,
      unlitColor,
      thickness,
    );
  }

  /// Draws a single 7-segment digit with authentic chamfered segment geometries
  void _paintSingle7SegmentDigit(
    Canvas canvas,
    Rect bounds,
    int digit,
    Color litColor,
    Color unlitColor,
    double t,
  ) {
    final states = _digitSegments[digit] ?? [false, false, false, false, false, false, false];

    final x = bounds.left;
    final y = bounds.top;
    final w = bounds.width;
    final h = bounds.height;
    final halfH = h / 2;

    // Segment A (Top horizontal)
    _drawHorizontalSegment(canvas, x + t * 0.5, y, w - t, t, states[0] ? litColor : unlitColor, states[0]);

    // Segment B (Top-Right vertical)
    _drawVerticalSegment(canvas, x + w - t, y + t * 0.5, t, halfH - t * 0.5, states[1] ? litColor : unlitColor, states[1]);

    // Segment C (Bottom-Right vertical)
    _drawVerticalSegment(canvas, x + w - t, y + halfH, t, halfH - t * 0.5, states[2] ? litColor : unlitColor, states[2]);

    // Segment D (Bottom horizontal)
    _drawHorizontalSegment(canvas, x + t * 0.5, y + h - t, w - t, t, states[3] ? litColor : unlitColor, states[3]);

    // Segment E (Bottom-Left vertical)
    _drawVerticalSegment(canvas, x, y + halfH, t, halfH - t * 0.5, states[4] ? litColor : unlitColor, states[4]);

    // Segment F (Top-Left vertical)
    _drawVerticalSegment(canvas, x, y + t * 0.5, t, halfH - t * 0.5, states[5] ? litColor : unlitColor, states[5]);

    // Segment G (Middle horizontal)
    _drawHorizontalSegment(canvas, x + t * 0.5, y + halfH - t * 0.5, w - t, t, states[6] ? litColor : unlitColor, states[6]);
  }

  void _drawHorizontalSegment(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    Color color,
    bool isLit,
  ) {
    final p = Path();
    final cap = h * 0.45;
    p.moveTo(x + cap, y);
    p.lineTo(x + w - cap, y);
    p.lineTo(x + w, y + h * 0.5);
    p.lineTo(x + w - cap, y + h);
    p.lineTo(x + cap, y + h);
    p.lineTo(x, y + h * 0.5);
    p.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(p, paint);

    if (isLit) {
      final glowPaint = Paint()
        ..color = color.withAlpha(50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);
      canvas.drawPath(p, glowPaint);
    }
  }

  void _drawVerticalSegment(
    Canvas canvas,
    double x,
    double y,
    double w,
    double h,
    Color color,
    bool isLit,
  ) {
    final p = Path();
    final cap = w * 0.45;
    p.moveTo(x + w * 0.5, y);
    p.lineTo(x + w, y + cap);
    p.lineTo(x + w, y + h - cap);
    p.lineTo(x + w * 0.5, y + h);
    p.lineTo(x, y + h - cap);
    p.lineTo(x, y + cap);
    p.close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(p, paint);

    if (isLit) {
      final glowPaint = Paint()
        ..color = color.withAlpha(50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);
      canvas.drawPath(p, glowPaint);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // OTHER CURATED DIGITAL DESIGNS
  // ══════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════
  // WATCH 1: SQUARE PIXEL WHITE LED (media_1790015376297.png)
  // ══════════════════════════════════════════════════════════════
  void _paintDotMatrixWhite(Canvas canvas, Size size, double scale) {
    _paintBrassBezelWithScrews(
      canvas,
      size,
      scale,
      dialBg: const Color(0xFF101317),
      dialBgEnd: const Color(0xFF07090C),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    _paintSquarePixelDigitRow(
      canvas,
      Offset(center.dx, size.height * 0.50),
      scale,
      hour: hour,
      minute: minute,
    );
  }

  void _paintSquarePixelDigitRow(
    Canvas canvas,
    Offset center,
    double scale, {
    required int hour,
    required int minute,
  }) {
    final d1 = hour ~/ 10;
    final d2 = hour % 10;
    final d3 = minute ~/ 10;
    final d4 = minute % 10;

    // Authentic tile metrics matching media_1790015376297.png - enlarged & centered
    final tileSize = 4.2 * scale;
    final tileStep = 5.2 * scale; // gap = 1.0 * scale
    final digitWidth = 3 * tileStep + tileSize; // 19.8 * scale
    final digitHeight = 6 * tileStep + tileSize; // 35.4 * scale
    final digitGap = 3.5 * scale;
    final colonWidth = 7.5 * scale;

    final totalWidth = 4 * digitWidth + 2 * digitGap + colonWidth;
    double currentX = center.dx - totalWidth / 2;
    final startY = center.dy - digitHeight / 2;

    // Digit 1 (Hour tens)
    _paintSingleSquarePixelDigit(canvas, Offset(currentX, startY), d1, tileSize, tileStep, scale);
    currentX += digitWidth + digitGap;

    // Digit 2 (Hour units)
    _paintSingleSquarePixelDigit(canvas, Offset(currentX, startY), d2, tileSize, tileStep, scale);
    currentX += digitWidth;

    // Colon ':'
    final colonCenterX = currentX + colonWidth / 2;
    final colonPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final colonRRectTop = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(colonCenterX, startY + 2 * tileStep + tileSize / 2),
        width: tileSize,
        height: tileSize,
      ),
      Radius.circular(0.9 * scale),
    );
    final colonRRectBottom = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(colonCenterX, startY + 4 * tileStep + tileSize / 2),
        width: tileSize,
        height: tileSize,
      ),
      Radius.circular(0.9 * scale),
    );
    canvas.drawRRect(colonRRectTop, colonPaint);
    canvas.drawRRect(colonRRectBottom, colonPaint);
    currentX += colonWidth;

    // Digit 3 (Minute tens)
    _paintSingleSquarePixelDigit(canvas, Offset(currentX, startY), d3, tileSize, tileStep, scale);
    currentX += digitWidth + digitGap;

    // Digit 4 (Minute units)
    _paintSingleSquarePixelDigit(canvas, Offset(currentX, startY), d4, tileSize, tileStep, scale);
  }

  void _paintSingleSquarePixelDigit(
    Canvas canvas,
    Offset origin,
    int digit,
    double tileSize,
    double tileStep,
    double scale,
  ) {
    final states = _digitSegments[digit] ?? [false, false, false, false, false, false, false];

    final tilePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final bevelPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.45 * scale;

    void drawTile(int col, int row) {
      final rect = Rect.fromLTWH(
        origin.dx + col * tileStep,
        origin.dy + row * tileStep,
        tileSize,
        tileSize,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(0.9 * scale));
      canvas.drawRRect(rrect, tilePaint);
      canvas.drawRRect(rrect, bevelPaint);
    }

    // Seg A (top): col 1, 2, row 0
    if (states[0]) {
      drawTile(1, 0);
      drawTile(2, 0);
    }
    // Seg B (top-right): col 3, row 1, 2
    if (states[1]) {
      drawTile(3, 1);
      drawTile(3, 2);
    }
    // Seg C (bottom-right): col 3, row 4, 5
    if (states[2]) {
      drawTile(3, 4);
      drawTile(3, 5);
    }
    // Seg D (bottom): col 1, 2, row 6
    if (states[3]) {
      drawTile(1, 6);
      drawTile(2, 6);
    }
    // Seg E (bottom-left): col 0, row 4, 5
    if (states[4]) {
      drawTile(0, 4);
      drawTile(0, 5);
    }
    // Seg F (top-left): col 0, row 1, 2
    if (states[5]) {
      drawTile(0, 1);
      drawTile(0, 2);
    }
    // Seg G (middle): col 1, 2, row 3
    if (states[6]) {
      drawTile(1, 3);
      drawTile(2, 3);
    }
  }

  // ══════════════════════════════════════════════════════════════
  // WATCH 2: CYAN DUAL DASHBOARD (media_1790015376317.png)
  // ══════════════════════════════════════════════════════════════
  // 2. CYAN GLOW LED (media_1790015376317.png)
  // "watch me sirf time show karna chahiye, date wagera kuchh bhi show nahi karna chahiye."
  // - Top: Small glowing cyan leaf emblem
  // - Center: Glowing Cyan 7-Segment LED Actual Time (HH:MM) - Centered at 0.50
  // - Bottom: Authentic MD Logo Emblem
  // - All secondary times (19:30 | 12:00), dividers, weather removed!
  // ══════════════════════════════════════════════════════════════
  void _paintCyanDualDashboard(Canvas canvas, Size size, double scale) {
    _paintBrassBezelWithScrews(
      canvas,
      size,
      scale,
      dialBg: const Color(0xFF09141B),
      dialBgEnd: const Color(0xFF03080C),
    );

    final center = Offset(size.width / 2, size.height / 2);

    // 1. Top Small Cyan Leaf (media_1790015376317.png)
    _paintSmallCyanLeaf(canvas, Offset(center.dx, size.height * 0.17), scale);

    // 2. Main Glowing Cyan Time (HH:MM) - Centered & Prominent at 0.50
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    _paint7SegmentRow(
      canvas,
      Offset(center.dx, size.height * 0.50),
      scale,
      hour: hour,
      minute: minute,
      litColor: const Color(0xFF00F0FF),
      unlitColor: const Color(0x1500E5FF),
      digitWidth: 20.0 * scale,
      digitHeight: 38.0 * scale,
      thickness: 4.2 * scale,
      digitGap: 3.5 * scale,
      colonGap: 7.0 * scale,
    );

    // 3. Bottom Section:
    // Authentic MD Logo is rendered here via DigitalClockFace overlay!
    // No dates, no secondary numbers, no weather icons. Sirf actual time!
  }

  void _paintSmallCyanLeaf(Canvas canvas, Offset center, double scale) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.35); // subtle slant matching image

    final w = 9.0 * scale;
    final h = 6.5 * scale;

    final leafPath = Path();
    leafPath.moveTo(-w * 0.5, 0);
    leafPath.cubicTo(-w * 0.2, -h * 0.6, w * 0.3, -h * 0.5, w * 0.5, 0);
    leafPath.cubicTo(w * 0.3, h * 0.5, -w * 0.2, h * 0.6, -w * 0.5, 0);
    leafPath.close();

    final fillPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * scale;

    canvas.drawPath(leafPath, fillPaint);
    canvas.drawPath(leafPath, strokePaint);

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // 3. NIXIE GLOW AMBER (Vintage Glass Tubes & Curved Wire Filaments)
  // ══════════════════════════════════════════════════════════════
  void _paintAmberNixieTube(Canvas canvas, Size size, double scale) {
    _paintSquircleBezelWithScrews(
      canvas,
      size,
      scale,
      bezelColors: const [
        Color(0xFFFDE8E1),
        Color(0xFFE5A99B),
        Color(0xFFB76E5E),
        Color(0xFF7A4034),
        Color(0xFFD69486),
      ],
      rimHighlightColor: const Color(0xFFFFECE5).withAlpha(170),
      grooveColor: const Color(0xFF2E110B),
      dialBg: const Color(0xFF0E0705),
      dialBgEnd: const Color(0xFF040201),
      screwColors: const [
        Color(0xFFE5A99B),
        Color(0xFF8D4F42),
        Color(0xFF53241B),
      ],
      slotColor: const Color(0xFF260E08),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    // Tube Dimensions & Positions - Centered at 0.50 with enlarged dimensions
    final tubeW = 20.5 * scale;
    final tubeH = 42.0 * scale;
    final tubeY = size.height * 0.50 - (tubeH / 2);
    final tubeGap = 3.2 * scale;
    final colonW = 7.0 * scale;
    final totalW = (tubeW * 4) + (tubeGap * 2) + colonW;
    final startX = center.dx - (totalW / 2);

    final digits = [hour ~/ 10, hour % 10, minute ~/ 10, minute % 10];

    // Paints for glowing wire filaments
    final glowPaint = Paint()
      ..color = const Color(0xFFFF8C00).withAlpha(90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2 * scale
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);

    final mainPaint = Paint()
      ..color = const Color(0xFFFF9500)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final corePaint = Paint()
      ..color = const Color(0xFFFFF7DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    double curX = startX;
    for (int i = 0; i < 4; i++) {
      if (i == 2) {
        // Neon Colon (Twin discharge dot tubes) - Centered vertically
        final colonCenterX = curX + (colonW / 2);
        final dotR = 1.8 * scale;
        final dotPaint = Paint()..color = const Color(0xFFFF9500);
        final dotGlow = Paint()
          ..color = const Color(0xFFFF8C00).withAlpha(90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8);

        for (final dy in [-7.0 * scale, 7.0 * scale]) {
          final c = Offset(colonCenterX, size.height * 0.50 + dy);
          canvas.drawCircle(c, dotR * 1.6, dotGlow);
          canvas.drawCircle(c, dotR, dotPaint);
          canvas.drawCircle(c, dotR * 0.45, Paint()..color = const Color(0xFFFFF7DB));
        }
        curX += colonW;
      }

      final tubeRect = Rect.fromLTWH(curX, tubeY, tubeW, tubeH);
      final tubeRRect = RRect.fromRectAndRadius(tubeRect, Radius.circular(5.0 * scale));

      // 1. Glass Cylinder Interior & Base
      final glassBg = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF22150E), Color(0xFF100905), Color(0xFF25160F)],
        ).createShader(tubeRect);
      canvas.drawRRect(tubeRRect, glassBg);

      // 2. Internal Cathode Wire Grid Pattern
      final gridP = Paint()
        ..color = const Color(0xFFFF9933).withAlpha(15)
        ..strokeWidth = 0.5 * scale;
      for (double gx = tubeRect.left + 3 * scale; gx < tubeRect.right - 2 * scale; gx += 3.2 * scale) {
        canvas.drawLine(Offset(gx, tubeRect.top + 3 * scale), Offset(gx, tubeRect.bottom - 3 * scale), gridP);
      }

      // 3. Top & Bottom Metallic Anode Mesh Caps
      final capPaint = Paint()
        ..color = const Color(0xFFB76E5E).withAlpha(120)
        ..strokeWidth = 1.2 * scale;
      canvas.drawLine(Offset(tubeRect.left + 2 * scale, tubeRect.top + 2.5 * scale), Offset(tubeRect.right - 2 * scale, tubeRect.top + 2.5 * scale), capPaint);
      canvas.drawLine(Offset(tubeRect.left + 2 * scale, tubeRect.bottom - 2.5 * scale), Offset(tubeRect.right - 2 * scale, tubeRect.bottom - 2.5 * scale), capPaint);

      // 4. Glass Reflection Sheen on Left
      final sheenPaint = Paint()
        ..color = Colors.white.withAlpha(35)
        ..strokeWidth = 0.8 * scale;
      canvas.drawLine(Offset(tubeRect.left + 2.0 * scale, tubeRect.top + 4 * scale), Offset(tubeRect.left + 2.0 * scale, tubeRect.bottom - 4 * scale), sheenPaint);

      // 5. Draw the actual curved glowing Nixie filament wire numeral!
      final digitBounds = tubeRect.deflate(3.2 * scale);
      _paintNixieWireNumeral(canvas, digitBounds, digits[i], glowPaint, mainPaint, corePaint);

      curX += tubeW + tubeGap;
    }
  }

  void _paintNixieWireNumeral(
    Canvas canvas,
    Rect bounds,
    int digit,
    Paint glowPaint,
    Paint mainPaint,
    Paint corePaint,
  ) {
    final p = Path();
    final l = bounds.left;
    final r = bounds.right;
    final t = bounds.top;
    final b = bounds.bottom;
    final w = bounds.width;
    final h = bounds.height;
    final cx = bounds.center.dx;
    final cy = bounds.center.dy;

    switch (digit) {
      case 0:
        p.addRRect(RRect.fromRectAndRadius(bounds, Radius.circular(w * 0.45)));
        break;
      case 1:
        p.moveTo(cx - w * 0.22, t + h * 0.16);
        p.lineTo(cx, t);
        p.lineTo(cx, b);
        break;
      case 2:
        p.moveTo(l, t + h * 0.24);
        p.cubicTo(l, t, r, t, r, t + h * 0.32);
        p.cubicTo(r, t + h * 0.55, l, t + h * 0.78, l, b);
        p.lineTo(r, b);
        break;
      case 3:
        p.moveTo(l, t + h * 0.1);
        p.lineTo(r - w * 0.1, t);
        p.cubicTo(r, t, r, cy, cx + w * 0.05, cy);
        p.cubicTo(r, cy, r, b, cx, b);
        p.cubicTo(l, b, l, b - h * 0.15, l, b - h * 0.15);
        break;
      case 4:
        p.moveTo(r - w * 0.2, b);
        p.lineTo(r - w * 0.2, t);
        p.lineTo(l, cy + h * 0.1);
        p.lineTo(r, cy + h * 0.1);
        break;
      case 5:
        p.moveTo(r, t);
        p.lineTo(l, t);
        p.lineTo(l, cy);
        p.cubicTo(cx, cy - h * 0.05, r, cy, r, b - h * 0.25);
        p.cubicTo(r, b, l, b, l, b - h * 0.1);
        break;
      case 6:
        p.moveTo(r - w * 0.1, t + h * 0.1);
        p.cubicTo(cx, t, l, cy - h * 0.1, l, b - h * 0.35);
        p.cubicTo(l, b, r, b, r, b - h * 0.35);
        p.cubicTo(r, cy, l, cy, l, b - h * 0.35);
        break;
      case 7:
        p.moveTo(l, t);
        p.lineTo(r, t);
        p.cubicTo(r, cy, cx, b * 0.8, cx - w * 0.1, b);
        break;
      case 8:
        p.addOval(Rect.fromLTWH(cx - w * 0.38, t, w * 0.76, (h * 0.5) + 0.5));
        p.addOval(Rect.fromLTWH(cx - w * 0.44, cy - 0.5, w * 0.88, h * 0.5));
        break;
      case 9:
      default:
        p.moveTo(l + w * 0.1, b - h * 0.1);
        p.cubicTo(cx, b, r, cy + h * 0.1, r, t + h * 0.35);
        p.cubicTo(r, t, l, t, l, t + h * 0.35);
        p.cubicTo(l, cy, r, cy, r, t + h * 0.35);
        break;
    }

    canvas.drawPath(p, glowPaint);
    canvas.drawPath(p, mainPaint);
    canvas.drawPath(p, corePaint);
  }

  // ══════════════════════════════════════════════════════════════
  // 4. ROYAL EMERALD & GOLD (Mechanical Flip-Card / Split-Flap Clock)
  // ══════════════════════════════════════════════════════════════
  void _paintEmeraldGoldLcd(Canvas canvas, Size size, double scale) {
    _paintSquircleBezelWithScrews(
      canvas,
      size,
      scale,
      bezelColors: const [
        Color(0xFFFFF1BD),
        Color(0xFFE8C252),
        Color(0xFFC49A28),
        Color(0xFF7B5A0C),
        Color(0xFFDFB63E),
      ],
      rimHighlightColor: const Color(0xFFFFF7DB).withAlpha(200),
      grooveColor: const Color(0xFF2A1C04),
      dialBg: const Color(0xFF031A12),
      dialBgEnd: const Color(0xFF010B07),
      screwColors: const [
        Color(0xFFFFF1BD),
        Color(0xFFC49A28),
        Color(0xFF6B4B03),
      ],
      slotColor: const Color(0xFF261902),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    // Dual Gold Guide Rails across emerald dial
    final railPaint = Paint()
      ..color = const Color(0xFFD4AF37).withAlpha(120)
      ..strokeWidth = 1.0 * scale;
    final rLeft = size.width * 0.12;
    final rRight = size.width * 0.88;
    canvas.drawLine(Offset(rLeft, size.height * 0.27), Offset(rRight, size.height * 0.27), railPaint);
    canvas.drawLine(Offset(rLeft, size.height * 0.73), Offset(rRight, size.height * 0.73), railPaint);

    // 4 Mechanical Split-Flap Cards - Centered at 0.50
    final cardW = 21.0 * scale;
    final cardH = 42.0 * scale;
    final cardY = size.height * 0.50 - (cardH / 2);
    final cardGap = 3.2 * scale;
    final colonW = 7.0 * scale;
    final totalW = (cardW * 4) + (cardGap * 2) + colonW;
    final startX = center.dx - (totalW / 2);

    final digits = [hour ~/ 10, hour % 10, minute ~/ 10, minute % 10];

    double curX = startX;
    for (int i = 0; i < 4; i++) {
      if (i == 2) {
        // Mechanical Hinge Colon - Centered vertically
        final colonX = curX + (colonW / 2);
        final dotPaint = Paint()..color = const Color(0xFFFFE082);
        canvas.drawCircle(Offset(colonX, size.height * 0.50 - 7.0 * scale), 1.9 * scale, dotPaint);
        canvas.drawCircle(Offset(colonX, size.height * 0.50 + 7.0 * scale), 1.9 * scale, dotPaint);
        curX += colonW;
      }

      final cardRect = Rect.fromLTWH(curX, cardY, cardW, cardH);
      final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(3.5 * scale));

      // Card Body (Deep Obsidian Emerald)
      final cardPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF052418), Color(0xFF02100A)],
        ).createShader(cardRect);
      canvas.drawRRect(cardRRect, cardPaint);

      // Card Gold Hairline Border
      final cardBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * scale
        ..color = const Color(0xFFD4AF37).withAlpha(100);
      canvas.drawRRect(cardRRect, cardBorder);

      // Stately Gold Embossed Numeral - Enlarged font size
      final tp = TextPainter(
        text: TextSpan(
          text: '${digits[i]}',
          style: TextStyle(
            fontSize: 31.0 * scale,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
            color: const Color(0xFFFFE082),
            shadows: [
              Shadow(
                color: Colors.black.withAlpha(180),
                offset: Offset(0.8 * scale, 1.2 * scale),
                blurRadius: 1.0,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cardRect.center.dx - (tp.width / 2), cardRect.center.dy - (tp.height / 2)));

      // Top Flap Shadow Overlay (creates physical flap dimension)
      final midY = cardRect.center.dy;
      final topFlapRect = Rect.fromLTRB(cardRect.left, cardRect.top, cardRect.right, midY);
      final topShadow = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withAlpha(110)],
        ).createShader(topFlapRect);
      canvas.drawRect(topFlapRect, topShadow);

      // Central Physical Split Line Groove
      final splitLine = Paint()
        ..color = Colors.black.withAlpha(230)
        ..strokeWidth = 1.3 * scale;
      canvas.drawLine(Offset(cardRect.left, midY), Offset(cardRect.right, midY), splitLine);

      // Bottom Flap Bevel Highlight below split
      final splitHighlight = Paint()
        ..color = const Color(0xFFFFE082).withAlpha(140)
        ..strokeWidth = 0.6 * scale;
      canvas.drawLine(Offset(cardRect.left, midY + 0.9 * scale), Offset(cardRect.right, midY + 0.9 * scale), splitHighlight);

      // Mechanical Left & Right Hinge Rivets
      final hingePaint = Paint()..color = const Color(0xFFD4AF37);
      canvas.drawCircle(Offset(cardRect.left + 1.2 * scale, midY), 1.2 * scale, hingePaint);
      canvas.drawCircle(Offset(cardRect.right - 1.2 * scale, midY), 1.2 * scale, hingePaint);

      curX += cardW + cardGap;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 5. CRIMSON CARBON SPORT (Circular LED Dot-Matrix Bulbs)
  // ══════════════════════════════════════════════════════════════
  static const Map<int, List<int>> _dotMatrix5x7 = {
    0: [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
    1: [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
    2: [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F],
    3: [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
    4: [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
    5: [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
    6: [0x0E, 0x11, 0x10, 0x1E, 0x11, 0x11, 0x0E],
    7: [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
    8: [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
    9: [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x11, 0x0E],
  };

  void _paintCrimsonCarbonMatrix(Canvas canvas, Size size, double scale) {
    // Octagonal Sports Case (Aggressive 45-degree corner bevels)
    final outerRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final octPath = Path();
    final cCut = 22.0 * scale;
    octPath.moveTo(cCut, 0);
    octPath.lineTo(size.width - cCut, 0);
    octPath.lineTo(size.width, cCut);
    octPath.lineTo(size.width, size.height - cCut);
    octPath.lineTo(size.width - cCut, size.height);
    octPath.lineTo(cCut, size.height);
    octPath.lineTo(0, size.height - cCut);
    octPath.lineTo(0, cCut);
    octPath.close();

    // Matte Titanium Gunmetal Bezel
    final bezelPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5A626A), Color(0xFF383E44), Color(0xFF23272B), Color(0xFF14171A), Color(0xFF434A51)],
      ).createShader(outerRect);
    canvas.drawPath(octPath, bezelPaint);

    // Red Anodized Racing Accent Rim
    final innerPath = Path();
    final iCut = 18.0 * scale;
    final iMargin = 6.0 * scale;
    innerPath.moveTo(iMargin + iCut, iMargin);
    innerPath.lineTo(size.width - iMargin - iCut, iMargin);
    innerPath.lineTo(size.width - iMargin, iMargin + iCut);
    innerPath.lineTo(size.width - iMargin, size.height - iMargin - iCut);
    innerPath.lineTo(size.width - iMargin - iCut, size.height - iMargin);
    innerPath.lineTo(iMargin + iCut, size.height - iMargin);
    innerPath.lineTo(iMargin, size.height - iMargin - iCut);
    innerPath.lineTo(iMargin, iMargin + iCut);
    innerPath.close();

    final redRimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale
      ..color = const Color(0xFFFF1E27).withAlpha(160);
    canvas.drawPath(innerPath, redRimPaint);

    // Carbon Fiber Dial Interior
    final dialPath = Path();
    final dCut = 15.0 * scale;
    final dMargin = 8.5 * scale;
    dialPath.moveTo(dMargin + dCut, dMargin);
    dialPath.lineTo(size.width - dMargin - dCut, dMargin);
    dialPath.lineTo(size.width - dMargin, dMargin + dCut);
    dialPath.lineTo(size.width - dMargin, size.height - dMargin - dCut);
    dialPath.lineTo(size.width - dMargin - dCut, size.height - dMargin);
    dialPath.lineTo(dMargin + dCut, size.height - dMargin);
    dialPath.lineTo(dMargin, size.height - dMargin - dCut);
    dialPath.lineTo(dMargin, dMargin + dCut);
    dialPath.close();

    canvas.drawPath(dialPath, Paint()..color = const Color(0xFF0A0A0C));

    // Real Carbon-Fiber Diagonal Weave Texture
    canvas.save();
    canvas.clipPath(dialPath);
    final carbonP = Paint()
      ..color = Colors.white.withAlpha(10)
      ..strokeWidth = 0.85 * scale;
    for (double i = -size.width; i < size.width * 2; i += 7.0 * scale) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), carbonP);
    }
    canvas.restore();

    // 8 Corner Titanium Hex Bolts
    final boltCenters = [
      Offset(cCut * 0.7, cCut * 0.7),
      Offset(size.width - cCut * 0.7, cCut * 0.7),
      Offset(size.width - cCut * 0.7, size.height - cCut * 0.7),
      Offset(cCut * 0.7, size.height - cCut * 0.7),
      Offset(size.width / 2, 4.0 * scale),
      Offset(size.width / 2, size.height - 4.0 * scale),
      Offset(4.0 * scale, size.height / 2),
      Offset(size.width - 4.0 * scale, size.height / 2),
    ];
    final boltPaint = Paint()..color = const Color(0xFF717D8A);
    for (final bc in boltCenters) {
      canvas.drawCircle(bc, 1.8 * scale, boltPaint);
      canvas.drawCircle(bc, 0.7 * scale, Paint()..color = const Color(0xFF14171A));
    }

    final center = Offset(size.width / 2, size.height / 2);
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    // True 5x7 Circular LED Bulbs Grid - Enlarged & Centered at 0.50
    final digits = [hour ~/ 10, hour % 10, minute ~/ 10, minute % 10];
    final stepX = 3.8 * scale;
    final stepY = 4.8 * scale;
    final dotR = 1.65 * scale;
    final digitW = 4 * stepX;
    final digitGap = 4.2 * scale;
    final colonW = 7.5 * scale;
    final totalW = (digitW * 4) + (digitGap * 2) + colonW;
    final startX = center.dx - (totalW / 2);
    final startY = size.height * 0.50 - (3 * stepY);

    final litPaint = Paint()..color = const Color(0xFFFF1E27);
    final glowPaint = Paint()
      ..color = const Color(0xFFFF1E27).withAlpha(70)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    final unlitPaint = Paint()..color = const Color(0x18FF1E27);

    double curX = startX;
    for (int d = 0; d < 4; d++) {
      if (d == 2) {
        // Dot-Matrix Colon (Round LED Bulbs) - Centered around Row 3
        final colonCenterX = curX + (colonW / 2);
        for (final row in [2, 4]) {
          final c = Offset(colonCenterX, startY + row * stepY);
          canvas.drawCircle(c, dotR * 1.5, glowPaint);
          canvas.drawCircle(c, dotR, litPaint);
        }
        curX += colonW;
      }

      final rows = _dotMatrix5x7[digits[d]] ?? _dotMatrix5x7[0]!;
      for (int r = 0; r < 7; r++) {
        final bits = rows[r];
        for (int c = 0; c < 5; c++) {
          final isLit = ((bits >> (4 - c)) & 1) == 1;
          final dotCenter = Offset(curX + c * stepX, startY + r * stepY);
          if (isLit) {
            canvas.drawCircle(dotCenter, dotR * 1.5, glowPaint);
            canvas.drawCircle(dotCenter, dotR, litPaint);
          } else {
            canvas.drawCircle(dotCenter, dotR * 0.85, unlitPaint);
          }
        }
      }

      curX += digitW + digitGap;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 6. BAUHAUS DARK GRAPHITE (Dark Slate Dial & Monolithic Numerals)
  // ══════════════════════════════════════════════════════════════
  void _paintMonochromeBauhaus(Canvas canvas, Size size, double scale) {
    // Pure Circular Inner Dial inside Square Gunmetal Bezel
    final outerRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bezelPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF2D3748), Color(0xFF1E293B), Color(0xFF0F172A), Color(0xFF090D15), Color(0xFF1E293B)],
      ).createShader(outerRect);
    canvas.drawRRect(RRect.fromRectAndRadius(outerRect, Radius.circular(16.0 * scale)), bezelPaint);

    final center = Offset(size.width / 2, size.height / 2);
    final dialRadius = (size.width / 2) - (8.5 * scale);

    // Matte Dark Graphite Slate Circular Dial
    final slatePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.9,
        colors: const [Color(0xFF141A23), Color(0xFF0B0E14)],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, slatePaint);

    // Precision Burnished Steel Rim
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale
      ..color = const Color(0xFF475569).withAlpha(100);
    canvas.drawCircle(center, dialRadius, rimPaint);

    // Technical Precision Crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF64748B).withAlpha(90)
      ..strokeWidth = 0.8 * scale;
    final cIn = dialRadius * 0.86;
    final cOut = dialRadius * 0.96;
    for (final angle in [0.0, pi * 0.5, pi, pi * 1.5]) {
      final dx = cos(angle);
      final dy = sin(angle);
      canvas.drawLine(Offset(center.dx + cIn * dx, center.dy + cIn * dy), Offset(center.dx + cOut * dx, center.dy + cOut * dy), crossPaint);
    }

    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    // Heavyweight Monolithic Bauhaus Stencil Numerals - Centered at 0.50 & Enlarged
    final hourTens = hour ~/ 10;
    final hourOnes = hour % 10;
    final minTens = minute ~/ 10;
    final minOnes = minute % 10;

    final digitW = 20.0 * scale;
    final digitH = 38.0 * scale;
    final digitGap = 3.5 * scale;
    final colonW = 7.0 * scale;
    final totalW = (digitW * 4) + (digitGap * 2) + colonW;
    final startX = center.dx - (totalW / 2);
    final y = size.height * 0.50;

    final digits = [hourTens, hourOnes, minTens, minOnes];

    double curX = startX;
    for (int i = 0; i < 4; i++) {
      if (i == 2) {
        // Bauhaus Square Colon Dots - Polar White
        final colonX = curX + (colonW / 2);
        final sqSide = 3.2 * scale;
        final colonPaint = Paint()..color = const Color(0xFFF8FAFC);
        canvas.drawRect(Rect.fromCenter(center: Offset(colonX, y - 7.0 * scale), width: sqSide, height: sqSide), colonPaint);
        canvas.drawRect(Rect.fromCenter(center: Offset(colonX, y + 7.0 * scale), width: sqSide, height: sqSide), colonPaint);
        curX += colonW;
      }

      _paintBauhausStencilDigit(canvas, Offset(curX + (digitW / 2), y), scale, digits[i], digitW, digitH);
      curX += digitW + digitGap;
    }
  }

  void _paintBauhausStencilDigit(Canvas canvas, Offset center, double scale, int digit, double w, double h) {
    final segs = _digitSegments[digit] ?? [true, true, true, true, true, true, false];
    final t = 5.2 * scale; // Ultra-thick monolithic bar
    final sGap = 1.4 * scale; // Clean Bauhaus stencil gap cutout
    final halfW = w / 2;
    final halfH = h / 2;

    final inkPaint = Paint()..color = const Color(0xFFF8FAFC);
    final debossPaint = Paint()..color = const Color(0xFF080B0F);

    // Segment A (Top)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx - halfW + sGap, center.dy - halfH, center.dx + halfW - sGap, center.dy - halfH + t), Radius.circular(0.8 * scale)),
      segs[0] ? inkPaint : debossPaint,
    );
    // Segment B (Top-Right)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx + halfW - t, center.dy - halfH + sGap, center.dx + halfW, center.dy - sGap), Radius.circular(0.8 * scale)),
      segs[1] ? inkPaint : debossPaint,
    );
    // Segment C (Bottom-Right)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx + halfW - t, center.dy + sGap, center.dx + halfW, center.dy + halfH - sGap), Radius.circular(0.8 * scale)),
      segs[2] ? inkPaint : debossPaint,
    );
    // Segment D (Bottom)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx - halfW + sGap, center.dy + halfH - t, center.dx + halfW - sGap, center.dy + halfH), Radius.circular(0.8 * scale)),
      segs[3] ? inkPaint : debossPaint,
    );
    // Segment E (Bottom-Left)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx - halfW, center.dy + sGap, center.dx - halfW + t, center.dy + halfH - sGap), Radius.circular(0.8 * scale)),
      segs[4] ? inkPaint : debossPaint,
    );
    // Segment F (Top-Left)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx - halfW, center.dy - halfH + sGap, center.dx - halfW + t, center.dy - sGap), Radius.circular(0.8 * scale)),
      segs[5] ? inkPaint : debossPaint,
    );
    // Segment G (Center)
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(center.dx - halfW + sGap, center.dy - (t / 2), center.dx + halfW - sGap, center.dy + (t / 2)), Radius.circular(0.8 * scale)),
      segs[6] ? inkPaint : debossPaint,
    );
  }

  // ══════════════════════════════════════════════════════════════
  // 7. CLASSIC BRASS E-INK CLOCK (Image 2: media_1790019228166.png)
  // ══════════════════════════════════════════════════════════════
  void _paintCyberVioletNeon(Canvas canvas, Size size, double scale) {
    // 1. Brushed Brass Squircle Bezel with 4 Corner Screws & Light Dial
    _paintSquircleBezelWithScrews(
      canvas,
      size,
      scale,
      bezelColors: const [
        Color(0xFFFFF2C2),
        Color(0xFFE8C55E),
        Color(0xFFC49A28),
        Color(0xFF825F12),
        Color(0xFFDFB845),
      ],
      rimHighlightColor: const Color(0xFFFFF7DB).withAlpha(180),
      grooveColor: const Color(0xFF4A340C),
      dialBg: const Color(0xFFFAF9F6),
      dialBgEnd: const Color(0xFFECEAE4),
      innerShadowColor: const Color(0x35000000),
      screwColors: const [
        Color(0xFFFFF1BD),
        Color(0xFFC49A28),
        Color(0xFF6B4B03),
      ],
      slotColor: const Color(0xFF4A340C),
    );

    final center = Offset(size.width / 2, size.height / 2);

    // 2. Circular Chapter Ring (60 Ticks: 12 Batons + 48 Minute Marks)
    final outerR = 52.5 * scale;
    final hourBatonLen = 5.2 * scale;
    final minuteTickLen = 2.6 * scale;

    final hourTickPaint = Paint()
      ..color = const Color(0xFF1C1F22)
      ..strokeWidth = 2.4 * scale
      ..strokeCap = StrokeCap.square;

    final minTickPaint = Paint()
      ..color = const Color(0xFF1C1F22).withAlpha(160)
      ..strokeWidth = 0.95 * scale
      ..strokeCap = StrokeCap.square;

    for (int i = 0; i < 60; i++) {
      final angle = (i * 2 * pi / 60) - (pi / 2);
      final isHour = (i % 5 == 0);
      final len = isHour ? hourBatonLen : minuteTickLen;
      final p = isHour ? hourTickPaint : minTickPaint;

      final pOuter = Offset(
        center.dx + outerR * cos(angle),
        center.dy + outerR * sin(angle),
      );
      final pInner = Offset(
        center.dx + (outerR - len) * cos(angle),
        center.dy + (outerR - len) * sin(angle),
      );

      canvas.drawLine(pOuter, pInner, p);
    }

    // 3. Top "E-INK" Header
    final einkTp = TextPainter(
      text: TextSpan(
        text: 'E-INK',
        style: TextStyle(
          fontSize: 13.5 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.2 * scale,
          color: const Color(0xFF1C1F22),
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    einkTp.paint(
      canvas,
      Offset(
        center.dx - (einkTp.width / 2),
        (size.height * 0.28) - (einkTp.height / 2),
      ),
    );

    // 4. Center Bold Grotesque Sans-Serif Time Digits (e.g. "12:59")
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;
    final timeStr = '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    final timeTp = TextPainter(
      text: TextSpan(
        text: timeStr,
        style: TextStyle(
          fontSize: 40.0 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.8 * scale,
          color: const Color(0xFF1A1D20),
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    timeTp.paint(
      canvas,
      Offset(
        center.dx - (timeTp.width / 2),
        (size.height * 0.50) - (timeTp.height / 2),
      ),
    );

    // 5. Authentic MD Logo is rendered at the bottom via DigitalClockFace overlay!
    // No dates, weather icons, or secondary widgets. Strictly time and brand!
  }

  // ══════════════════════════════════════════════════════════════
  // 8. ROYAL SAPPHIRE FLIP CLOCK (Mechanical Flip Clock from image 2)
  // ══════════════════════════════════════════════════════════════
  void _paintIceBlueCrystal(Canvas canvas, Size size, double scale) {
    _paintSquircleBezelWithScrews(
      canvas,
      size,
      scale,
      bezelColors: const [
        Color(0xFFFFF1BD),
        Color(0xFFE8C252),
        Color(0xFFC49A28),
        Color(0xFF7B5A0C),
        Color(0xFFDFB63E),
      ],
      rimHighlightColor: const Color(0xFFFFF7DB).withAlpha(200),
      grooveColor: const Color(0xFF04101D),
      dialBg: const Color(0xFF071F38),
      dialBgEnd: const Color(0xFF020A14),
      screwColors: const [
        Color(0xFFFFF1BD),
        Color(0xFFC49A28),
        Color(0xFF6B4B03),
      ],
      slotColor: const Color(0xFF04101D),
    );

    final center = Offset(size.width / 2, size.height / 2);
    final hour = is24Hour ? dateTime.hour : (dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12);
    final minute = dateTime.minute;

    // Dual Sapphire-Gold Guide Rails across midnight sapphire dial
    final railPaint = Paint()
      ..color = const Color(0xFF38BDF8).withAlpha(90)
      ..strokeWidth = 1.0 * scale;
    final rLeft = size.width * 0.12;
    final rRight = size.width * 0.88;
    canvas.drawLine(Offset(rLeft, size.height * 0.27), Offset(rRight, size.height * 0.27), railPaint);
    canvas.drawLine(Offset(rLeft, size.height * 0.73), Offset(rRight, size.height * 0.73), railPaint);

    // 4 Mechanical Split-Flap Cards (image 2 style) - Centered at 0.50
    final cardW = 21.0 * scale;
    final cardH = 42.0 * scale;
    final cardY = size.height * 0.50 - (cardH / 2);
    final cardGap = 3.2 * scale;
    final colonW = 7.0 * scale;
    final totalW = (cardW * 4) + (cardGap * 2) + colonW;
    final startX = center.dx - (totalW / 2);

    final digits = [hour ~/ 10, hour % 10, minute ~/ 10, minute % 10];

    double curX = startX;
    for (int i = 0; i < 4; i++) {
      if (i == 2) {
        // Mechanical Hinge Colon - Centered vertically
        final colonX = curX + (colonW / 2);
        final dotPaint = Paint()..color = const Color(0xFFFFE082);
        canvas.drawCircle(Offset(colonX, size.height * 0.50 - 7.0 * scale), 1.9 * scale, dotPaint);
        canvas.drawCircle(Offset(colonX, size.height * 0.50 + 7.0 * scale), 1.9 * scale, dotPaint);
        curX += colonW;
      }

      final cardRect = Rect.fromLTWH(curX, cardY, cardW, cardH);
      final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(3.5 * scale));

      // Card Body (Deep Obsidian Charcoal Navy)
      final cardPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1724), Color(0xFF040810)],
        ).createShader(cardRect);
      canvas.drawRRect(cardRRect, cardPaint);

      // Card Gold Hairline Border
      final cardBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8 * scale
        ..color = const Color(0xFFD4AF37).withAlpha(100);
      canvas.drawRRect(cardRRect, cardBorder);

      // Stately Gold Embossed Serif Numeral
      final tp = TextPainter(
        text: TextSpan(
          text: '${digits[i]}',
          style: TextStyle(
            fontSize: 31.0 * scale,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
            color: const Color(0xFFFFE082),
            shadows: [
              Shadow(
                color: Colors.black.withAlpha(180),
                offset: Offset(0.8 * scale, 1.2 * scale),
                blurRadius: 1.0,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cardRect.center.dx - (tp.width / 2), cardRect.center.dy - (tp.height / 2)));

      // Top Flap Shadow Overlay (physical split-flap dimension)
      final midY = cardRect.center.dy;
      final topFlapRect = Rect.fromLTRB(cardRect.left, cardRect.top, cardRect.right, midY);
      final topShadow = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withAlpha(120)],
        ).createShader(topFlapRect);
      canvas.drawRect(topFlapRect, topShadow);

      // Central Physical Split Line Groove
      final splitLine = Paint()
        ..color = Colors.black.withAlpha(230)
        ..strokeWidth = 1.3 * scale;
      canvas.drawLine(Offset(cardRect.left, midY), Offset(cardRect.right, midY), splitLine);

      // Bottom Flap Bevel Highlight below split
      final splitHighlight = Paint()
        ..color = const Color(0xFFFFE082).withAlpha(140)
        ..strokeWidth = 0.6 * scale;
      canvas.drawLine(Offset(cardRect.left, midY + 0.9 * scale), Offset(cardRect.right, midY + 0.9 * scale), splitHighlight);

      // Mechanical Left & Right Hinge Rivets
      final hingePaint = Paint()..color = const Color(0xFFD4AF37);
      canvas.drawCircle(Offset(cardRect.left + 1.2 * scale, midY), 1.2 * scale, hingePaint);
      canvas.drawCircle(Offset(cardRect.right - 1.2 * scale, midY), 1.2 * scale, hingePaint);

      curX += cardW + cardGap;
    }
  }

  @override
  bool shouldRepaint(covariant DigitalClockPainter oldDelegate) {
    return oldDelegate.dateTime.minute != dateTime.minute ||
        oldDelegate.dateTime.hour != dateTime.hour ||
        oldDelegate.dateTime.second != dateTime.second ||
        oldDelegate.design.id != design.id ||
        oldDelegate.isDark != isDark ||
        oldDelegate.showSeconds != showSeconds ||
        oldDelegate.is24Hour != is24Hour;
  }
}

/// A composited widget that paints the digital clock face and overlays
/// the authentic transparent MD logo emblem asset.
class DigitalClockFace extends StatelessWidget {
  final DateTime dateTime;
  final bool isDark;
  final ClockDesign design;
  final bool is24Hour;
  final bool showSeconds;
  final double size;

  const DigitalClockFace({
    super.key,
    required this.dateTime,
    required this.isDark,
    required this.design,
    this.is24Hour = false,
    this.showSeconds = true,
    this.size = 140.0,
  });

  @override
  Widget build(BuildContext context) {
    final scale = size / 140.0;

    final isTopLogo = design.id == 'digital_dot_matrix_white' ||
        design.id == 'digital_red_led_leaf_md' ||
        design.id == 'digital_emerald_gold_lcd' ||
        design.id == 'digital_crimson_carbon_matrix' ||
        design.id == 'digital_ice_blue_crystal';

    final isBottomLogo = design.id == 'digital_cyan_weather_schedule' ||
        design.id == 'digital_white_led_status' ||
        design.id == 'digital_amber_nixie_tube' ||
        design.id == 'digital_monochrome_bauhaus' ||
        design.id == 'digital_cyber_violet_neon';

    Widget? emblem;
    if (isTopLogo) {
      final w = 28.0 * scale;
      final h = 19.5 * scale;
      final left = (size - w) / 2;
      final top = 11.0 * scale;
      emblem = Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: Image.asset(
          'assets/images/md_logo_emblem.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      );
    } else if (isBottomLogo) {
      final isEInk = design.id == 'digital_cyber_violet_neon';
      final w = (isEInk ? 28.0 : 30.0) * scale;
      final h = (isEInk ? 19.5 : 21.0) * scale;
      final left = (size - w) / 2;
      final top = isEInk ? ((size * 0.735) - (h / 2)) : ((size * 0.81) - (h / 2));
      emblem = Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: Image.asset(
          'assets/images/md_logo_emblem.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: DigitalClockPainter(
              dateTime: dateTime,
              isDark: isDark,
              design: design,
              is24Hour: is24Hour,
              showSeconds: showSeconds,
            ),
          ),
          ?emblem,
        ],
      ),
    );
  }
}

