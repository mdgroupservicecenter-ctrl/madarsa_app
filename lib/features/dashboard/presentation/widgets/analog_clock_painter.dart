import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/services/clock_theme_service.dart';

/// Analog clock painter that renders the 8 authentic clock designs
/// from the curated MD GROUP collection.
class AnalogClockPainter extends CustomPainter {
  final DateTime dateTime;
  final bool isDark;
  final ClockDesign? design;
  final ClockTheme? theme;

  AnalogClockPainter({
    required this.dateTime,
    required this.isDark,
    this.design,
    this.theme,
  });

  ClockDesign get _activeDesign => design ?? ClockThemeService.defaultAnalogDesign;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    // Ensure strict edge-to-edge circular geometry (no square overflow)
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    switch (_activeDesign.id) {
      case 'analog_military_chrono_md':
        _paintMilitaryChronoMD(canvas, center, radius);
        break;
      case 'analog_ruby_sunburst_md':
        _paintRubySunburstMD(canvas, center, radius);
        break;
      case 'analog_rosegold_black_skeleton':
        _paintRoseGoldBlackSkeleton(canvas, center, radius);
        break;
      case 'analog_moonphase_pearl_gold':
        _paintMoonphasePearlGold(canvas, center, radius);
        break;
      case 'analog_classic_roman_gold':
        _paintClassicRomanGold(canvas, center, radius);
        break;
      case 'analog_emerald_leaf_code':
        _paintEmeraldLeafCode(canvas, center, radius);
        break;
      case 'analog_steampunk_skeleton':
        _paintSteampunkSkeleton(canvas, center, radius);
        break;
      case 'analog_minimalist_stealth':
        _paintMinimalistStealth(canvas, center, radius);
        break;
      default:
        _paintMilitaryChronoMD(canvas, center, radius);
        break;
    }

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // 1. ROYAL WALNUT ROMAN BRASS (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintClassicRomanGold(Canvas canvas, Offset center, double radius) {
    // 1. Outermost Dark Matte Gunmetal Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF141618));

    // 4. Multi-Tiered 3D Sculpted Metallic Brass Bezel
    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.075;
    final brassBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFFFF3D1), // Top-left bright specular highlight
          Color(0xFFE5C158),
          Color(0xFFA17424),
          Color(0xFF5E400E), // Bottom-right deep bronze shadow
          Color(0xFFA17424),
          Color(0xFFE5C158),
          Color(0xFFFFF3D1),
        ],
        stops: [0.0, 0.22, 0.44, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, brassBezel);

    // Outer Bezel Rim Highlight
    canvas.drawCircle(
      center,
      radius * 0.925,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFFFF8E3).withAlpha(190),
    );

    // Inner Recessed Shadow Groove
    canvas.drawCircle(
      center,
      radius * 0.845,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0xFF140F08),
    );

    // Inner Gold Rehaut Lip
    canvas.drawCircle(
      center,
      radius * 0.835,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFECC76D),
    );

    // 5. Dial Face (Circular-Brushed Anthracite / Charcoal Sunray Finish)
    final dialRadius = radius * 0.83;
    final dialPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, -0.15),
        colors: const [
          Color(0xFF282C33), // Subtle warm center sheen
          Color(0xFF1C2025),
          Color(0xFF121417), // Deep charcoal outer perimeter
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, dialPaint);

    // Circular brushed satin sheen lines
    final dialSheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withAlpha(6);
    for (double r = dialRadius * 0.22; r < dialRadius * 0.95; r += 3.5) {
      canvas.drawCircle(center, r, dialSheen);
    }

    // 6. Gold Railroad Minute Track
    final rOuter = dialRadius * 0.955;
    final rInner = dialRadius * 0.865;
    final trackRingPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFD4AF37).withAlpha(210);
    canvas.drawCircle(center, rOuter, trackRingPaint);
    canvas.drawCircle(center, rInner, trackRingPaint);

    final tickPaint = Paint()..strokeCap = StrokeCap.square;
    for (int i = 0; i < 60; i++) {
      final angle = (i * 6) * pi / 180;
      final isHour = i % 5 == 0;
      final cosA = cos(angle);
      final sinA = sin(angle);

      if (isHour) {
        tickPaint
          ..color = const Color(0xFFFFF2D0)
          ..strokeWidth = 1.5;
        canvas.drawLine(
          Offset(center.dx + rInner * sinA, center.dy - rInner * cosA),
          Offset(center.dx + rOuter * sinA, center.dy - rOuter * cosA),
          tickPaint,
        );
      } else {
        tickPaint
          ..color = const Color(0xFFD4AF37).withAlpha(160)
          ..strokeWidth = 0.6;
        canvas.drawLine(
          Offset(center.dx + (rInner + 0.4) * sinA, center.dy - (rInner + 0.4) * cosA),
          Offset(center.dx + (rOuter - 0.4) * sinA, center.dy - (rOuter - 0.4) * cosA),
          tickPaint,
        );
      }
    }

    // 7. 12 Roman Numerals in Classical Serif Typography & 3D Bevels
    // Notice: 4 is 'IIII' (Watchmaker's Four, identical to the reference image)
    final numerals = {
      12: 'XII', 1: 'I', 2: 'II', 3: 'III', 4: 'IIII', 5: 'V',
      6: 'VI', 7: 'VII', 8: 'VIII', 9: 'IX', 10: 'X', 11: 'XI',
    };
    final numeralRadius = dialRadius * 0.69;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final entry in numerals.entries) {
      final hour = entry.key;
      final text = entry.value;
      final angle = (hour * 30) * pi / 180;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      // 3D Drop shadow under numeral
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: radius * 0.145,
          fontWeight: FontWeight.w800,
          color: Colors.black.withAlpha(180),
          letterSpacing: 0.4,
        ),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(-tp.width / 2 + 0.5, -numeralRadius - tp.height / 2 + 0.8),
      );

      // Polished Gold Roman Numeral with bevel highlight
      tp.text = TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'serif',
          fontSize: radius * 0.145,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFECC875),
          letterSpacing: 0.4,
          shadows: const [
            Shadow(color: Color(0xFFFFF6DB), offset: Offset(0, -0.4), blurRadius: 0.5),
          ],
        ),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(-tp.width / 2, -numeralRadius - tp.height / 2),
      );

      canvas.restore();
    }

    // 8. 3D Faceted Dauphine Hands
    final (hAngle, mAngle, sAngle) = _calculateAngles();

    // Hour Hand (Faceted Dauphine)
    _drawWalnutRomanDauphineHand(
      canvas,
      center,
      hAngle,
      dialRadius * 0.55,
      dialRadius * 0.085,
      lightColor: const Color(0xFFF7E2A3),
      darkColor: const Color(0xFFA67A26),
      spineColor: const Color(0xFFFFF9E6),
    );

    // Minute Hand (Longer Faceted Dauphine)
    _drawWalnutRomanDauphineHand(
      canvas,
      center,
      mAngle,
      dialRadius * 0.82,
      dialRadius * 0.068,
      lightColor: const Color(0xFFFBF0CD),
      darkColor: const Color(0xFF8F641B),
      spineColor: const Color(0xFFFFFBF0),
    );

    // Second Hand (Rose-Gold Needle with Counterweight)
    _drawWalnutRomanSecondHand(
      canvas,
      center,
      sAngle,
      dialRadius * 0.88,
      dialRadius * 0.22,
      const Color(0xFFE28C4A),
    );

    // 9. Multi-Tier Center Boss / Pinion
    // Outer polished gold ring
    canvas.drawCircle(center, radius * 0.075, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(
      center,
      radius * 0.075,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFFF4D4),
    );

    // Mid warm rose-gold ring
    canvas.drawCircle(center, radius * 0.050, Paint()..color = const Color(0xFFE28C4A));

    // Inner bevel & center dark screw dimple
    canvas.drawCircle(center, radius * 0.030, Paint()..color = const Color(0xFFECC875));
    canvas.drawCircle(center, radius * 0.015, Paint()..color = const Color(0xFF1B140B));
  }

  // ══════════════════════════════════════════════════════════════
  // 2. EMERALD LEAF & CODE </> (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintEmeraldLeafCode(Canvas canvas, Offset center, double radius) {
    // 1. Outer Forest Green Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF072B1E));

    // 4. Multi-Tiered 3D Sculpted Metallic Brass Bezel
    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.075;
    final brassBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFFFF3D1), // Top-left specular highlight
          Color(0xFFE5C158),
          Color(0xFFA17424),
          Color(0xFF5E400E), // Bottom-right shadow
          Color(0xFFA17424),
          Color(0xFFE5C158),
          Color(0xFFFFF3D1),
        ],
        stops: [0.0, 0.22, 0.44, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, brassBezel);

    // Inner Gold Rehaut Lip
    canvas.drawCircle(
      center,
      radius * 0.835,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFECC76D),
    );

    // 5. Dial Face (Vibrant Emerald Green Sunburst)
    final dialRadius = radius * 0.83;
    final dialPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, -0.15),
        colors: const [
          Color(0xFF0EA370), // Center bright emerald sunray
          Color(0xFF077A53),
          Color(0xFF034830), // Deep rich emerald perimeter
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, dialPaint);

    // Circular brushed satin sheen lines
    final dialSheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withAlpha(8);
    for (double r = dialRadius * 0.22; r < dialRadius * 0.95; r += 3.5) {
      canvas.drawCircle(center, r, dialSheen);
    }

    // 6. The Sacred Center Jewel Leaf Emblem
    _drawEmeraldJeweledLeaf(canvas, center, dialRadius);

    // 7. Code Bracket Markers </> at 12, 3, 6, 9
    final codeRadius = dialRadius * 0.76;
    _drawCodeBracketMarker(canvas, Offset(center.dx, center.dy - codeRadius), isVertical: false, scale: radius * 0.009);
    _drawCodeBracketMarker(canvas, Offset(center.dx + codeRadius, center.dy), isVertical: true, scale: radius * 0.009);
    _drawCodeBracketMarker(canvas, Offset(center.dx, center.dy + codeRadius), isVertical: false, scale: radius * 0.009);
    _drawCodeBracketMarker(canvas, Offset(center.dx - codeRadius, center.dy), isVertical: true, scale: radius * 0.009);

    // 8. Polished Gold Baton Markers at 1, 2, 4, 5, 7, 8, 10, 11
    final batonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = const Color(0xFFECC875);

    final batonShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4
      ..color = Colors.black.withAlpha(120);

    for (int i = 1; i <= 12; i++) {
      if (i % 3 != 0) {
        final a = (i * 30) * pi / 180;
        final cosA = cos(a);
        final sinA = sin(a);
        final rStart = dialRadius * 0.73;
        final rEnd = dialRadius * 0.84;

        canvas.drawLine(
          Offset(center.dx + rStart * sinA + 0.6, center.dy - rStart * cosA + 0.8),
          Offset(center.dx + rEnd * sinA + 0.6, center.dy - rEnd * cosA + 0.8),
          batonShadow,
        );
        canvas.drawLine(
          Offset(center.dx + rStart * sinA, center.dy - rStart * cosA),
          Offset(center.dx + rEnd * sinA, center.dy - rEnd * cosA),
          batonPaint,
        );
      }
    }

    // 9. Faceted Rose-Gold Dauphine Hands
    final (hAngle, mAngle, sAngle) = _calculateAngles();

    // Hour Hand
    _drawWalnutRomanDauphineHand(
      canvas,
      center,
      hAngle,
      dialRadius * 0.52,
      dialRadius * 0.08,
      lightColor: const Color(0xFFE89A60),
      darkColor: const Color(0xFF9E5424),
      spineColor: const Color(0xFFFBD7BA),
    );

    // Minute Hand
    _drawWalnutRomanDauphineHand(
      canvas,
      center,
      mAngle,
      dialRadius * 0.78,
      dialRadius * 0.065,
      lightColor: const Color(0xFFF2A972),
      darkColor: const Color(0xFF8C481C),
      spineColor: const Color(0xFFFCE3CE),
    );

    // Second Hand (with rectangular bar counterweight near tail)
    _drawEmeraldLeafSecondHand(
      canvas,
      center,
      sAngle,
      dialRadius * 0.86,
      dialRadius * 0.22,
      const Color(0xFFE28C4A),
    );

    // 10. Center Pinion Boss
    canvas.drawCircle(center, radius * 0.065, Paint()..color = const Color(0xFFB86634));
    canvas.drawCircle(
      center,
      radius * 0.065,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFF7C8A8),
    );
    canvas.drawCircle(center, radius * 0.040, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(center, radius * 0.018, Paint()..color = const Color(0xFF1B140B));
  }

  // ══════════════════════════════════════════════════════════════
  // 3. STEAMPUNK GEARS SKELETON (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintSteampunkSkeleton(Canvas canvas, Offset center, double radius) {
    // 1. Multi-Tiered Industrial Gunmetal Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF181B1F));

    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.070;
    final gunmetalBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFF5A626E), // Top-left metallic steel highlight
          Color(0xFF383D45),
          Color(0xFF22262B),
          Color(0xFF15171A), // Bottom-right shadow
          Color(0xFF22262B),
          Color(0xFF383D45),
          Color(0xFF5A626E),
        ],
        stops: [0.0, 0.22, 0.44, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, gunmetalBezel);

    // Concentric stepped highlights
    canvas.drawCircle(
      center,
      radius * 0.925,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFF6B7280).withAlpha(160),
    );

    // 4. Exposed Skeleton Deep Obsidian Movement Bay
    final skeletonRadius = radius * 0.84;
    canvas.drawCircle(center, skeletonRadius, Paint()..color = const Color(0xFF0A0C0E));

    // 5. Steampunk Gears Mechanical Movement
    // Decorative Bridges with Jewel Inlays
    _drawSteampunkJeweledBridges(canvas, center, skeletonRadius);

    // Top Spur Gear (12 o'clock)
    _drawSteampunkSpurGear(
      canvas,
      Offset(center.dx, center.dy - skeletonRadius * 0.42),
      skeletonRadius * 0.28,
      teeth: 16,
      spokes: 8,
      gearColor: const Color(0xFFD4AF37),
    );

    // Left Curved Spoke Gear (8-9 o'clock)
    _drawSteampunkCurvedSpokeGear(
      canvas,
      Offset(center.dx - skeletonRadius * 0.42, center.dy - skeletonRadius * 0.05),
      skeletonRadius * 0.29,
      teeth: 18,
      spokes: 4,
      gearColor: const Color(0xFFC87D55),
    );

    // Right Internal Teeth Hub Gear (2-3 o'clock)
    _drawSteampunkMultiRingGear(
      canvas,
      Offset(center.dx + skeletonRadius * 0.38, center.dy - skeletonRadius * 0.24),
      skeletonRadius * 0.25,
      teeth: 14,
      gearColor: const Color(0xFFD99B43),
    );

    // Bottom-Right Copper Balance Gear (4-5 o'clock)
    _drawSteampunkCurvedSpokeGear(
      canvas,
      Offset(center.dx + skeletonRadius * 0.40, center.dy + skeletonRadius * 0.22),
      skeletonRadius * 0.22,
      teeth: 14,
      spokes: 4,
      gearColor: const Color(0xFFB86B3E),
    );

    // Center Main Openwork Gear
    _drawSteampunkSpurGear(
      canvas,
      center,
      skeletonRadius * 0.30,
      teeth: 16,
      spokes: 8,
      gearColor: const Color(0xFFECC875),
    );

    // Bottom 6 o'clock Master Keyhole Gear
    _drawSteampunkKeyholeGear(
      canvas,
      Offset(center.dx, center.dy + skeletonRadius * 0.48),
      skeletonRadius * 0.29,
      teeth: 20,
      gearColor: const Color(0xFFD4AF37),
    );

    // 6. Architectural Crenellated Gunmetal Chapter Ring
    _drawSteampunkCrenellatedChapterRing(canvas, center, radius, skeletonRadius);

    // 7. Skeletonized Gold Lance Hands
    final (hAngle, mAngle, sAngle) = _calculateAngles();

    // Hour Hand (Skeletonized Gold Lance)
    _drawSkeletonLanceHand(
      canvas,
      center,
      hAngle,
      skeletonRadius * 0.54,
      skeletonRadius * 0.09,
      const Color(0xFFECC875),
    );

    // Minute Hand (Longer Skeletonized Gold Lance)
    _drawSkeletonLanceHand(
      canvas,
      center,
      mAngle,
      skeletonRadius * 0.82,
      skeletonRadius * 0.075,
      const Color(0xFFECC875),
    );

    // Center Gold Boss
    canvas.drawCircle(center, radius * 0.060, Paint()..color = const Color(0xFFECC875));
    canvas.drawCircle(
      center,
      radius * 0.060,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFFFFF6DB),
    );
    canvas.drawCircle(center, radius * 0.025, Paint()..color = const Color(0xFF141618));
  }

  // ══════════════════════════════════════════════════════════════
  // 4. GOLDEN SUNBURST & RUBY (MD GROUP) (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintRubySunburstMD(Canvas canvas, Offset center, double radius) {
    // 1. Outer Dark Bronze Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1E140A));

    // 2. Multi-Tiered Sculpted 3D Yellow Gold Bezel
    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.080;

    final goldBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFFFFBE8), // Specular light highlight top-left
          Color(0xFFF6D062),
          Color(0xFFCA9427),
          Color(0xFF6B450C), // Deep bronze shadow bottom-right
          Color(0xFFCA9427),
          Color(0xFFF6D062),
          Color(0xFFFFFBE8),
        ],
        stops: [0.0, 0.22, 0.44, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, goldBezel);

    // Concentric stepped highlights on bezel
    canvas.drawCircle(
      center,
      radius * 0.925,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFFFDF5).withAlpha(180),
    );

    // Inner Polished Gold Rehaut Lip
    final rehautRadius = radius * 0.84;
    canvas.drawCircle(
      center,
      rehautRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFECC565),
    );

    // 4. Amber / Honey Metallic Sunburst Dial Face
    final dialRadius = radius * 0.835;
    final sunburstPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.10, -0.10),
        colors: const [
          Color(0xFFFBAE17), // Radiant center amber gold
          Color(0xFFE28907),
          Color(0xFFB45309),
          Color(0xFF6B2602), // Deep antique dark amber rim
        ],
        stops: const [0.0, 0.40, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, sunburstPaint);

    // Subtle radial satin sheen micro-grooves
    final sheenPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.white.withAlpha(9);
    for (double r = dialRadius * 0.25; r < dialRadius * 0.96; r += 3.5) {
      canvas.drawCircle(center, r, sheenPaint);
    }

    // 5. Embossed Gold "MD GROUP" Emblem (Under 12)
    _drawMDGroupEmblemGold(canvas, Offset(center.dx, center.dy - dialRadius * 0.46), scale: radius * 0.0095);

    // 6. 12 Sparkling Square Cushion-Cut Ruby Gemstones
    final rubyDistance = dialRadius * 0.78;
    for (int i = 0; i < 12; i++) {
      final a = (i * 30) * pi / 180;
      final pos = Offset(center.dx + rubyDistance * sin(a), center.dy - rubyDistance * cos(a));
      // Cardinal hours (12, 3, 6, 9) square alignment; other hours rotated diamond alignment
      final rotation = (i % 3 == 0) ? 0.0 : pi / 4;
      _drawCushionCutRubyMarker(canvas, pos, radius * 0.068, rotation);
    }

    // 7. Luminous Faceted Green Jeweled Hands
    final (hAngle, mAngle, _) = _calculateAngles();

    // Hour Hand
    _drawJeweledGreenDauphineHand(
      canvas,
      center,
      hAngle,
      length: dialRadius * 0.54,
      width: dialRadius * 0.088,
    );

    // Minute Hand
    _drawJeweledGreenDauphineHand(
      canvas,
      center,
      mAngle,
      length: dialRadius * 0.82,
      width: dialRadius * 0.075,
    );

    // Center Gold Boss with Concentric Bevel
    canvas.drawCircle(center, radius * 0.060, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(
      center,
      radius * 0.060,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFFF9E6),
    );
    canvas.drawCircle(center, radius * 0.038, Paint()..color = const Color(0xFF8F6317));
    canvas.drawCircle(center, radius * 0.016, Paint()..color = const Color(0xFF261805));
  }

  // ══════════════════════════════════════════════════════════════
  // 5. MINIMALIST STEALTH BLACK (Row 2, Col 1)
  // ══════════════════════════════════════════════════════════════
  void _paintMinimalistStealth(Canvas canvas, Offset center, double radius) {
    // Matte black dial
    canvas.drawCircle(center, radius - 2, Paint()..color = const Color(0xFF101418));

    // Concentric vinyl grooves
    for (double r = radius * 0.35; r < radius - 8; r += 5.0) {
      canvas.drawCircle(
        center,
        r,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = Colors.white.withAlpha(12),
      );
    }

    // Polished Silver Slender Baton Indices (Double at 12)
    final silverBaton = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.square;

    for (int i = 0; i < 12; i++) {
      final a = (i * 30) * pi / 180;
      final r1 = radius - 6;
      final r2 = radius - 14;

      if (i == 0) {
        // Double baton at 12
        canvas.drawLine(
          Offset(center.dx - 2.5 + r1 * sin(a), center.dy - r1 * cos(a)),
          Offset(center.dx - 2.5 + r2 * sin(a), center.dy - r2 * cos(a)),
          silverBaton,
        );
        canvas.drawLine(
          Offset(center.dx + 2.5 + r1 * sin(a), center.dy - r1 * cos(a)),
          Offset(center.dx + 2.5 + r2 * sin(a), center.dy - r2 * cos(a)),
          silverBaton,
        );
      } else {
        canvas.drawLine(
          Offset(center.dx + r1 * sin(a), center.dy - r1 * cos(a)),
          Offset(center.dx + r2 * sin(a), center.dy - r2 * cos(a)),
          silverBaton,
        );
      }
    }

    // Silver Dauphine Hands
    final (hAngle, mAngle, sAngle) = _calculateAngles();
    _drawDauphineHand(canvas, center, hAngle, radius * 0.48, 4.5, const Color(0xFFCBD5E1));
    _drawDauphineHand(canvas, center, mAngle, radius * 0.72, 3.2, const Color(0xFFCBD5E1));
    _drawSecondNeedle(canvas, center, sAngle, radius * 0.78, const Color(0xFF94A3B8));

    canvas.drawCircle(center, 3.5, Paint()..color = const Color(0xFFE2E8F0));
  }

  // ══════════════════════════════════════════════════════════════
  // ROSE GOLD & STEALTH BLACK (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintRoseGoldBlackSkeleton(Canvas canvas, Offset center, double radius) {
    // 1. Outermost Dark Matte Gunmetal Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF16181B));

    // 4. Multi-Tiered 3D Rounded Tubular Rose Gold / Copper Bezel
    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.082;
    final roseGoldBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFFBE4D5), // Bright specular highlight top-left
          Color(0xFFE89F77),
          Color(0xFFB86641),
          Color(0xFF5E2B16), // Deep bronze/copper shadow bottom-right
          Color(0xFFB86641),
          Color(0xFFE89F77),
          Color(0xFFFBE4D5),
        ],
        stops: [0.0, 0.22, 0.44, 0.58, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, roseGoldBezel);

    // Tubular Convex Highlights
    canvas.drawCircle(
      center,
      radius * 0.928,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFFFF0E6).withAlpha(180),
    );
    canvas.drawCircle(
      center,
      radius * 0.852,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFFFF0E6).withAlpha(150),
    );

    // Inner Recessed Shadow Groove
    canvas.drawCircle(
      center,
      radius * 0.840,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF0E0B09),
    );

    // 5. Flat Velvet Matte Obsidian Black Dial
    final dialRadius = radius * 0.835;
    canvas.drawCircle(center, dialRadius, Paint()..color = const Color(0xFF161719));

    // Subtle inner shadow cast from bezel onto dial
    final innerShadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: [
          Colors.transparent,
          Colors.black.withAlpha(90),
        ],
        stops: const [0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, innerShadow);

    // 6. 3D Rose Gold Arabic Numerals (1 to 12)
    final numerals = {
      12: '12', 1: '1', 2: '2', 3: '3', 4: '4', 5: '5',
      6: '6', 7: '7', 8: '8', 9: '9', 10: '10', 11: '11',
    };
    _drawRoseGoldArabicNumerals(canvas, center, dialRadius * 0.76, numerals, radius * 0.138);

    // 7. Openwork Skeleton Lance / Lozenge Hands in Rose Gold
    final (hAngle, mAngle, sAngle) = _calculateAngles();

    // Hour Hand
    _drawRoseGoldSkeletonLanceHand(
      canvas,
      center,
      hAngle,
      length: dialRadius * 0.50,
      width: dialRadius * 0.125,
    );

    // Minute Hand
    _drawRoseGoldSkeletonLanceHand(
      canvas,
      center,
      mAngle,
      length: dialRadius * 0.76,
      width: dialRadius * 0.10,
    );

    // Second Hand (Straight Slender Rose-Gold Needle)
    _drawRoseGoldSecondNeedle(
      canvas,
      center,
      sAngle,
      length: dialRadius * 0.86,
      tailLength: dialRadius * 0.18,
    );

    // Center Layered Rose-Gold Boss
    canvas.drawCircle(center, radius * 0.055, Paint()..color = const Color(0xFFD48B64));
    canvas.drawCircle(
      center,
      radius * 0.055,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFBE4D5),
    );
    canvas.drawCircle(center, radius * 0.026, Paint()..color = const Color(0xFF7C3B24));
  }

  // ══════════════════════════════════════════════════════════════
  // MOTHER-OF-PEARL MOONPHASE & SECONDS (Curated from user reference image)
  // ══════════════════════════════════════════════════════════════
  void _paintMoonphasePearlGold(Canvas canvas, Offset center, double radius) {
    // 1. Outermost Dark Matte Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF16181B));

    // 2. Outermost Brushed Steel / Silver Ring
    final steelRadius = radius * 0.96;
    final steelPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFE2E8F0),
          Color(0xFF94A3B8),
          Color(0xFF64748B),
          Color(0xFF94A3B8),
          Color(0xFFE2E8F0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: steelRadius));
    canvas.drawCircle(center, steelRadius - radius * 0.025, steelPaint);

    // Outer Silver Highlight Rim
    canvas.drawCircle(
      center,
      radius * 0.955,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFF8FAFC).withAlpha(200),
    );

    // 4. Stepped Sculpted 3D Yellow Gold Bezel
    final goldBezelRadius = radius * 0.875;
    final goldBezelStroke = radius * 0.075;
    final goldBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = goldBezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFFFF8E3), // Specular highlight top-left
          Color(0xFFF3CF68),
          Color(0xFFCA9427),
          Color(0xFF6B450C), // Deep bronze shadow bottom-right
          Color(0xFFCA9427),
          Color(0xFFF3CF68),
          Color(0xFFFFF8E3),
        ],
        stops: [0.0, 0.22, 0.44, 0.58, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: goldBezelRadius));
    canvas.drawCircle(center, goldBezelRadius, goldBezel);

    // Stepped Gold Ridge Highlight
    canvas.drawCircle(
      center,
      radius * 0.912,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFFFFDF5).withAlpha(190),
    );

    // Inner Polished Gold Rehaut Lip
    final rehautRadius = radius * 0.838;
    canvas.drawCircle(
      center,
      rehautRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xFFECC565),
    );

    // 5. Iridescent Mother-of-Pearl (MOP) Dial Face
    final dialRadius = radius * 0.83;
    final mopBase = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.15, -0.15),
        colors: const [
          Color(0xFFFCFAF7),
          Color(0xFFF5EFE4),
          Color(0xFFE8E0D2),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, mopBase);

    // Soft shimmering pearl clouds
    final pinkPearl = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, 0.25),
        colors: [const Color(0xFFFCE7F3).withAlpha(45), Colors.transparent],
        radius: 0.65,
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, pinkPearl);

    final mintPearl = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.40, -0.30),
        colors: [const Color(0xFFECFDF5).withAlpha(45), Colors.transparent],
        radius: 0.60,
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, mintPearl);

    // Inner dial subtle shadow from gold rehaut
    final innerDialShadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: [Colors.transparent, Colors.black.withAlpha(45)],
        stops: const [0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, innerDialShadow);

    // 6. Perimeter Minute Track with Gold Batons & Graduation Ticks
    for (int i = 0; i < 60; i++) {
      final a = (i * 6) * pi / 180;
      final isHour = (i % 5 == 0);

      if (isHour) {
        // Gold rectangular hour baton
        final r1 = dialRadius * 0.89;
        final r2 = dialRadius * 0.94;
        canvas.drawLine(
          Offset(center.dx + r1 * sin(a), center.dy - r1 * cos(a)),
          Offset(center.dx + r2 * sin(a), center.dy - r2 * cos(a)),
          Paint()..color = const Color(0xFFC89B2B)..strokeWidth = 1.9..strokeCap = StrokeCap.square,
        );
      } else {
        // Fine dark minute tick
        final r1 = dialRadius * 0.91;
        final r2 = dialRadius * 0.94;
        canvas.drawLine(
          Offset(center.dx + r1 * sin(a), center.dy - r1 * cos(a)),
          Offset(center.dx + r2 * sin(a), center.dy - r2 * cos(a)),
          Paint()..color = const Color(0xFF475569)..strokeWidth = 0.75..strokeCap = StrokeCap.square,
        );
      }
    }

    // 7. Classical Gold Arabic Numerals (1 to 12, omitting 6 for sub-dial)
    final pearlNumerals = {
      12: '12', 1: '1', 2: '2', 3: '3', 4: '4', 5: '5',
      7: '7', 8: '8', 9: '9', 10: '10', 11: '11',
    };
    _drawPearlGoldArabicNumerals(canvas, center, dialRadius * 0.74, pearlNumerals, radius * 0.125);

    // 8. Top Celestial Moonphase Aperture Complication (under 12)
    _drawMoonphaseAperture(canvas, Offset(center.dx, center.dy - dialRadius * 0.28), dialRadius);

    // 9. Bottom Running Seconds Sub-Dial Complication (at 6 o'clock)
    _drawRunningSecondsSubDial(canvas, Offset(center.dx, center.dy + dialRadius * 0.44), dialRadius * 0.27);

    // 10. Sage Green Dauphine-Leaf Main Hands
    final (hAngle, mAngle, _) = _calculateAngles();

    // Hour Hand
    _drawSageGreenDauphineHand(
      canvas,
      center,
      hAngle,
      length: dialRadius * 0.50,
      width: dialRadius * 0.088,
    );

    // Minute Hand
    _drawSageGreenDauphineHand(
      canvas,
      center,
      mAngle,
      length: dialRadius * 0.78,
      width: dialRadius * 0.075,
    );

    // Center Jade Green Boss with Inner Gold Dot
    canvas.drawCircle(center, radius * 0.052, Paint()..color = const Color(0xFF385C3B));
    canvas.drawCircle(
      center,
      radius * 0.052,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFF7CB380),
    );
    canvas.drawCircle(center, radius * 0.020, Paint()..color = const Color(0xFFD4AF37));
  }
  // ══════════════════════════════════════════════════════════════
  void _paintMilitaryChronoMD(Canvas canvas, Offset center, double radius) {
    // 1. Outermost Industrial Gunmetal Circular Casing
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF141618));

    // 2. Multi-Tiered Industrial Gunmetal Bezel
    final bezelMidRadius = radius * 0.89;
    final bezelStroke = radius * 0.075;

    final gunmetalBezel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bezelStroke
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFF555D68), // Specular light highlight top-left
          Color(0xFF32373E),
          Color(0xFF1C1F24),
          Color(0xFF101214), // Deep shadow bottom-right
          Color(0xFF1C1F24),
          Color(0xFF32373E),
          Color(0xFF555D68),
        ],
        stops: [0.0, 0.22, 0.44, 0.56, 0.76, 0.92, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: bezelMidRadius));
    canvas.drawCircle(center, bezelMidRadius, gunmetalBezel);

    // Concentric stepped highlights
    canvas.drawCircle(
      center,
      radius * 0.925,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF6B7280).withAlpha(140),
    );

    // Inner Bezel Rehaut Lip
    final rehautRadius = radius * 0.84;
    canvas.drawCircle(
      center,
      rehautRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF374151),
    );

    // 4. Matte Velvet Obsidian Black Dial
    final dialRadius = radius * 0.835;
    canvas.drawCircle(center, dialRadius, Paint()..color = const Color(0xFF121417));

    // 5. Perimeter Tick Track & Cardinal Lume Bars
    final tickPaint = Paint()
      ..color = const Color(0xFFE5DECE).withAlpha(200)
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.square;

    final majorTickPaint = Paint()
      ..color = const Color(0xFFFFF7DF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.square;

    for (int i = 0; i < 60; i++) {
      final a = (i * 6) * pi / 180;
      final isMajor = (i % 5 == 0);
      final rStart = isMajor ? dialRadius * 0.89 : dialRadius * 0.92;
      final rEnd = dialRadius * 0.96;

      canvas.drawLine(
        Offset(center.dx + rStart * sin(a), center.dy - rStart * cos(a)),
        Offset(center.dx + rEnd * sin(a), center.dy - rEnd * cos(a)),
        isMajor ? majorTickPaint : tickPaint,
      );
    }

    // Inner dial subtle shadow from top-left rehaut
    final innerShadow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: [
          Colors.transparent,
          Colors.black.withAlpha(80),
        ],
        stops: const [0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: dialRadius));
    canvas.drawCircle(center, dialRadius, innerShadow);

    // Cardinal Rectangular Luminous Bars (12, 3, 6, 9) - Matching Reference Photo
    final barW = radius * 0.034;
    final barH = radius * 0.082;
    final barPaint = Paint()..color = const Color(0xFFEDE2CC);
    final barShadow = Paint()..color = Colors.black.withAlpha(140);

    void drawCardinalBar(Offset pos, {bool isDouble = false, bool isHorizontal = false}) {
      final w = isHorizontal ? barH : barW;
      final h = isHorizontal ? barW : barH;

      if (isDouble) {
        final r1 = Rect.fromCenter(center: Offset(pos.dx - barW * 0.75, pos.dy), width: barW * 0.70, height: barH);
        final r2 = Rect.fromCenter(center: Offset(pos.dx + barW * 0.75, pos.dy), width: barW * 0.70, height: barH);
        canvas.drawRect(r1.shift(const Offset(0.6, 0.8)), barShadow);
        canvas.drawRect(r2.shift(const Offset(0.6, 0.8)), barShadow);
        canvas.drawRect(r1, barPaint);
        canvas.drawRect(r2, barPaint);
      } else {
        final r = Rect.fromCenter(center: pos, width: w, height: h);
        canvas.drawRect(r.shift(const Offset(0.6, 0.8)), barShadow);
        canvas.drawRect(r, barPaint);
      }
    }

    drawCardinalBar(Offset(center.dx, center.dy - dialRadius * 0.86), isDouble: true); // 12 (double vertical)
    drawCardinalBar(Offset(center.dx + dialRadius * 0.86, center.dy), isHorizontal: true); // 3 (horizontal)
    drawCardinalBar(Offset(center.dx, center.dy + dialRadius * 0.86)); // 6 (vertical)
    drawCardinalBar(Offset(center.dx - dialRadius * 0.86, center.dy), isHorizontal: true); // 9 (horizontal)

    // 6. Prominent Arabic Numerals: 12, 1, 2, 4, 5, 7, 8, 10, 11
    final numerals = {
      12: '12',
      1: '1',
      2: '2',
      4: '4',
      5: '5',
      7: '7',
      8: '8',
      10: '10',
      11: '11',
    };
    _drawAviatorNumerals(canvas, center, dialRadius * 0.74, numerals, radius * 0.115);

    // 7. Distinctive "MD GROUP" Emblem (Under 12)
    _drawMDGroupEmblemWhite(canvas, Offset(center.dx, center.dy - dialRadius * 0.44), scale: radius * 0.0092);

    // 8. The Three Tri-Compax Chronograph Sub-Dials
    final subRadius = dialRadius * 0.28;

    // Left Sub-Dial (9 o'clock): Gauge Instrument with Lower-Half Cutout Aperture & Orange Pointer
    _drawChronoApertureSubDial(canvas, Offset(center.dx - dialRadius * 0.45, center.dy), subRadius);

    // Right Sub-Dial (3 o'clock): 30-Minute Counter with numbers 20 & 16, and top crown glyph
    _drawChrono30MinSubDial(canvas, Offset(center.dx + dialRadius * 0.45, center.dy), subRadius);

    // Bottom Sub-Dial (6 o'clock): 12-Hour Counter with numbers 8, 6, 4, 12
    _drawChrono12HourSubDial(canvas, Offset(center.dx, center.dy + dialRadius * 0.45), subRadius);

    // 9. Main Hands
    final (hAngle, mAngle, sAngle) = _calculateAngles();

    // Hour Hand (Aviator Sword Hand)
    _drawAviatorSwordHand(
      canvas,
      center,
      hAngle,
      length: dialRadius * 0.50,
      width: dialRadius * 0.095,
      lumeColor: const Color(0xFFD2DDD0),
    );

    // Minute Hand (Longer Aviator Sword Hand)
    _drawAviatorSwordHand(
      canvas,
      center,
      mAngle,
      length: dialRadius * 0.76,
      width: dialRadius * 0.082,
      lumeColor: const Color(0xFFD2DDD0),
    );

    // Chronograph Sweep Seconds Hand (Slender rose-gold needle with luminous bar)
    _drawChronoSweepSecondHand(
      canvas,
      center,
      sAngle,
      length: dialRadius * 0.85,
      tailLength: dialRadius * 0.20,
    );

    // Layered Gunmetal Center Pinion Boss
    canvas.drawCircle(center, radius * 0.055, Paint()..color = const Color(0xFF232830));
    canvas.drawCircle(
      center,
      radius * 0.055,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF4B5563),
    );
    canvas.drawCircle(center, radius * 0.024, Paint()..color = const Color(0xFF0F1114));
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER DRAWING METHODS
  // ══════════════════════════════════════════════════════════════

  (double, double, double) _calculateAngles() {
    final hour = dateTime.hour;
    final minute = dateTime.minute;
    final second = dateTime.second;
    final millisecond = dateTime.millisecond;

    final smoothSecond = second + millisecond / 1000.0;
    final smoothMinute = minute + smoothSecond / 60.0;
    final smoothHour = (hour % 12) + smoothMinute / 60.0;

    final hourAngle = smoothHour * 30 * pi / 180;
    final minuteAngle = smoothMinute * 6 * pi / 180;
    final secondAngle = smoothSecond * 6 * pi / 180;

    return (hourAngle, minuteAngle, secondAngle);
  }



  void _drawDauphineHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final leftPath = Path()..moveTo(0, 6)..lineTo(-width, -length * 0.35)..lineTo(0, -length)..close();
    canvas.drawPath(leftPath, Paint()..color = Color.lerp(color, Colors.white, 0.25)!);

    final rightPath = Path()..moveTo(0, 6)..lineTo(width, -length * 0.35)..lineTo(0, -length)..close();
    canvas.drawPath(rightPath, Paint()..color = Color.lerp(color, Colors.black, 0.25)!);

    canvas.restore();
  }


  void _drawSecondNeedle(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    Color color,
  ) {
    final tip = Offset(center.dx + length * sin(angle), center.dy - length * cos(angle));
    final tail = Offset(center.dx - 12 * sin(angle), center.dy + 12 * cos(angle));
    canvas.drawLine(tail, tip, Paint()..color = color..strokeWidth = 1.4..strokeCap = StrokeCap.round);
  }

  void _drawWalnutRomanDauphineHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width, {
    required Color lightColor,
    required Color darkColor,
    required Color spineColor,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Hand drop shadow onto dial
    final shadowPath = Path()
      ..moveTo(0, 5)
      ..lineTo(-width, -length * 0.26)
      ..lineTo(0, -length)
      ..lineTo(width, -length * 0.26)
      ..close();
    canvas.drawPath(
      shadowPath.shift(const Offset(1.0, 1.4)),
      Paint()
        ..color = Colors.black.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );

    // Light illuminated half (left)
    final leftPath = Path()
      ..moveTo(0, 5)
      ..lineTo(-width, -length * 0.26)
      ..lineTo(0, -length)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = lightColor);

    // Dark shaded half (right)
    final rightPath = Path()
      ..moveTo(0, 5)
      ..lineTo(width, -length * 0.26)
      ..lineTo(0, -length)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = darkColor);

    // Crisp center spine line
    canvas.drawLine(
      const Offset(0, 4),
      Offset(0, -length + 1),
      Paint()
        ..color = spineColor
        ..strokeWidth = 0.65
        ..style = PaintingStyle.stroke,
    );

    canvas.restore();
  }

  void _drawWalnutRomanSecondHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double tailLength,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Soft drop shadow
    canvas.drawLine(
      Offset(0.8, tailLength + 0.8),
      Offset(0.8, -length + 0.8),
      Paint()
        ..color = Colors.black.withAlpha(80)
        ..strokeWidth = 1.0,
    );

    // Needle from rear tail to tip
    final needlePaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.95;
    canvas.drawLine(Offset(0, tailLength), Offset(0, -length), needlePaint);

    // Small counterweight disc on tail
    canvas.drawCircle(Offset(0, tailLength * 0.55), 1.6, Paint()..color = color);

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: EMERALD LEAF & CODE </>
  // ══════════════════════════════════════════════════════════════
  void _drawEmeraldJeweledLeaf(Canvas canvas, Offset center, double dialRadius) {
    final topY = center.dy - dialRadius * 0.48;
    final botY = center.dy + dialRadius * 0.46;
    final leafHeight = botY - topY;
    final leafHalfW = dialRadius * 0.38;

    // Drop shadow under the leaf
    final shadowPath = Path()
      ..moveTo(center.dx, topY)
      ..cubicTo(
        center.dx + leafHalfW, topY + leafHeight * 0.28,
        center.dx + leafHalfW * 0.90, botY - leafHeight * 0.25,
        center.dx, botY,
      )
      ..cubicTo(
        center.dx - leafHalfW * 0.90, botY - leafHeight * 0.25,
        center.dx - leafHalfW, topY + leafHeight * 0.28,
        center.dx, topY,
      )
      ..close();

    canvas.drawPath(
      shadowPath.shift(const Offset(1.5, 2.0)),
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );

    // 1. Embossed Polished Gold Outer Leaf Border
    final goldBorderPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFF6DF), // Bright gold highlight
          Color(0xFFE5BE5E),
          Color(0xFF9E7022),
          Color(0xFFE5BE5E),
          Color(0xFFFFF6DF),
        ],
      ).createShader(Rect.fromLTWH(center.dx - leafHalfW, topY, leafHalfW * 2, leafHeight));

    canvas.drawPath(shadowPath, goldBorderPaint);

    // 2. Dark Rich Emerald Inner Leaf Bed
    final innerHalfW = leafHalfW * 0.88;
    final innerTopY = topY + dialRadius * 0.035;
    final innerBotY = botY - dialRadius * 0.030;
    final innerH = innerBotY - innerTopY;

    final innerLeafPath = Path()
      ..moveTo(center.dx, innerTopY)
      ..cubicTo(
        center.dx + innerHalfW, innerTopY + innerH * 0.28,
        center.dx + innerHalfW * 0.90, innerBotY - innerH * 0.25,
        center.dx, innerBotY,
      )
      ..cubicTo(
        center.dx - innerHalfW * 0.90, innerBotY - innerH * 0.25,
        center.dx - innerHalfW, innerTopY + innerH * 0.28,
        center.dx, innerTopY,
      )
      ..close();

    final innerEmeraldPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.2),
        colors: const [
          Color(0xFF045838), // Center luminous emerald
          Color(0xFF023220),
          Color(0xFF011C12), // Deep shadow inside bevel
        ],
      ).createShader(Rect.fromLTWH(center.dx - innerHalfW, innerTopY, innerHalfW * 2, innerH));
    canvas.drawPath(innerLeafPath, innerEmeraldPaint);

    // 3. Central Gold Spine / Midrib Vein
    final spinePaint = Paint()
      ..color = const Color(0xFFECC875)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx, innerBotY - 2),
      Offset(center.dx, innerTopY + 4),
      spinePaint,
    );

    // 4. Symmetrical Branching Lateral Veins (4 pairs)
    final veinPaint = Paint()
      ..color = const Color(0xFFECC875).withAlpha(220)
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final veinFractions = [0.20, 0.40, 0.60, 0.78];
    for (int idx = 0; idx < veinFractions.length; idx++) {
      final frac = veinFractions[idx];
      final yAnchor = innerBotY - innerH * frac;
      final yEnd = yAnchor - innerH * 0.13;
      final xSpan = innerHalfW * (1.0 - (frac - 0.5).abs() * 0.95);

      // Right lateral vein
      final rightVein = Path()
        ..moveTo(center.dx, yAnchor)
        ..quadraticBezierTo(
          center.dx + xSpan * 0.5, yAnchor - innerH * 0.04,
          center.dx + xSpan * 0.82, yEnd,
        );
      canvas.drawPath(rightVein, veinPaint);

      // Left lateral vein
      final leftVein = Path()
        ..moveTo(center.dx, yAnchor)
        ..quadraticBezierTo(
          center.dx - xSpan * 0.5, yAnchor - innerH * 0.04,
          center.dx - xSpan * 0.82, yEnd,
        );
      canvas.drawPath(leftVein, veinPaint);
    }

    // 5. Crystalline Emerald & Diamond Sparkle Studs inside leaf
    final crystalPaint = Paint()..style = PaintingStyle.fill;
    final crystalOffsets = [
      Offset(center.dx - leafHalfW * 0.35, center.dy - dialRadius * 0.18),
      Offset(center.dx + leafHalfW * 0.35, center.dy - dialRadius * 0.18),
      Offset(center.dx - leafHalfW * 0.45, center.dy),
      Offset(center.dx + leafHalfW * 0.45, center.dy),
      Offset(center.dx - leafHalfW * 0.32, center.dy + dialRadius * 0.18),
      Offset(center.dx + leafHalfW * 0.32, center.dy + dialRadius * 0.18),
      Offset(center.dx - leafHalfW * 0.20, center.dy - dialRadius * 0.30),
      Offset(center.dx + leafHalfW * 0.20, center.dy - dialRadius * 0.30),
    ];

    for (final pt in crystalOffsets) {
      crystalPaint.color = const Color(0xFF6EE7B7).withAlpha(180);
      canvas.drawCircle(pt, 2.4, crystalPaint);
      crystalPaint.color = Colors.white;
      canvas.drawCircle(Offset(pt.dx - 0.4, pt.dy - 0.4), 0.9, crystalPaint);
    }
  }

  void _drawCodeBracketMarker(
    Canvas canvas,
    Offset pos, {
    required bool isVertical,
    required double scale,
  }) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    final goldStroke = Paint()
      ..color = const Color(0xFFECC875)
      ..strokeWidth = 1.8 * (scale / 1.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final shadowStroke = Paint()
      ..color = Colors.black.withAlpha(130)
      ..strokeWidth = 1.8 * (scale / 1.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    void drawSymbolGroup(double dx, double dy) {
      final s = scale * 0.9;
      // <
      final openBracket = Path()
        ..moveTo(dx - s * 2.8, dy - s * 1.5)
        ..lineTo(dx - s * 4.2, dy)
        ..lineTo(dx - s * 2.8, dy + s * 1.5);

      // /
      final slash = Path()
        ..moveTo(dx + s * 0.8, dy - s * 1.7)
        ..lineTo(dx - s * 0.8, dy + s * 1.7);

      // >
      final closeBracket = Path()
        ..moveTo(dx + s * 2.8, dy - s * 1.5)
        ..lineTo(dx + s * 4.2, dy)
        ..lineTo(dx + s * 2.8, dy + s * 1.5);

      canvas.drawPath(openBracket, dx != 0 ? shadowStroke : goldStroke);
      canvas.drawPath(slash, dx != 0 ? shadowStroke : goldStroke);
      canvas.drawPath(closeBracket, dx != 0 ? shadowStroke : goldStroke);
    }

    // Shadow
    drawSymbolGroup(0.7, 0.9);
    // Fore
    drawSymbolGroup(0.0, 0.0);

    canvas.restore();
  }

  void _drawEmeraldLeafSecondHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double tailLength,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withAlpha(100)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(1.0, tailLength + 1.0), Offset(1.0, -length + 1.0), shadowPaint);

    // Main needle
    final needlePaint = Paint()
      ..color = color
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, tailLength), Offset(0, -length), needlePaint);

    // Rectangular counterweight bar located between center and tail
    final barW = 2.4;
    final barH = tailLength * 0.55;
    final barTopY = tailLength * 0.30;
    final barRect = Rect.fromLTWH(-barW / 2, barTopY, barW, barH);

    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(0.8)),
      Paint()..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = const Color(0xFFFFF1E0),
    );

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: STEAMPUNK GEARS SKELETON
  // ══════════════════════════════════════════════════════════════
  void _drawSteampunkJeweledBridges(Canvas canvas, Offset center, double skeletonRadius) {
    final bridgePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF3E434D),
          Color(0xFF262A30),
          Color(0xFF1B1E22),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: skeletonRadius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Curved bridge 1 across upper left
    final bridge1 = Path()
      ..moveTo(center.dx - skeletonRadius * 0.70, center.dy - skeletonRadius * 0.20)
      ..cubicTo(
        center.dx - skeletonRadius * 0.35, center.dy - skeletonRadius * 0.65,
        center.dx + skeletonRadius * 0.20, center.dy - skeletonRadius * 0.55,
        center.dx + skeletonRadius * 0.60, center.dy - skeletonRadius * 0.15,
      );
    bridgePaint.strokeWidth = skeletonRadius * 0.11;
    canvas.drawPath(bridge1, bridgePaint);

    // Jewel bearing in bridge 1 (ruby jewel)
    final jewelPt1 = Offset(center.dx - skeletonRadius * 0.20, center.dy - skeletonRadius * 0.45);
    _drawJewelBearing(canvas, jewelPt1, skeletonRadius * 0.038, const Color(0xFFBE123C));

    // Curved bridge 2 across lower right
    final bridge2 = Path()
      ..moveTo(center.dx - skeletonRadius * 0.30, center.dy + skeletonRadius * 0.40)
      ..cubicTo(
        center.dx, center.dy + skeletonRadius * 0.25,
        center.dx + skeletonRadius * 0.45, center.dy + skeletonRadius * 0.40,
        center.dx + skeletonRadius * 0.65, center.dy + skeletonRadius * 0.10,
      );
    bridgePaint.strokeWidth = skeletonRadius * 0.09;
    canvas.drawPath(bridge2, bridgePaint);

    // Jewel bearing in bridge 2 (ruby jewel)
    final jewelPt2 = Offset(center.dx + skeletonRadius * 0.30, center.dy + skeletonRadius * 0.32);
    _drawJewelBearing(canvas, jewelPt2, skeletonRadius * 0.034, const Color(0xFFBE123C));
  }

  void _drawJewelBearing(Canvas canvas, Offset center, double radius, Color jewelColor) {
    // Polished gold chaton (bushing)
    canvas.drawCircle(center, radius * 1.5, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(
      center,
      radius * 1.5,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = const Color(0xFFFFF6DB),
    );
    // Gemstone center
    canvas.drawCircle(center, radius, Paint()..color = jewelColor);
    // Specular shine
    canvas.drawCircle(Offset(center.dx - radius * 0.3, center.dy - radius * 0.3), radius * 0.3, Paint()..color = Colors.white70);
  }

  void _drawSteampunkSpurGear(
    Canvas canvas,
    Offset cogCenter,
    double cogR, {
    required int teeth,
    required int spokes,
    required Color gearColor,
  }) {
    canvas.save();
    canvas.translate(cogCenter.dx, cogCenter.dy);

    final toothDepth = cogR * 0.16;
    final rimOuterR = cogR;
    final rimInnerR = cogR * 0.74;
    final hubR = cogR * 0.26;

    final gearPath = Path();
    for (int i = 0; i < teeth; i++) {
      final angleStep = (2 * pi) / teeth;
      final a0 = i * angleStep;
      final a1 = a0 + angleStep * 0.25;
      final a2 = a0 + angleStep * 0.65;
      final a3 = a0 + angleStep * 0.90;

      final rBase = rimOuterR - toothDepth;
      final rTip = rimOuterR;

      if (i == 0) {
        gearPath.moveTo(rBase * cos(a0), rBase * sin(a0));
      } else {
        gearPath.lineTo(rBase * cos(a0), rBase * sin(a0));
      }
      gearPath.lineTo(rTip * cos(a1), rTip * sin(a1));
      gearPath.lineTo(rTip * cos(a2), rTip * sin(a2));
      gearPath.lineTo(rBase * cos(a3), rBase * sin(a3));
    }
    gearPath.close();

    // Drop shadow
    canvas.drawPath(
      gearPath.shift(const Offset(1.2, 1.6)),
      Paint()
        ..color = Colors.black.withAlpha(120)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Shaded metallic gear body
    final gearPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(gearColor, Colors.white, 0.25)!,
          gearColor,
          Color.lerp(gearColor, Colors.black, 0.35)!,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: cogR));
    canvas.drawPath(gearPath, gearPaint);

    // Recessed hole inside the rim
    canvas.drawCircle(Offset.zero, rimInnerR, Paint()..color = const Color(0xFF0A0C0E));

    // Spokes
    final spokePaint = Paint()
      ..color = gearColor
      ..strokeWidth = cogR * 0.12
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < spokes; i++) {
      final a = i * (2 * pi / spokes);
      canvas.drawLine(
        Offset(hubR * cos(a), hubR * sin(a)),
        Offset(rimInnerR * cos(a), rimInnerR * sin(a)),
        spokePaint,
      );
    }

    // Central hub & brass rivet
    canvas.drawCircle(Offset.zero, hubR, Paint()..color = gearColor);
    canvas.drawCircle(
      Offset.zero,
      hubR,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = const Color(0xFFFFF6DB),
    );
    canvas.drawCircle(Offset.zero, hubR * 0.45, Paint()..color = const Color(0xFF1F2429));

    canvas.restore();
  }

  void _drawSteampunkCurvedSpokeGear(
    Canvas canvas,
    Offset cogCenter,
    double cogR, {
    required int teeth,
    required int spokes,
    required Color gearColor,
  }) {
    canvas.save();
    canvas.translate(cogCenter.dx, cogCenter.dy);

    final toothDepth = cogR * 0.14;
    final rimOuterR = cogR;
    final rimInnerR = cogR * 0.76;
    final hubR = cogR * 0.24;

    final gearPath = Path();
    for (int i = 0; i < teeth; i++) {
      final angleStep = (2 * pi) / teeth;
      final a0 = i * angleStep;
      final a1 = a0 + angleStep * 0.25;
      final a2 = a0 + angleStep * 0.65;
      final a3 = a0 + angleStep * 0.90;

      final rBase = rimOuterR - toothDepth;
      final rTip = rimOuterR;

      if (i == 0) {
        gearPath.moveTo(rBase * cos(a0), rBase * sin(a0));
      } else {
        gearPath.lineTo(rBase * cos(a0), rBase * sin(a0));
      }
      gearPath.lineTo(rTip * cos(a1), rTip * sin(a1));
      gearPath.lineTo(rTip * cos(a2), rTip * sin(a2));
      gearPath.lineTo(rBase * cos(a3), rBase * sin(a3));
    }
    gearPath.close();

    // Drop shadow
    canvas.drawPath(
      gearPath.shift(const Offset(1.2, 1.5)),
      Paint()..color = Colors.black.withAlpha(120)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Solid gear rim
    canvas.drawPath(gearPath, Paint()..color = gearColor);
    canvas.drawCircle(Offset.zero, rimInnerR, Paint()..color = const Color(0xFF0A0C0E));

    // Curved spiral spokes
    final spokePaint = Paint()
      ..color = gearColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = cogR * 0.10
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < spokes; i++) {
      final startAngle = i * (2 * pi / spokes);
      final endAngle = startAngle + pi / 3.0;

      final startPt = Offset(hubR * cos(startAngle), hubR * sin(startAngle));
      final endPt = Offset(rimInnerR * cos(endAngle), rimInnerR * sin(endAngle));
      final controlPt = Offset(
        cogR * 0.55 * cos(startAngle + pi / 6.0),
        cogR * 0.55 * sin(startAngle + pi / 6.0),
      );

      final curve = Path()
        ..moveTo(startPt.dx, startPt.dy)
        ..quadraticBezierTo(controlPt.dx, controlPt.dy, endPt.dx, endPt.dy);
      canvas.drawPath(curve, spokePaint);
    }

    // Hub
    canvas.drawCircle(Offset.zero, hubR, Paint()..color = gearColor);
    canvas.drawCircle(Offset.zero, hubR * 0.40, Paint()..color = const Color(0xFF15181B));

    canvas.restore();
  }

  void _drawSteampunkMultiRingGear(
    Canvas canvas,
    Offset cogCenter,
    double cogR, {
    required int teeth,
    required Color gearColor,
  }) {
    canvas.save();
    canvas.translate(cogCenter.dx, cogCenter.dy);

    final toothDepth = cogR * 0.15;
    final gearPath = Path();
    for (int i = 0; i < teeth; i++) {
      final angleStep = (2 * pi) / teeth;
      final a0 = i * angleStep;
      final a1 = a0 + angleStep * 0.3;
      final a2 = a0 + angleStep * 0.7;
      final a3 = a0 + angleStep * 0.95;

      final rBase = cogR - toothDepth;
      final rTip = cogR;

      if (i == 0) {
        gearPath.moveTo(rBase * cos(a0), rBase * sin(a0));
      } else {
        gearPath.lineTo(rBase * cos(a0), rBase * sin(a0));
      }
      gearPath.lineTo(rTip * cos(a1), rTip * sin(a1));
      gearPath.lineTo(rTip * cos(a2), rTip * sin(a2));
      gearPath.lineTo(rBase * cos(a3), rBase * sin(a3));
    }
    gearPath.close();

    canvas.drawPath(
      gearPath.shift(const Offset(1.2, 1.5)),
      Paint()..color = Colors.black.withAlpha(120)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );
    canvas.drawPath(gearPath, Paint()..color = gearColor);

    // Concentric machined grooves
    canvas.drawCircle(
      Offset.zero,
      cogR * 0.75,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0..color = const Color(0xFF1B1E22),
    );
    canvas.drawCircle(
      Offset.zero,
      cogR * 0.55,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFFFFF6DB).withAlpha(140),
    );

    // 6 circular cutout holes
    for (int i = 0; i < 6; i++) {
      final a = i * (2 * pi / 6);
      final holeCenter = Offset(cogR * 0.50 * cos(a), cogR * 0.50 * sin(a));
      canvas.drawCircle(holeCenter, cogR * 0.12, Paint()..color = const Color(0xFF0A0C0E));
    }

    // Center pivot
    canvas.drawCircle(Offset.zero, cogR * 0.22, Paint()..color = const Color(0xFFC87D55));
    canvas.drawCircle(Offset.zero, cogR * 0.10, Paint()..color = const Color(0xFF15181B));

    canvas.restore();
  }

  void _drawSteampunkKeyholeGear(
    Canvas canvas,
    Offset cogCenter,
    double cogR, {
    required int teeth,
    required Color gearColor,
  }) {
    canvas.save();
    canvas.translate(cogCenter.dx, cogCenter.dy);

    final toothDepth = cogR * 0.14;
    final gearPath = Path();
    for (int i = 0; i < teeth; i++) {
      final angleStep = (2 * pi) / teeth;
      final a0 = i * angleStep;
      final a1 = a0 + angleStep * 0.28;
      final a2 = a0 + angleStep * 0.68;
      final a3 = a0 + angleStep * 0.92;

      final rBase = cogR - toothDepth;
      final rTip = cogR;

      if (i == 0) {
        gearPath.moveTo(rBase * cos(a0), rBase * sin(a0));
      } else {
        gearPath.lineTo(rBase * cos(a0), rBase * sin(a0));
      }
      gearPath.lineTo(rTip * cos(a1), rTip * sin(a1));
      gearPath.lineTo(rTip * cos(a2), rTip * sin(a2));
      gearPath.lineTo(rBase * cos(a3), rBase * sin(a3));
    }
    gearPath.close();

    // Drop shadow
    canvas.drawPath(
      gearPath.shift(const Offset(1.2, 1.8)),
      Paint()..color = Colors.black.withAlpha(140)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Metallic Brass Gear Face
    final facePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFFFF4D4),
          gearColor,
          const Color(0xFF9E7022),
          gearColor,
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: cogR));
    canvas.drawPath(gearPath, facePaint);

    // Beveled concentric rim
    canvas.drawCircle(
      Offset.zero,
      cogR * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF785112),
    );
    canvas.drawCircle(
      Offset.zero,
      cogR * 0.75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFFF5D9).withAlpha(180),
    );

    // 4 Bolt rivets on the face
    for (int i = 0; i < 4; i++) {
      final a = (i * pi / 2) + pi / 4;
      final rvt = Offset(cogR * 0.60 * cos(a), cogR * 0.60 * sin(a));
      canvas.drawCircle(rvt, cogR * 0.05, Paint()..color = const Color(0xFF573E11));
      canvas.drawCircle(rvt, cogR * 0.04, Paint()..color = const Color(0xFFE5BF62));
    }

    // ── THE ANTIQUE BLACK KEYHOLE ──
    final keyholeR = cogR * 0.22;
    final keyholeH = cogR * 0.34;
    final keyholeTopY = -cogR * 0.16;

    final keyholePath = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, keyholeTopY), radius: keyholeR));

    // Trapezoid slot widening towards bottom
    final slotPath = Path()
      ..moveTo(-keyholeR * 0.65, keyholeTopY + keyholeR * 0.4)
      ..lineTo(-keyholeR * 0.90, keyholeTopY + keyholeH)
      ..lineTo(keyholeR * 0.90, keyholeTopY + keyholeH)
      ..lineTo(keyholeR * 0.65, keyholeTopY + keyholeR * 0.4)
      ..close();

    keyholePath.addPath(slotPath, Offset.zero);

    // Keyhole depth shadow / inner bevel
    canvas.drawPath(
      keyholePath.shift(const Offset(-0.8, -0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF422C0A),
    );
    canvas.drawPath(
      keyholePath.shift(const Offset(0.8, 0.8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFFFF6DF).withAlpha(160),
    );

    // Deep antique black void
    canvas.drawPath(keyholePath, Paint()..color = const Color(0xFF08090B));

    canvas.restore();
  }

  void _drawSteampunkCrenellatedChapterRing(
    Canvas canvas,
    Offset center,
    double radius,
    double skeletonRadius,
  ) {
    final ringOuterR = radius * 0.86;
    final ringInnerR = skeletonRadius;

    // Outer subtle gold accent ring
    canvas.drawCircle(
      center,
      ringOuterR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFD4AF37),
    );

    // Industrial Rivet Bolts along perimeter
    final rivetPaint = Paint()..color = const Color(0xFFECC875);
    final rivetCap = Paint()..color = const Color(0xFF33383F);
    for (int i = 0; i < 24; i++) {
      final a = i * (2 * pi / 24);
      final rvtPos = Offset(center.dx + (ringOuterR - 3.5) * cos(a), center.dy + (ringOuterR - 3.5) * sin(a));
      canvas.drawCircle(rvtPos, 1.4, rivetPaint);
      canvas.drawCircle(rvtPos, 0.7, rivetCap);
    }

    // Crenellated Hour Indices
    for (int hour = 1; hour <= 12; hour++) {
      final a = (hour * 30) * pi / 180;
      final isCardinal = (hour % 3 == 0);

      if (isCardinal) {
        // Stepped crenellated cutout with fluted gold columns
        final isTriple = (hour == 12 || hour == 6);
        final colCount = isTriple ? 3 : 2;
        final colSpacing = 3.4;

        final centerColPos = Offset(
          center.dx + (ringOuterR - 10.0) * sin(a),
          center.dy - (ringOuterR - 10.0) * cos(a),
        );

        canvas.save();
        canvas.translate(centerColPos.dx, centerColPos.dy);
        canvas.rotate(a);

        final colH = (ringOuterR - ringInnerR) * 0.78;
        final colW = 2.0;

        for (int c = 0; c < colCount; c++) {
          final offsetX = (c - (colCount - 1) / 2.0) * colSpacing;
          final colRect = Rect.fromCenter(center: Offset(offsetX, 0), width: colW, height: colH);

          // Shadow
          canvas.drawRect(
            colRect.shift(const Offset(0.8, 1.0)),
            Paint()..color = Colors.black.withAlpha(150),
          );

          // Fluted gold column gradient
          final colPaint = Paint()
            ..shader = const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFFFFF3D4),
                Color(0xFFE5BE5E),
                Color(0xFF9E7022),
              ],
            ).createShader(colRect);
          canvas.drawRect(colRect, colPaint);

          // Column capital & base caps
          canvas.drawRect(
            Rect.fromCenter(center: Offset(offsetX, -colH / 2), width: colW + 1.0, height: 1.2),
            Paint()..color = const Color(0xFFFFF3D4),
          );
          canvas.drawRect(
            Rect.fromCenter(center: Offset(offsetX, colH / 2), width: colW + 1.0, height: 1.2),
            Paint()..color = const Color(0xFFFFF3D4),
          );
        }
        canvas.restore();
      } else {
        // Double batons at remaining hours
        final rStart = ringInnerR + 2.0;
        final rEnd = ringOuterR - 6.5;

        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(a);

        const batonW = 1.3;
        const spacing = 2.2;

        final batonPaint = Paint()
          ..color = const Color(0xFFE5BE5E)
          ..strokeWidth = batonW
          ..strokeCap = StrokeCap.square;

        final batonShadow = Paint()
          ..color = Colors.black.withAlpha(140)
          ..strokeWidth = batonW
          ..strokeCap = StrokeCap.square;

        // Left baton
        canvas.drawLine(Offset(-spacing / 2 + 0.6, -rStart + 0.8), Offset(-spacing / 2 + 0.6, -rEnd + 0.8), batonShadow);
        canvas.drawLine(Offset(-spacing / 2, -rStart), Offset(-spacing / 2, -rEnd), batonPaint);

        // Right baton
        canvas.drawLine(Offset(spacing / 2 + 0.6, -rStart + 0.8), Offset(spacing / 2 + 0.6, -rEnd + 0.8), batonShadow);
        canvas.drawLine(Offset(spacing / 2, -rStart), Offset(spacing / 2, -rEnd), batonPaint);

        canvas.restore();
      }
    }
  }

  void _drawSkeletonLanceHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfW = width / 2;
    final tipY = -length;
    final shoulderY = -length * 0.72;
    final waistY = -length * 0.22;
    final tailY = length * 0.18;

    // Outer lance perimeter
    final outerLance = Path()
      ..moveTo(0, tailY)
      ..lineTo(-halfW * 0.55, 0)
      ..lineTo(-halfW, waistY)
      ..lineTo(-halfW * 1.15, shoulderY)
      ..lineTo(0, tipY) // Sharp tip
      ..lineTo(halfW * 1.15, shoulderY)
      ..lineTo(halfW, waistY)
      ..lineTo(halfW * 0.55, 0)
      ..close();

    // Drop shadow
    canvas.drawPath(
      outerLance.shift(const Offset(1.2, 1.8)),
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Gold body
    final goldBodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFFFFF6DF),
          color,
          const Color(0xFF9E7022),
        ],
      ).createShader(Rect.fromLTWH(-halfW * 1.2, tipY, halfW * 2.4, length + tailY));
    canvas.drawPath(outerLance, goldBodyPaint);

    // Inner openwork skeletonized slit
    final innerSlit = Path()
      ..moveTo(0, waistY * 0.85)
      ..lineTo(-halfW * 0.50, waistY)
      ..lineTo(-halfW * 0.55, shoulderY * 0.95)
      ..lineTo(0, shoulderY * 1.05)
      ..lineTo(halfW * 0.55, shoulderY * 0.95)
      ..lineTo(halfW * 0.50, waistY)
      ..close();

    // Carve out skeleton aperture revealing movement behind
    canvas.drawPath(innerSlit, Paint()..color = const Color(0xFF0A0C0E));
    canvas.drawPath(
      innerSlit,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(0xFFFFF6DF).withAlpha(160),
    );

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: GOLDEN SUNBURST & RUBY (MD GROUP)
  // ══════════════════════════════════════════════════════════════
  void _drawMDGroupEmblemGold(Canvas canvas, Offset pos, {required double scale}) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    final strokeGold = Paint()
      ..color = const Color(0xFFFFF6D9)
      ..strokeWidth = 1.3 * (scale / 1.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shadowGold = Paint()
      ..color = Colors.black.withAlpha(140)
      ..strokeWidth = 1.3 * (scale / 1.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawMD(double dx, double dy, Paint paint) {
      final s = scale * 4.0;
      // "M"
      final mPath = Path()
        ..moveTo(dx - s * 1.8, dy + s * 0.9)
        ..lineTo(dx - s * 1.8, dy - s * 0.9)
        ..lineTo(dx - s * 0.9, dy + s * 0.2)
        ..lineTo(dx, dy - s * 0.9)
        ..lineTo(dx, dy + s * 0.9);
      canvas.drawPath(mPath, paint);

      // "D" with inner concentric loops
      final dRect = Rect.fromCenter(center: Offset(dx + s * 1.0, dy), width: s * 1.7, height: s * 1.8);
      final dPath = Path()
        ..moveTo(dx + s * 0.2, dy + s * 0.9)
        ..lineTo(dx + s * 0.2, dy - s * 0.9)
        ..arcTo(dRect, -pi / 2, pi, false)
        ..close();
      canvas.drawPath(dPath, paint);

      // Inner spiral/concentric groove
      final innerD = Rect.fromCenter(center: Offset(dx + s * 1.0, dy), width: s * 1.0, height: s * 1.1);
      canvas.drawArc(innerD, -pi / 2, pi, false, paint);
    }

    drawMD(0.6, 0.8, shadowGold);
    drawMD(0.0, 0.0, strokeGold);

    // "GROUP" text
    final tp = TextPainter(
      text: TextSpan(
        text: 'GROUP',
        style: TextStyle(
          fontSize: 6.5 * (scale / 1.0),
          fontWeight: FontWeight.w900,
          color: const Color(0xFFFFF6DF),
          letterSpacing: 2.0 * (scale / 1.0),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(-tp.width / 2 + 0.6, scale * 4.8 + 0.8));
    tp.paint(canvas, Offset(-tp.width / 2, scale * 4.8));

    canvas.restore();
  }

  void _drawCushionCutRubyMarker(Canvas canvas, Offset center, double size, double rotation) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final half = size / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: size, height: size),
      Radius.circular(size * 0.22),
    );

    // Drop shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0.9, 1.2)),
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );

    // Outer Bezel / 4-Prong Gold Setting with Pavé Diamond Prongs
    final goldSetting = Paint()..color = const Color(0xFFECC565);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size + 1.8, height: size + 1.8),
        Radius.circular(size * 0.25),
      ),
      goldSetting,
    );

    // 4 Corner Gold/Diamond Prongs
    final prongPaint = Paint()..color = Colors.white;
    final prongOffsets = [
      Offset(-half - 0.4, -half - 0.4),
      Offset(half + 0.4, -half - 0.4),
      Offset(-half - 0.4, half + 0.4),
      Offset(half + 0.4, half + 0.4),
    ];
    for (final pt in prongOffsets) {
      canvas.drawCircle(pt, 0.85, prongPaint);
    }

    // Ruby Gemstone Body Gradient (Rich Crimson to Dark Pigeon Blood Red)
    final rubyPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: const [
          Color(0xFFF43F5E), // Bright ruby facet highlight
          Color(0xFFE11D48),
          Color(0xFFBE123C),
          Color(0xFF7F092B), // Deep crimson shadow
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromCenter(center: Offset.zero, width: size, height: size));
    canvas.drawRRect(rrect, rubyPaint);

    // Crystalline Sparkle / Facet Dots inside ruby
    final sparklePaint = Paint()..color = Colors.white.withAlpha(220);
    canvas.drawCircle(Offset(-half * 0.35, -half * 0.35), size * 0.16, sparklePaint);
    canvas.drawCircle(Offset(half * 0.35, -half * 0.10), size * 0.09, sparklePaint);
    canvas.drawCircle(Offset(-half * 0.10, half * 0.35), size * 0.08, sparklePaint);

    canvas.restore();
  }

  void _drawJeweledGreenDauphineHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double width,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfW = width / 2;
    final tailY = length * 0.16;

    // Drop shadow
    final handPath = Path()
      ..moveTo(0, tailY)
      ..lineTo(-halfW * 0.6, 0)
      ..lineTo(-halfW, -length * 0.22)
      ..lineTo(0, -length) // Sharp spear tip
      ..lineTo(halfW, -length * 0.22)
      ..lineTo(halfW * 0.6, 0)
      ..close();

    canvas.drawPath(
      handPath.shift(const Offset(1.2, 1.6)),
      Paint()
        ..color = Colors.black.withAlpha(120)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Left Facet (Light Lime Green)
    final leftPath = Path()
      ..moveTo(0, tailY)
      ..lineTo(-halfW * 0.6, 0)
      ..lineTo(-halfW, -length * 0.22)
      ..lineTo(0, -length)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = const Color(0xFF84CC16));

    // Right Facet (Darker Forest Jade Green)
    final rightPath = Path()
      ..moveTo(0, tailY)
      ..lineTo(halfW * 0.6, 0)
      ..lineTo(halfW, -length * 0.22)
      ..lineTo(0, -length)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = const Color(0xFF4D7C0F));

    // Center Spine Inlaid Diamond Crystals
    final spineLen = length * 0.65;
    final dotCount = (spineLen / 3.0).floor().clamp(4, 10);
    final dotPaint = Paint()..color = Colors.white;
    final dotBorder = Paint()
      ..color = const Color(0xFFD9F99D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (int i = 1; i <= dotCount; i++) {
      final y = -length * 0.12 - (spineLen * (i / (dotCount + 1)));
      canvas.drawCircle(Offset(0, y), 0.95, dotPaint);
      canvas.drawCircle(Offset(0, y), 1.25, dotBorder);
    }

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: AVIATOR CHRONOGRAPH (MD GROUP)
  // ══════════════════════════════════════════════════════════════
  void _drawAviatorNumerals(
    Canvas canvas,
    Offset center,
    double radius,
    Map<int, String> numerals,
    double fontSize,
  ) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    numerals.forEach((hour, label) {
      final a = (hour * 30) * pi / 180;
      final pos = Offset(center.dx + radius * sin(a), center.dy - radius * cos(a));

      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: const Color(0xFFEFE5D1),
          height: 1.0,
        ),
      );
      textPainter.layout();

      // Soft shadow
      final shadowPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            color: Colors.black.withAlpha(150),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      shadowPainter.paint(
        canvas,
        Offset(pos.dx - shadowPainter.width / 2 + 0.6, pos.dy - shadowPainter.height / 2 + 0.8),
      );

      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
      );
    });
  }

  void _drawMDGroupEmblemWhite(Canvas canvas, Offset pos, {required double scale}) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    final strokeWhite = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.3 * (scale / 1.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final shadowWhite = Paint()
      ..color = Colors.black.withAlpha(160)
      ..strokeWidth = 1.3 * (scale / 1.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawMD(double dx, double dy, Paint paint) {
      final s = scale * 4.0;
      // "M"
      final mPath = Path()
        ..moveTo(dx - s * 1.8, dy + s * 0.9)
        ..lineTo(dx - s * 1.8, dy - s * 0.9)
        ..lineTo(dx - s * 0.9, dy + s * 0.2)
        ..lineTo(dx, dy - s * 0.9)
        ..lineTo(dx, dy + s * 0.9);
      canvas.drawPath(mPath, paint);

      // "D"
      final dRect = Rect.fromCenter(center: Offset(dx + s * 1.0, dy), width: s * 1.7, height: s * 1.8);
      final dPath = Path()
        ..moveTo(dx + s * 0.2, dy + s * 0.9)
        ..lineTo(dx + s * 0.2, dy - s * 0.9)
        ..arcTo(dRect, -pi / 2, pi, false)
        ..close();
      canvas.drawPath(dPath, paint);

      // Inner spiral/groove inside D
      final innerD = Rect.fromCenter(center: Offset(dx + s * 1.0, dy), width: s * 1.0, height: s * 1.1);
      canvas.drawArc(innerD, -pi / 2, pi, false, paint);
    }

    drawMD(0.6, 0.8, shadowWhite);
    drawMD(0.0, 0.0, strokeWhite);

    // "GROUP" text
    final tp = TextPainter(
      text: TextSpan(
        text: 'GROUP',
        style: TextStyle(
          fontSize: 6.5 * (scale / 1.0),
          fontWeight: FontWeight.w900,
          color: const Color(0xFFF1F5F9),
          letterSpacing: 2.0 * (scale / 1.0),
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(-tp.width / 2 + 0.6, scale * 4.8 + 0.8));
    tp.paint(canvas, Offset(-tp.width / 2, scale * 4.8));

    canvas.restore();
  }

  void _drawChronoApertureSubDial(Canvas canvas, Offset subCenter, double subR) {
    // Recessed background disc
    canvas.drawCircle(subCenter, subR, Paint()..color = const Color(0xFF0D0F12));
    canvas.drawCircle(
      subCenter,
      subR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF262C36),
    );

    // Upper circular graduation ticks
    for (int i = 0; i < 12; i++) {
      final a = (i * 30) * pi / 180;
      // Only draw ticks in upper hemisphere
      if (a < pi / 2 || a > 3 * pi / 2) {
        final r1 = subR * 0.78;
        final r2 = subR * 0.92;
        canvas.drawLine(
          Offset(subCenter.dx + r1 * sin(a), subCenter.dy - r1 * cos(a)),
          Offset(subCenter.dx + r2 * sin(a), subCenter.dy - r2 * cos(a)),
          Paint()..color = Colors.white60..strokeWidth = 0.8,
        );
      }
    }

    // Lower-Half White/Cream Curved Aperture Cutout Window (Matching Reference Photo)
    final aptTopY = subCenter.dy + subR * 0.14;
    final aptHalfW = subR * 0.74;
    final aptBotY = subCenter.dy + subR * 0.82;

    final aptPath = Path()
      ..moveTo(subCenter.dx - aptHalfW, aptTopY)
      ..lineTo(subCenter.dx + aptHalfW, aptTopY)
      ..quadraticBezierTo(
        subCenter.dx + aptHalfW * 0.88, aptBotY,
        subCenter.dx, aptBotY,
      )
      ..quadraticBezierTo(
        subCenter.dx - aptHalfW * 0.88, aptBotY,
        subCenter.dx - aptHalfW, aptTopY,
      )
      ..close();

    // Inner White/Cream Gauge Plate
    canvas.drawPath(aptPath, Paint()..color = const Color(0xFFF4EFE6));
    canvas.drawPath(
      aptPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF2C3540),
    );

    // Miniature instrument markings inside aperture window
    final gaugePaint = Paint()..color = const Color(0xFF1E293B)..strokeWidth = 0.75;
    for (int g = -2; g <= 2; g++) {
      final gx = subCenter.dx + g * (subR * 0.22);
      final gyTop = aptTopY + 1.0;
      final gyBot = gyTop + subR * (g == 0 ? 0.32 : 0.22);
      canvas.drawLine(Offset(gx, gyTop), Offset(gx, gyBot), gaugePaint);
    }

    // Small black indicator glyph at center bottom of aperture
    canvas.drawCircle(Offset(subCenter.dx, aptBotY - subR * 0.12), subR * 0.065, Paint()..color = const Color(0xFF0F172A));

    // Center Copper Boss
    canvas.drawCircle(subCenter, subR * 0.18, Paint()..color = const Color(0xFFC27D53));
    canvas.drawCircle(
      subCenter,
      subR * 0.18,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = const Color(0xFFFFD4BA),
    );

    // Horizontal Tapered Orange Pointer Needle pointing directly to 9 o'clock
    final orangePath = Path()
      ..moveTo(subCenter.dx, subCenter.dy - 1.2)
      ..lineTo(subCenter.dx - subR * 0.88, subCenter.dy)
      ..lineTo(subCenter.dx, subCenter.dy + 1.2)
      ..close();
    canvas.drawPath(orangePath, Paint()..color = const Color(0xFFF97316));
  }

  void _drawChrono30MinSubDial(Canvas canvas, Offset subCenter, double subR) {
    canvas.drawCircle(subCenter, subR, Paint()..color = const Color(0xFF0D0F12));
    canvas.drawCircle(
      subCenter,
      subR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF262C36),
    );

    // 30 graduation ticks around perimeter
    for (int i = 0; i < 30; i++) {
      final a = (i * 12) * pi / 180;
      final isMajor = (i % 5 == 0);
      final r1 = isMajor ? subR * 0.75 : subR * 0.84;
      final r2 = subR * 0.94;
      canvas.drawLine(
        Offset(subCenter.dx + r1 * sin(a), subCenter.dy - r1 * cos(a)),
        Offset(subCenter.dx + r2 * sin(a), subCenter.dy - r2 * cos(a)),
        Paint()..color = Colors.white70..strokeWidth = isMajor ? 1.0 : 0.6,
      );
    }

    // Numerals: 20 (at ~8 o'clock of sub-dial), 16 (at ~4 o'clock)
    final numPainter = TextPainter(textDirection: TextDirection.ltr);
    void paintSubNum(String text, double angleDeg) {
      final a = angleDeg * pi / 180;
      final pos = Offset(subCenter.dx + subR * 0.58 * sin(a), subCenter.dy - subR * 0.58 * cos(a));
      numPainter.text = TextSpan(
        text: text,
        style: TextStyle(fontSize: subR * 0.30, fontWeight: FontWeight.bold, color: const Color(0xFFEFE5D1)),
      );
      numPainter.layout();
      numPainter.paint(canvas, Offset(pos.dx - numPainter.width / 2, pos.dy - numPainter.height / 2));
    }

    paintSubNum('20', 235);
    paintSubNum('16', 125);

    // Top figure-8 / crown glyph at 12 o'clock of sub-dial
    final glyphCenter = Offset(subCenter.dx, subCenter.dy - subR * 0.56);
    canvas.drawCircle(Offset(glyphCenter.dx, glyphCenter.dy - 1.2), subR * 0.08, Paint()..color = const Color(0xFFE5A97C));
    canvas.drawCircle(Offset(glyphCenter.dx, glyphCenter.dy + 1.2), subR * 0.10, Paint()..color = const Color(0xFFE5A97C));

    // Slender rose-gold / copper needle pointing upward
    final needlePaint = Paint()
      ..color = const Color(0xFFE5A97C)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(subCenter, Offset(subCenter.dx, subCenter.dy - subR * 0.82), needlePaint);

    // Center copper pivot
    canvas.drawCircle(subCenter, subR * 0.16, Paint()..color = const Color(0xFFC27D53));
    canvas.drawCircle(subCenter, subR * 0.08, Paint()..color = const Color(0xFF181C22));
  }

  void _drawChrono12HourSubDial(Canvas canvas, Offset subCenter, double subR) {
    canvas.drawCircle(subCenter, subR, Paint()..color = const Color(0xFF0D0F12));
    canvas.drawCircle(
      subCenter,
      subR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFF262C36),
    );

    // 24 ticks around perimeter
    for (int i = 0; i < 24; i++) {
      final a = (i * 15) * pi / 180;
      final isMajor = (i % 6 == 0);
      final r1 = isMajor ? subR * 0.74 : subR * 0.84;
      final r2 = subR * 0.94;
      canvas.drawLine(
        Offset(subCenter.dx + r1 * sin(a), subCenter.dy - r1 * cos(a)),
        Offset(subCenter.dx + r2 * sin(a), subCenter.dy - r2 * cos(a)),
        Paint()..color = Colors.white70..strokeWidth = isMajor ? 1.0 : 0.6,
      );
    }

    // Numbers: 6 (bottom), 8 (left), 4 (right), 12 (top double tick)
    final numPainter = TextPainter(textDirection: TextDirection.ltr);
    void paintSubNum(String text, double angleDeg) {
      final a = angleDeg * pi / 180;
      final pos = Offset(subCenter.dx + subR * 0.58 * sin(a), subCenter.dy - subR * 0.58 * cos(a));
      numPainter.text = TextSpan(
        text: text,
        style: TextStyle(fontSize: subR * 0.28, fontWeight: FontWeight.bold, color: const Color(0xFFEFE5D1)),
      );
      numPainter.layout();
      numPainter.paint(canvas, Offset(pos.dx - numPainter.width / 2, pos.dy - numPainter.height / 2));
    }

    paintSubNum('6', 180);
    paintSubNum('8', 240);
    paintSubNum('4', 120);

    // Double tick indicator at top
    final doubleTick = Paint()..color = const Color(0xFFEFE5D1)..strokeWidth = 1.0;
    canvas.drawLine(Offset(subCenter.dx - 1.2, subCenter.dy - subR * 0.72), Offset(subCenter.dx - 1.2, subCenter.dy - subR * 0.92), doubleTick);
    canvas.drawLine(Offset(subCenter.dx + 1.2, subCenter.dy - subR * 0.72), Offset(subCenter.dx + 1.2, subCenter.dy - subR * 0.92), doubleTick);

    // Slender rose-gold / copper needle pointing upward
    final needlePaint = Paint()
      ..color = const Color(0xFFE5A97C)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(subCenter, Offset(subCenter.dx, subCenter.dy - subR * 0.82), needlePaint);

    // Center copper pivot
    canvas.drawCircle(subCenter, subR * 0.16, Paint()..color = const Color(0xFFC27D53));
    canvas.drawCircle(subCenter, subR * 0.08, Paint()..color = const Color(0xFF181C22));
  }

  void _drawAviatorSwordHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double width,
    required Color lumeColor,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfW = width / 2;
    final tailY = length * 0.15;
    final tipY = -length;
    final shoulderY = -length * 0.75;

    // Drop shadow
    final handPath = Path()
      ..moveTo(0, tailY)
      ..lineTo(-halfW * 0.55, 0)
      ..lineTo(-halfW, shoulderY)
      ..lineTo(0, tipY) // Pointed triangle tip
      ..lineTo(halfW, shoulderY)
      ..lineTo(halfW * 0.55, 0)
      ..close();

    canvas.drawPath(
      handPath.shift(const Offset(1.2, 1.6)),
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Outer Dark Gunmetal Frame
    canvas.drawPath(handPath, Paint()..color = const Color(0xFF2B313A));

    // Inner Luminous Sage-Cream Fill Aperture
    final innerLumePath = Path()
      ..moveTo(0, tailY * 0.4)
      ..lineTo(-halfW * 0.65, -length * 0.05)
      ..lineTo(-halfW * 0.72, shoulderY * 0.96)
      ..lineTo(0, tipY * 0.92)
      ..lineTo(halfW * 0.72, shoulderY * 0.96)
      ..lineTo(halfW * 0.65, -length * 0.05)
      ..close();

    canvas.drawPath(innerLumePath, Paint()..color = lumeColor);

    // Center divider spine line
    canvas.drawLine(
      Offset(0, tailY * 0.2),
      Offset(0, tipY * 0.90),
      Paint()..color = const Color(0xFF4A5568)..strokeWidth = 0.6,
    );

    canvas.restore();
  }

  void _drawChronoSweepSecondHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double tailLength,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Drop shadow
    canvas.drawLine(
      Offset(0.9, tailLength + 0.9),
      Offset(0.9, -length + 0.9),
      Paint()..color = Colors.black.withAlpha(100)..strokeWidth = 1.2,
    );

    // Rose-Gold / Copper Needle
    final needlePaint = Paint()
      ..color = const Color(0xFFE5A97C)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, tailLength), Offset(0, -length), needlePaint);

    // Luminous Rectangular Bar near Tip
    final barTopY = -length * 0.82;
    final barRect = Rect.fromCenter(center: Offset(0, barTopY), width: 2.4, height: length * 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(0.6)),
      Paint()..color = const Color(0xFFEDE2CC),
    );

    // Rear counterweight
    canvas.drawCircle(Offset(0, tailLength * 0.65), 1.6, Paint()..color = const Color(0xFFE5A97C));

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: ROSE GOLD & SKELETON
  // ══════════════════════════════════════════════════════════════
  void _drawRoseGoldArabicNumerals(
    Canvas canvas,
    Offset center,
    double radius,
    Map<int, String> numerals,
    double fontSize,
  ) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    numerals.forEach((hour, label) {
      final a = (hour * 30) * pi / 180;
      final pos = Offset(center.dx + radius * sin(a), center.dy - radius * cos(a));

      // 1. Soft drop shadow
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.black.withAlpha(170),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 + 0.8, pos.dy - textPainter.height / 2 + 1.2));

      // 2. Base copper metallic body
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFB86641),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 + 0.3, pos.dy - textPainter.height / 2 + 0.4));

      // 3. Rose gold foreground face
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFEFA682),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2));

      // 4. Specular glint highlight
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFF2EB).withAlpha(140),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 - 0.3, pos.dy - textPainter.height / 2 - 0.4));
    });
  }

  void _drawRoseGoldSkeletonLanceHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double width,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfW = width / 2;
    final tipY = -length;
    final shoulderY = -length * 0.58;
    final neckY = -length * 0.18;

    // Hand outer outline path
    final outerPath = Path()
      ..moveTo(0, 3)
      ..lineTo(-halfW * 0.32, neckY)
      ..lineTo(-halfW, shoulderY)
      ..lineTo(0, tipY)
      ..lineTo(halfW, shoulderY)
      ..lineTo(halfW * 0.32, neckY)
      ..close();

    // Inner cutout opening (revealing black dial beneath)
    final innerCutout = Path()
      ..moveTo(0, neckY * 1.08)
      ..lineTo(-halfW * 0.52, shoulderY)
      ..lineTo(0, tipY * 0.88)
      ..lineTo(halfW * 0.52, shoulderY)
      ..close();

    final skeletonPath = Path.combine(PathOperation.difference, outerPath, innerCutout);

    // Drop shadow
    canvas.drawPath(
      skeletonPath.shift(const Offset(1.2, 1.6)),
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Rose gold metallic gradient
    final roseGoldHandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0xFFFBE4D5), // Specular light left
          Color(0xFFE89F77),
          Color(0xFFB86641), // Shaded right
        ],
      ).createShader(Rect.fromLTWH(-halfW, tipY, width, length));

    canvas.drawPath(skeletonPath, roseGoldHandPaint);

    // Fine inner and outer chamfer edges
    canvas.drawPath(
      outerPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = const Color(0xFFFFF0E6).withAlpha(130),
    );
    canvas.drawPath(
      innerCutout,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = const Color(0xFF7C3B24).withAlpha(160),
    );

    canvas.restore();
  }

  void _drawRoseGoldSecondNeedle(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double tailLength,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Drop shadow
    canvas.drawLine(
      Offset(0.8, tailLength + 0.8),
      Offset(0.8, -length + 0.8),
      Paint()..color = Colors.black.withAlpha(90)..strokeWidth = 1.0,
    );

    // Rose gold needle
    final needlePaint = Paint()
      ..color = const Color(0xFFE89F77)
      ..strokeWidth = 1.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, tailLength), Offset(0, -length), needlePaint);

    // Tail round boss
    canvas.drawCircle(Offset(0, tailLength * 0.6), 1.6, Paint()..color = const Color(0xFFE89F77));

    canvas.restore();
  }

  // ══════════════════════════════════════════════════════════════
  // HELPER RENDERING METHODS: MOTHER-OF-PEARL & MOONPHASE
  // ══════════════════════════════════════════════════════════════
  void _drawPearlGoldArabicNumerals(
    Canvas canvas,
    Offset center,
    double radius,
    Map<int, String> numerals,
    double fontSize,
  ) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    numerals.forEach((hour, label) {
      final a = (hour * 30) * pi / 180;
      final pos = Offset(center.dx + radius * sin(a), center.dy - radius * cos(a));

      // 1. Soft drop shadow onto mother-of-pearl
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.black.withAlpha(50),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 + 0.6, pos.dy - textPainter.height / 2 + 0.9));

      // 2. Base warm bronze edge
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF946816),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 + 0.2, pos.dy - textPainter.height / 2 + 0.3));

      // 3. Polished gold face
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFD4AF37),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2));

      // 4. Specular highlight
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFFF7DC).withAlpha(150),
          height: 1.0,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pos.dx - textPainter.width / 2 - 0.2, pos.dy - textPainter.height / 2 - 0.3));
    });
  }

  void _drawMoonphaseAperture(Canvas canvas, Offset aptCenter, double dialRadius) {
    final aptHalfW = dialRadius * 0.44;
    final aptHeight = dialRadius * 0.26;
    final topArcY = aptCenter.dy - aptHeight * 0.42;
    final botY = aptCenter.dy + aptHeight * 0.58;

    // Arched double-lobed crescent cutout aperture path
    final aperturePath = Path()
      ..moveTo(aptCenter.dx - aptHalfW, botY)
      ..cubicTo(
        aptCenter.dx - aptHalfW, topArcY - aptHeight * 0.25,
        aptCenter.dx + aptHalfW, topArcY - aptHeight * 0.25,
        aptCenter.dx + aptHalfW, botY,
      )
      ..close();

    // 1. Deep Midnight Royal Navy Blue Starry Sky
    canvas.save();
    canvas.clipPath(aperturePath);

    final skyPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter,
        radius: 0.85,
        colors: const [Color(0xFF1B356E), Color(0xFF0D1B3E), Color(0xFF080F24)],
      ).createShader(Rect.fromLTWH(aptCenter.dx - aptHalfW, topArcY - 10, aptHalfW * 2, aptHeight + 20));
    canvas.drawPaint(skyPaint);

    // 2. Full Gold Moon Disc
    final moonRadius = aptHeight * 0.38;
    final moonCenter = Offset(aptCenter.dx, aptCenter.dy - aptHeight * 0.04);
    final moonPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.25, -0.25),
        colors: [Color(0xFFFFF0B8), Color(0xFFFBBF24), Color(0xFFD97706)],
        stops: [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: moonCenter, radius: moonRadius));
    canvas.drawCircle(moonCenter, moonRadius, moonPaint);

    // Moon crater details
    canvas.drawCircle(Offset(moonCenter.dx - 3, moonCenter.dy - 2), 1.6, Paint()..color = const Color(0xFFB45309).withAlpha(45));
    canvas.drawCircle(Offset(moonCenter.dx + 4, moonCenter.dy + 3), 2.2, Paint()..color = const Color(0xFFB45309).withAlpha(40));

    // 3. Golden & Diamond Stars across Sky
    final starPaint = Paint()..color = const Color(0xFFFFF8E3);
    canvas.drawCircle(Offset(aptCenter.dx - aptHalfW * 0.58, aptCenter.dy - aptHeight * 0.12), 1.2, starPaint);
    canvas.drawCircle(Offset(aptCenter.dx - aptHalfW * 0.42, aptCenter.dy - aptHeight * 0.28), 0.9, starPaint);
    canvas.drawCircle(Offset(aptCenter.dx + aptHalfW * 0.52, aptCenter.dy - aptHeight * 0.16), 1.2, starPaint);
    canvas.drawCircle(Offset(aptCenter.dx + aptHalfW * 0.38, aptCenter.dy - aptHeight * 0.26), 0.8, starPaint);
    canvas.drawCircle(Offset(aptCenter.dx + aptHalfW * 0.62, aptCenter.dy + aptHeight * 0.05), 0.9, starPaint);

    // Small celestial emblem / constellation on the left
    final emblemX = aptCenter.dx - aptHalfW * 0.62;
    final emblemY = aptCenter.dy + aptHeight * 0.05;
    canvas.drawRect(Rect.fromCenter(center: Offset(emblemX, emblemY), width: 2.2, height: 4.2), Paint()..color = const Color(0xFFFBBF24));
    canvas.drawCircle(Offset(emblemX, emblemY - 3), 1.2, Paint()..color = const Color(0xFFFBBF24));

    // 4. Scalloped White Cloud Mask across the lower portion
    final cloudPath = Path()
      ..moveTo(aptCenter.dx - aptHalfW, botY + 5)
      ..lineTo(aptCenter.dx - aptHalfW, botY - aptHeight * 0.15)
      ..quadraticBezierTo(
        aptCenter.dx - aptHalfW * 0.50, botY - aptHeight * 0.42,
        aptCenter.dx, botY - aptHeight * 0.18,
      )
      ..quadraticBezierTo(
        aptCenter.dx + aptHalfW * 0.50, botY - aptHeight * 0.42,
        aptCenter.dx + aptHalfW, botY - aptHeight * 0.15,
      )
      ..lineTo(aptCenter.dx + aptHalfW, botY + 5)
      ..close();

    final cloudPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFFFFFFF), Color(0xFFF1EFEA)],
      ).createShader(Rect.fromLTWH(aptCenter.dx - aptHalfW, botY - aptHeight * 0.45, aptHalfW * 2, aptHeight));
    canvas.drawPath(cloudPath, cloudPaint);

    // Fine gold lining on cloud crests
    final cloudRim = Path()
      ..moveTo(aptCenter.dx - aptHalfW, botY - aptHeight * 0.15)
      ..quadraticBezierTo(
        aptCenter.dx - aptHalfW * 0.50, botY - aptHeight * 0.42,
        aptCenter.dx, botY - aptHeight * 0.18,
      )
      ..quadraticBezierTo(
        aptCenter.dx + aptHalfW * 0.50, botY - aptHeight * 0.42,
        aptCenter.dx + aptHalfW, botY - aptHeight * 0.15,
      );
    canvas.drawPath(
      cloudRim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFECC565),
    );

    canvas.restore();

    // 5. Polished 3D Gold Aperture Frame Rim
    canvas.drawPath(
      aperturePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFFD4AF37),
    );
    canvas.drawPath(
      aperturePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0xFFFFF8E3).withAlpha(180),
    );
  }

  void _drawRunningSecondsSubDial(Canvas canvas, Offset subCenter, double subR) {
    // Drop shadow
    canvas.drawCircle(
      subCenter.translate(0, 1.0),
      subR,
      Paint()
        ..color = Colors.black.withAlpha(45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Sunburst Champagne Brass Disc
    final brassPaint = Paint()
      ..shader = const SweepGradient(
        transform: GradientRotation(-pi / 4),
        colors: [
          Color(0xFFF9E7B3), // Top-left highlight
          Color(0xFFE5BE5E),
          Color(0xFFC49226),
          Color(0xFF9E7018), // Bottom-right shade
          Color(0xFFC49226),
          Color(0xFFE5BE5E),
          Color(0xFFF9E7B3),
        ],
      ).createShader(Rect.fromCircle(center: subCenter, radius: subR));
    canvas.drawCircle(subCenter, subR, brassPaint);

    // Double Concentric Polished Gold Border Rings
    canvas.drawCircle(
      subCenter,
      subR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = const Color(0xFFD4AF37),
    );
    canvas.drawCircle(
      subCenter,
      subR * 0.94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = const Color(0xFF9E7018).withAlpha(140),
    );

    // 60 Fine Radial Graduation Ticks along perimeter
    for (int i = 0; i < 60; i++) {
      final a = (i * 6) * pi / 180;
      final isMajor = (i % 5 == 0);
      final r1 = isMajor ? subR * 0.76 : subR * 0.83;
      final r2 = subR * 0.92;
      canvas.drawLine(
        Offset(subCenter.dx + r1 * sin(a), subCenter.dy - r1 * cos(a)),
        Offset(subCenter.dx + r2 * sin(a), subCenter.dy - r2 * cos(a)),
        Paint()
          ..color = const Color(0xFF422E0F)
          ..strokeWidth = isMajor ? 0.9 : 0.55,
      );
    }

    // Rotating Miniature Sage Green Seconds Needle
    final sSec = dateTime.second + dateTime.millisecond / 1000.0;
    final subAngle = sSec * 6 * pi / 180;

    canvas.save();
    canvas.translate(subCenter.dx, subCenter.dy);
    canvas.rotate(subAngle);

    // Needle drop shadow
    canvas.drawLine(
      const Offset(0.6, 2.6),
      Offset(0.6, -subR * 0.76 + 0.6),
      Paint()..color = Colors.black.withAlpha(60)..strokeWidth = 1.0,
    );

    // Sage Green Needle
    final needlePaint = Paint()
      ..color = const Color(0xFF3B633F)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(0, 2.0), Offset(0, -subR * 0.76), needlePaint);

    // Center Gold Pivot Boss
    canvas.drawCircle(Offset.zero, subR * 0.16, Paint()..color = const Color(0xFFD4AF37));
    canvas.drawCircle(Offset.zero, subR * 0.07, Paint()..color = const Color(0xFF3B633F));

    canvas.restore();
  }

  void _drawSageGreenDauphineHand(
    Canvas canvas,
    Offset center,
    double angle, {
    required double length,
    required double width,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final halfW = width / 2;
    final shoulderY = -length * 0.35;
    final tipY = -length;

    // Hand drop shadow onto mother-of-pearl dial
    final shadowPath = Path()
      ..moveTo(0, 4)
      ..lineTo(-halfW, shoulderY)
      ..lineTo(0, tipY)
      ..lineTo(halfW, shoulderY)
      ..close();

    canvas.drawPath(
      shadowPath.shift(const Offset(1.0, 1.5)),
      Paint()
        ..color = Colors.black.withAlpha(90)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
    );

    // Left illuminated green facet
    final leftPath = Path()
      ..moveTo(0, 4)
      ..lineTo(-halfW, shoulderY)
      ..lineTo(0, tipY)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = const Color(0xFF5E9462));

    // Right shaded green facet
    final rightPath = Path()
      ..moveTo(0, 4)
      ..lineTo(halfW, shoulderY)
      ..lineTo(0, tipY)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = const Color(0xFF385C3B));

    // Crisp center spine line
    canvas.drawLine(
      const Offset(0, 3),
      Offset(0, tipY + 1),
      Paint()
        ..color = const Color(0xFF7CB380)
        ..strokeWidth = 0.75,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnalogClockPainter oldDelegate) {
    return oldDelegate.dateTime.second != dateTime.second ||
        oldDelegate.dateTime.minute != dateTime.minute ||
        oldDelegate.dateTime.hour != dateTime.hour ||
        oldDelegate.isDark != isDark ||
        oldDelegate.design != design ||
        oldDelegate.theme != theme;
  }
}
