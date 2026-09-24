import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines the visual aesthetic, artwork, dial geometry, digital layout,
/// and matching card container styling for the clock.
class ClockDesign {
  final String id;
  final String name;
  final String urduName;
  final String description;
  final IconData icon;
  final bool isDigital;

  // Matching Card Theming Properties
  final Color cardBgLight;
  final Color cardBgDark;
  final Color cardBorderColor;
  final Color cardShadowColor;
  final Color primaryColor;
  final Color accentColor;
  final Color textColorLight;
  final Color textColorDark;

  // Watch Face Dial & Hand Colors
  final Color dialBgLight;
  final Color dialBgDark;
  final Color handLight;
  final Color handDark;

  const ClockDesign({
    required this.id,
    required this.name,
    required this.urduName,
    required this.description,
    required this.icon,
    this.isDigital = false,
    required this.cardBgLight,
    required this.cardBgDark,
    required this.cardBorderColor,
    required this.cardShadowColor,
    required this.primaryColor,
    required this.accentColor,
    required this.textColorLight,
    required this.textColorDark,
    required this.dialBgLight,
    required this.dialBgDark,
    required this.handLight,
    required this.handDark,
  });
}

/// Backwards compatibility wrapper for ClockTheme
class ClockTheme {
  final String id;
  final String name;
  final String urduName;
  final Color primaryColor;
  final Color accentColor;
  final Color dialLight;
  final Color dialDark;
  final Color handLight;
  final Color handDark;

  const ClockTheme({
    required this.id,
    required this.name,
    required this.urduName,
    required this.primaryColor,
    required this.accentColor,
    required this.dialLight,
    required this.dialDark,
    required this.handLight,
    required this.handDark,
  });

  factory ClockTheme.fromDesign(ClockDesign design) {
    return ClockTheme(
      id: design.id,
      name: design.name,
      urduName: design.urduName,
      primaryColor: design.primaryColor,
      accentColor: design.accentColor,
      dialLight: design.dialBgLight,
      dialDark: design.dialBgDark,
      handLight: design.handLight,
      handDark: design.handDark,
    );
  }
}

/// Service managing the 16 Curated Clock Designs (8 Analog + 8 Digital)
/// and their matching card styling.
class ClockThemeService {
  static const _prefAnalogDesignKey = 'dashboard_clock_design_id';
  static const _prefDigitalDesignKey = 'dashboard_clock_digital_design_id';

  // ══════════════════════════════════════════════════════════════
  // 6 ANALOG CLOCK DESIGNS (CURATED COLLECTION - AVIATOR DEFAULT)
  // ══════════════════════════════════════════════════════════════
  static const List<ClockDesign> analogDesigns = [
    // 1. Aviator Chronograph (MD GROUP) (Curated from user reference image - PRIMARY DEFAULT)
    ClockDesign(
      id: 'analog_military_chrono_md',
      name: 'Aviator Chronograph',
      urduName: 'ملٹری ایوی ایٹر (MD GROUP)',
      description: 'Tactical matte black dial, MD GROUP logo, 3 sub-dials with gauge aperture, and aviator sword hands',
      icon: Icons.speed_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF221711),
      cardBgDark: Color(0xFF18100B),
      cardBorderColor: Color(0xFFE5A97C),
      cardShadowColor: Color(0x6618100B),
      primaryColor: Color(0xFFE5A97C),
      accentColor: Color(0xFFF97316),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF1A1D22),
      dialBgDark: Color(0xFF111417),
      handLight: Color(0xFFD2DDD0),
      handDark: Color(0xFFD2DDD0),
    ),

    // 2. Golden Sunburst & Ruby (MD GROUP) (Curated from user reference image)
    ClockDesign(
      id: 'analog_ruby_sunburst_md',
      name: 'Golden Sunburst & Ruby',
      urduName: 'سن برسٹ روبی (MD GROUP)',
      description: 'Honey amber sunburst dial, MD GROUP badge, 12 square cushion-cut rubies, and jeweled green hands',
      icon: Icons.diamond_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF261908),
      cardBgDark: Color(0xFF1B1104),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x66B45309),
      primaryColor: Color(0xFFD97706),
      accentColor: Color(0xFFE11D48),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFFE28907),
      dialBgDark: Color(0xFFB45309),
      handLight: Color(0xFF84CC16),
      handDark: Color(0xFF84CC16),
    ),

    // 3. Rose Gold & Stealth Black (Curated from user reference image)
    ClockDesign(
      id: 'analog_rosegold_black_skeleton',
      name: 'Rose Gold & Stealth Black',
      urduName: 'روز گولڈ و بلیک اسکیلیٹن',
      description: 'Matte black dial, 3D rose-gold Arabic numerals (1-12), tubular copper bezel, and openwork skeleton lance hands',
      icon: Icons.all_inclusive_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF201614),
      cardBgDark: Color(0xFF140D0C),
      cardBorderColor: Color(0xFFE5A27A),
      cardShadowColor: Color(0x665E2B16),
      primaryColor: Color(0xFFE5A27A),
      accentColor: Color(0xFFF6C4A6),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF18191C),
      dialBgDark: Color(0xFF101113),
      handLight: Color(0xFFE5A27A),
      handDark: Color(0xFFE5A27A),
    ),

    // 4. Mother-of-Pearl Moonphase (Curated from user reference image)
    ClockDesign(
      id: 'analog_moonphase_pearl_gold',
      name: 'Mother-of-Pearl Moonphase',
      urduName: 'مدر آف پرل مون فیز گولڈ',
      description: 'Shimmering pearl dial, top midnight moonphase aperture, bottom gold running seconds dial, and jade green hands',
      icon: Icons.brightness_2_rounded,
      isDigital: false,
      cardBgLight: Color(0xFFFAF7F2),
      cardBgDark: Color(0xFF111827),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x44D4AF37),
      primaryColor: Color(0xFF4A784E),
      accentColor: Color(0xFFD4AF37),
      textColorLight: Color(0xFF1E293B),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFFFAF8F5),
      dialBgDark: Color(0xFFEDE7DC),
      handLight: Color(0xFF4A784E),
      handDark: Color(0xFF4A784E),
    ),

    // 5. Royal Walnut Roman Brass (Curated from user reference image)
    ClockDesign(
      id: 'analog_classic_roman_gold',
      name: 'Royal Walnut Roman Brass',
      urduName: 'والنٹ و براس رومن',
      description: 'Walnut wood surround, 3D brass bezel, radial brushed dial, railroad track, and faceted dauphine hands',
      icon: Icons.watch_later_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF231610),
      cardBgDark: Color(0xFF1B100B),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x661A1108),
      primaryColor: Color(0xFFD4AF37),
      accentColor: Color(0xFFF3D78A),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF14171A),
      dialBgDark: Color(0xFF14171A),
      handLight: Color(0xFFF3D78A),
      handDark: Color(0xFFF3D78A),
    ),

    // 6. Emerald Leaf & Code </> (Curated from user reference image)
    ClockDesign(
      id: 'analog_emerald_leaf_code',
      name: 'Emerald Leaf & Code',
      urduName: 'زمرد لیف اور کوڈ </>',
      description: 'Sunburst emerald dial, embossed jewel leaf, gold </> code bracket markers, and faceted rose hands',
      icon: Icons.code_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF07241B),
      cardBgDark: Color(0xFF041913),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x55042F24),
      primaryColor: Color(0xFF10B981),
      accentColor: Color(0xFFFDE047),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF077A53),
      dialBgDark: Color(0xFF044831),
      handLight: Color(0xFFE28C4A),
      handDark: Color(0xFFE28C4A),
    ),

    // 7. Steampunk Gears Skeleton (Curated from user reference image)
    ClockDesign(
      id: 'analog_steampunk_skeleton',
      name: 'Steampunk Gears Skeleton',
      urduName: 'اسٹیم پنک مکینیکل گیئرز',
      description: 'Industrial gunmetal crenellated ring, interlocking exposed cogs, keyhole at 6, and skeleton lance hands',
      icon: Icons.settings_rounded,
      isDigital: false,
      cardBgLight: Color(0xFF221F1C),
      cardBgDark: Color(0xFF161412),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x66B45309),
      primaryColor: Color(0xFFD4AF37),
      accentColor: Color(0xFFF59E0B),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF181A1C),
      dialBgDark: Color(0xFF0E1012),
      handLight: Color(0xFFECC875),
      handDark: Color(0xFFECC875),
    ),

    // 8. Minimalist Stealth Black
    ClockDesign(
      id: 'analog_minimalist_stealth',
      name: 'Minimalist Stealth Black',
      urduName: 'منیملسٹ اسٹیلتھ بلیک',
      description: 'Concentric vinyl-grooved black dial, slender silver batons, and dauphine hands',
      icon: Icons.blur_circular_rounded,
      isDigital: false,
      cardBgLight: Color(0xFFF8FAFC),
      cardBgDark: Color(0xFF0B0F17),
      cardBorderColor: Color(0xFF475569),
      cardShadowColor: Color(0x33475569),
      primaryColor: Color(0xFF334155),
      accentColor: Color(0xFF94A3B8),
      textColorLight: Color(0xFF0F172A),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF1E293B),
      dialBgDark: Color(0xFF0F172A),
      handLight: Color(0xFFE2E8F0),
      handDark: Color(0xFFFFFFFF),
    ),
  ];

  // ══════════════════════════════════════════════════════════════
  // 6 DIGITAL CLOCK DESIGNS (CURATED COLLECTION FROM IMAGE)
  // ══════════════════════════════════════════════════════════════
  static const List<ClockDesign> digitalDesigns = [
    // 1. Square Pixel White LED (media_1790015376297.png - PRIMARY DEFAULT)
    ClockDesign(
      id: 'digital_dot_matrix_white',
      name: 'Square Pixel LED',
      urduName: 'اسکوائر پکسل ایل ای ڈی',
      description: 'Brass squircle bezel & 4 corner screws, enlarged crisp white square-pixel block LED digits, and metallic MD logo',
      icon: Icons.grain_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF14171E),
      cardBgDark: Color(0xFF0C0E13),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x44D4AF37),
      primaryColor: Color(0xFFD4AF37),
      accentColor: Color(0xFFF8FAFC),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF14171E),
      dialBgDark: Color(0xFF0C0E13),
      handLight: Colors.white,
      handDark: Colors.white,
    ),

    // 2. Cyan Glow LED (media_1790015376317.png)
    ClockDesign(
      id: 'digital_cyan_weather_schedule',
      name: 'Cyan Glow LED',
      urduName: 'سیان گلو ایل ای ڈی',
      description: 'Brass squircle bezel, enlarged glowing cyan 7-segment LED time, cyan leaf accent, and authentic MD logo',
      icon: Icons.access_time_filled_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF071920),
      cardBgDark: Color(0xFF030D10),
      cardBorderColor: Color(0xFF00E5FF),
      cardShadowColor: Color(0x4400E5FF),
      primaryColor: Color(0xFF00E5FF),
      accentColor: Color(0xFF22D3EE),
      textColorLight: Color(0xFFE0F7FA),
      textColorDark: Color(0xFFE0F7FA),
      dialBgLight: Color(0xFF071920),
      dialBgDark: Color(0xFF030D10),
      handLight: Color(0xFF22D3EE),
      handDark: Color(0xFF22D3EE),
    ),

    // 3. Nixie Glow Amber
    ClockDesign(
      id: 'digital_amber_nixie_tube',
      name: 'Nixie Glow Amber',
      urduName: 'نکسی گلو امبر',
      description: 'Smoked copper squircle bezel, enlarged warm glowing amber neon vacuum tube digits, and metallic MD logo',
      icon: Icons.lightbulb_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF180D07),
      cardBgDark: Color(0xFF0E0703),
      cardBorderColor: Color(0xFFFF9500),
      cardShadowColor: Color(0x44FF9500),
      primaryColor: Color(0xFFFF9500),
      accentColor: Color(0xFFFFB347),
      textColorLight: Color(0xFFFFEDD5),
      textColorDark: Color(0xFFFFEDD5),
      dialBgLight: Color(0xFF180D07),
      dialBgDark: Color(0xFF0E0703),
      handLight: Color(0xFFFF9224),
      handDark: Color(0xFFFF9224),
    ),

    // 4. Royal Emerald & Gold
    ClockDesign(
      id: 'digital_emerald_gold_lcd',
      name: 'Royal Emerald & Gold',
      urduName: 'رائل زمرد و زریں',
      description: '18K fluted gold bezel with corner rivets, deep imperial obsidian emerald dial, enlarged champagne gold split-flap cards, and MD logo',
      icon: Icons.diamond_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF051B12),
      cardBgDark: Color(0xFF020E09),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x44052E20),
      primaryColor: Color(0xFFD4AF37),
      accentColor: Color(0xFFFFE082),
      textColorLight: Color(0xFFDCFCE7),
      textColorDark: Color(0xFFDCFCE7),
      dialBgLight: Color(0xFF051B12),
      dialBgDark: Color(0xFF020E09),
      handLight: Color(0xFFFFE082),
      handDark: Color(0xFFFFE082),
    ),

    // 5. Crimson Carbon Sport
    ClockDesign(
      id: 'digital_crimson_carbon_matrix',
      name: 'Crimson Carbon Sport',
      urduName: 'کرمسن کاربن اسپورٹ',
      description: 'Matte gunmetal titanium bezel, woven carbon fiber dial, enlarged racing crimson red LED dot-matrix bulbs, and MD logo',
      icon: Icons.sports_motorsports_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF17080A),
      cardBgDark: Color(0xFF0E0405),
      cardBorderColor: Color(0xFFFF1E27),
      cardShadowColor: Color(0x44FF1E27),
      primaryColor: Color(0xFFFF1E27),
      accentColor: Color(0xFFFF4D55),
      textColorLight: Color(0xFFFEE2E2),
      textColorDark: Color(0xFFFEE2E2),
      dialBgLight: Color(0xFF17080A),
      dialBgDark: Color(0xFF0E0405),
      handLight: Color(0xFFFF1E27),
      handDark: Color(0xFFFF1E27),
    ),

    // 6. Bauhaus Dark Graphite
    ClockDesign(
      id: 'digital_monochrome_bauhaus',
      name: 'Bauhaus Dark Graphite',
      urduName: 'باؤہاؤس ڈارک گریفائٹ',
      description: 'Brushed gunmetal bezel, matte dark graphite slate dial, enlarged monolithic stencil polar white numerals, and MD logo',
      icon: Icons.article_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF141A24),
      cardBgDark: Color(0xFF0B0E14),
      cardBorderColor: Color(0xFF475569),
      cardShadowColor: Color(0x44334155),
      primaryColor: Color(0xFF94A3B8),
      accentColor: Color(0xFFF8FAFC),
      textColorLight: Color(0xFFF8FAFC),
      textColorDark: Color(0xFFF8FAFC),
      dialBgLight: Color(0xFF141A24),
      dialBgDark: Color(0xFF0B0E14),
      handLight: Color(0xFFF8FAFC),
      handDark: Color(0xFFF8FAFC),
    ),

    // 7. Classic Brass E-Ink (media_1790019228166.png)
    ClockDesign(
      id: 'digital_cyber_violet_neon',
      name: 'Classic Brass E-Ink',
      urduName: 'کلاسک براس ای-انک',
      description: 'Polished brushed brass squircle bezel with corner screws, warm off-white dial, circular chapter ring, E-INK header, bold center time, and MD logo',
      icon: Icons.access_time_filled_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF1E1C18),
      cardBgDark: Color(0xFF12110E),
      cardBorderColor: Color(0xFFD4AF37),
      cardShadowColor: Color(0x44D4AF37),
      primaryColor: Color(0xFFD4AF37),
      accentColor: Color(0xFF1A1D20),
      textColorLight: Color(0xFFFAF9F6),
      textColorDark: Color(0xFFFAF9F6),
      dialBgLight: Color(0xFFFAF9F6),
      dialBgDark: Color(0xFFECEAE4),
      handLight: Color(0xFF1A1D20),
      handDark: Color(0xFF1A1D20),
    ),

    // 8. Royal Sapphire Flip Clock (Replaces Glacier Ice Crystal with Flip Clock from image 2)
    ClockDesign(
      id: 'digital_ice_blue_crystal',
      name: 'Royal Sapphire Flip Clock',
      urduName: 'رائل سیفائر فلپ کلاک',
      description: 'Brass squircle bezel & corner screws, deep midnight sapphire dial, dark split-flap flip cards with gold serif numerals, and MD logo',
      icon: Icons.flip_to_front_rounded,
      isDigital: true,
      cardBgLight: Color(0xFF071526),
      cardBgDark: Color(0xFF030B14),
      cardBorderColor: Color(0xFF38BDF8),
      cardShadowColor: Color(0x440284C7),
      primaryColor: Color(0xFF38BDF8),
      accentColor: Color(0xFFFFE082),
      textColorLight: Color(0xFFE0F2FE),
      textColorDark: Color(0xFFE0F2FE),
      dialBgLight: Color(0xFF071526),
      dialBgDark: Color(0xFF030B14),
      handLight: Color(0xFFFFE082),
      handDark: Color(0xFFFFE082),
    ),
  ];

  // Combined designs
  static List<ClockDesign> get designs => [...analogDesigns, ...digitalDesigns];

  static ClockDesign get defaultAnalogDesign => analogDesigns.first;
  static ClockDesign get defaultDigitalDesign => digitalDesigns.first;
  static ClockDesign get defaultDesign => defaultAnalogDesign;

  // Notifiers
  static final ValueNotifier<ClockDesign> currentAnalogDesignNotifier =
      ValueNotifier<ClockDesign>(defaultAnalogDesign);

  static final ValueNotifier<ClockDesign> currentDigitalDesignNotifier =
      ValueNotifier<ClockDesign>(defaultDigitalDesign);

  // Backward compatibility alias for currentDesignNotifier
  static ValueNotifier<ClockDesign> get currentDesignNotifier => currentAnalogDesignNotifier;

  // Backward compatibility theme notifier
  static final ValueNotifier<ClockTheme> currentThemeNotifier =
      ValueNotifier<ClockTheme>(ClockTheme.fromDesign(defaultAnalogDesign));

  static ClockDesign get currentAnalogDesign => currentAnalogDesignNotifier.value;
  static ClockDesign get currentDigitalDesign => currentDigitalDesignNotifier.value;
  static ClockDesign get currentDesign => currentAnalogDesignNotifier.value;
  static ClockTheme get currentTheme => currentThemeNotifier.value;

  /// Returns active design for given mode
  static ClockDesign getActiveDesign(bool isAnalog) =>
      isAnalog ? currentAnalogDesign : currentDigitalDesign;

  /// Returns the design list corresponding to mode
  static List<ClockDesign> getDesignsForMode(bool isAnalog) =>
      isAnalog ? analogDesigns : digitalDesigns;

  /// Initialize and restore saved designs from SharedPreferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Ensure migration to Aviator Chronograph (MD GROUP) as new primary default
    final isMigrated = prefs.getBool('dashboard_clock_v3_migrated') ?? false;
    if (!isMigrated) {
      await prefs.setString(_prefAnalogDesignKey, defaultAnalogDesign.id);
      await prefs.setBool('dashboard_clock_v3_migrated', true);
    }

    // 1. Analog Design Model
    final savedAnalogId = prefs.getString(_prefAnalogDesignKey);
    final found = analogDesigns.firstWhere(
      (d) => d.id == savedAnalogId,
      orElse: () => defaultAnalogDesign,
    );
    currentAnalogDesignNotifier.value = found;
    currentThemeNotifier.value = ClockTheme.fromDesign(found);

    // 2. Digital Design Model (Migrate to new Square Pixel White LED default)
    final isDigitalMigratedV4 = prefs.getBool('dashboard_clock_v4_digital_migrated') ?? false;
    if (!isDigitalMigratedV4) {
      await prefs.setString(_prefDigitalDesignKey, defaultDigitalDesign.id);
      await prefs.setBool('dashboard_clock_v4_digital_migrated', true);
    }

    final savedDigitalId = prefs.getString(_prefDigitalDesignKey);
    final foundDigital = digitalDesigns.firstWhere(
      (d) => d.id == savedDigitalId,
      orElse: () => defaultDigitalDesign,
    );
    currentDigitalDesignNotifier.value = foundDigital;
  }

  /// Change and persist Analog Clock Design
  static Future<void> setAnalogDesign(String id) async {
    final found = analogDesigns.firstWhere(
      (d) => d.id == id,
      orElse: () => defaultAnalogDesign,
    );
    currentAnalogDesignNotifier.value = found;
    currentThemeNotifier.value = ClockTheme.fromDesign(found);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAnalogDesignKey, id);
  }

  /// Change and persist Digital Clock Design
  static Future<void> setDigitalDesign(String id) async {
    final found = digitalDesigns.firstWhere(
      (d) => d.id == id,
      orElse: () => defaultDigitalDesign,
    );
    currentDigitalDesignNotifier.value = found;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefDigitalDesignKey, id);
  }

  /// Change and persist Clock Design (automatically handles analog/digital based on design)
  static Future<void> setDesign(String id, {bool isDigital = false}) async {
    if (isDigital || digitalDesigns.any((d) => d.id == id)) {
      await setDigitalDesign(id);
    } else {
      await setAnalogDesign(id);
    }
  }

  // Backwards compatibility alias
  static List<ClockTheme> get colorThemes =>
      analogDesigns.map((d) => ClockTheme.fromDesign(d)).toList();
  static List<ClockTheme> get themes => colorThemes;
  static ClockTheme get defaultTheme => ClockTheme.fromDesign(defaultAnalogDesign);
  static Future<void> setColorTheme(String id) async {
    await setAnalogDesign(id);
  }
  static Future<void> setTheme(String id) => setColorTheme(id);
}
