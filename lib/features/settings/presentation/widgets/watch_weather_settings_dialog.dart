import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/clock_theme_service.dart';
import '../../../../core/services/salat_time_service.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dashboard/presentation/widgets/analog_clock_painter.dart';
import '../../../dashboard/presentation/widgets/digital_clock_painter.dart';

class WatchWeatherSettingsDialog extends StatefulWidget {
  const WatchWeatherSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const WatchWeatherSettingsDialog(),
    );
  }

  @override
  State<WatchWeatherSettingsDialog> createState() => _WatchWeatherSettingsDialogState();
}

class _WatchWeatherSettingsDialogState extends State<WatchWeatherSettingsDialog> {
  static const _prefKeyIsAnalog = 'dashboard_is_analog_clock';
  static const _prefKey24Hour = 'dashboard_clock_is_24h';
  static const _prefKeyShowSeconds = 'dashboard_clock_show_seconds';
  static const _prefKeyTempUnitF = 'dashboard_temp_unit_fahrenheit';

  bool _isAnalog = true;
  bool _is24Hour = false;
  bool _showSeconds = true;
  bool _isFahrenheit = false;

  String _selectedAnalogDesignId = ClockThemeService.defaultAnalogDesign.id;
  String _selectedDigitalDesignId = ClockThemeService.defaultDigitalDesign.id;
  late TextEditingController _cityCtrl;

  late final ValueNotifier<DateTime> _clockTicker;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _clockTicker = ValueNotifier<DateTime>(DateTime.now());
    _cityCtrl = TextEditingController();
    _selectedAnalogDesignId = ClockThemeService.currentAnalogDesign.id;
    _selectedDigitalDesignId = ClockThemeService.currentDigitalDesign.id;
    _loadPreferences();
    _startPreviewTimer();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _clockTicker.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _startPreviewTimer() {
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _clockTicker.value = DateTime.now();
      }
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCity = await WeatherService.getSavedCity();
    if (mounted) {
      setState(() {
        _isAnalog = prefs.getBool(_prefKeyIsAnalog) ?? true;
        _is24Hour = prefs.getBool(_prefKey24Hour) ?? false;
        _showSeconds = prefs.getBool(_prefKeyShowSeconds) ?? true;
        _isFahrenheit = prefs.getBool(_prefKeyTempUnitF) ?? false;
        _selectedAnalogDesignId = ClockThemeService.currentAnalogDesign.id;
        _selectedDigitalDesignId = ClockThemeService.currentDigitalDesign.id;
        _cityCtrl.text = savedCity;
      });
    }
  }

  ClockDesign get _activeDesign => _isAnalog
      ? ClockThemeService.analogDesigns.firstWhere(
          (d) => d.id == _selectedAnalogDesignId,
          orElse: () => ClockThemeService.defaultAnalogDesign,
        )
      : ClockThemeService.digitalDesigns.firstWhere(
          (d) => d.id == _selectedDigitalDesignId,
          orElse: () => ClockThemeService.defaultDigitalDesign,
        );

  ClockTheme get _activeTheme => ClockTheme.fromDesign(_activeDesign);

  Future<void> _handleSave() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyIsAnalog, _isAnalog);
    await prefs.setBool(_prefKey24Hour, _is24Hour);
    await prefs.setBool(_prefKeyShowSeconds, _showSeconds);
    await prefs.setBool(_prefKeyTempUnitF, _isFahrenheit);

    // Save both Analog and Digital Designs
    await ClockThemeService.setAnalogDesign(_selectedAnalogDesignId);
    await ClockThemeService.setDigitalDesign(_selectedDigitalDesignId);

    // Save City
    final cityText = _cityCtrl.text.trim();
    if (cityText.isNotEmpty) {
      final preset = SalatTimeService.findPresetCity(cityText);
      if (preset != null) {
        await SalatTimeService.setCityAndCoordinates(
          preset.name,
          preset.latitude,
          preset.longitude,
          tz: preset.timeZone,
        );
      }
      await WeatherService.fetchWeather(cityOverride: cityText);
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Clock design, theme & settings updated!'),
              ),
            ],
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeDesign = _activeDesign;
    final activeTheme = _activeTheme;

    final availableDesigns = _isAnalog
        ? ClockThemeService.analogDesigns
        : ClockThemeService.digitalDesigns;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: Container(
        width: min(680.0, MediaQuery.of(context).size.width - 32),
        constraints: BoxConstraints(maxHeight: min(720.0, MediaQuery.of(context).size.height - 40)),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Dialog Header ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: activeTheme.primaryColor.withAlpha(isDark ? 45 : 20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _isAnalog ? Icons.watch_later_rounded : Icons.pin_rounded,
                    color: activeTheme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch Face & Theme Customization',
                        style: AppTheme.getFontStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isAnalog
                            ? 'Customize Analog Clock Designs (Watch Faces) & Colors freely.'
                            : 'Customize Digital Clock Themes (Display Styles) & Colors freely.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
            const SizedBox(height: 14),

            // ── Scrollable Body ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── LIVE CLOCK PREVIEW ──
                    _buildLivePreviewCard(activeDesign, activeTheme, isDark),
                    const SizedBox(height: 20),

                    // ── 1. CLOCK TYPE (ANALOG VS DIGITAL) ──
                    Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 16, color: activeTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          '1. Clock Type',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildChoiceCard(
                            title: 'Analog Clock',
                            subtitle: 'Dial & Hands',
                            icon: Icons.access_time_rounded,
                            isSelected: _isAnalog,
                            isDark: isDark,
                            primaryColor: activeTheme.primaryColor,
                            onTap: () => setState(() => _isAnalog = true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildChoiceCard(
                            title: 'Digital Clock',
                            subtitle: 'Digital Digits & Display',
                            icon: Icons.pin_rounded,
                            isSelected: !_isAnalog,
                            isDark: isDark,
                            primaryColor: activeTheme.primaryColor,
                            onTap: () => setState(() => _isAnalog = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // ── 2. DYNAMIC DESIGNS LIST (MATCHES ACTIVE CLOCK TYPE) ──
                    Row(
                      children: [
                        Icon(Icons.style_rounded, size: 16, color: activeTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          _isAnalog
                              ? '2. Analog Clock Designs (Watch Faces)'
                              : '2. Digital Clock Themes (Display Designs)',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isAnalog
                          ? 'Select any watch face below. The live preview updates instantly.'
                          : 'Select any digital display theme below. The live preview updates instantly.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.1,
                      ),
                      itemCount: availableDesigns.length,
                      itemBuilder: (context, index) {
                        final design = availableDesigns[index];
                        final isSelected = _isAnalog
                            ? _selectedAnalogDesignId == design.id
                            : _selectedDigitalDesignId == design.id;

                        return RepaintBoundary(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_isAnalog) {
                                  _selectedAnalogDesignId = design.id;
                                } else {
                                  _selectedDigitalDesignId = design.id;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? design.primaryColor.withAlpha(isDark ? 45 : 18)
                                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? design.cardBorderColor
                                      : (isDark ? Colors.white12 : Colors.grey.shade300),
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: design.cardShadowColor,
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? design.primaryColor
                                          : (isDark ? Colors.white10 : Colors.grey.shade200),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      design.icon,
                                      size: 20,
                                      color: isSelected ? Colors.white : design.primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          design.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          design.description,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: isSelected ? design.accentColor : Colors.grey.shade600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded, size: 18, color: design.cardBorderColor),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),

                    // ── 3. CLOCK FORMAT & OPTIONS ──
                    Row(
                      children: [
                        Icon(Icons.settings_suggest_rounded, size: 16, color: activeTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          '3. Format & Seconds',
                          style: AppTheme.getFontStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('12-Hour Format (AM / PM)', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        _is24Hour ? 'Currently 24-Hour (13:00)' : 'Currently 12-Hour (01:00 PM)',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: !_is24Hour,
                      activeThumbColor: activeTheme.primaryColor,
                      onChanged: (val) => setState(() => _is24Hour = !val),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Seconds Ticking (:ss)', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('Live second hand / ticking seconds', style: TextStyle(fontSize: 11)),
                      value: _showSeconds,
                      activeThumbColor: activeTheme.primaryColor,
                      onChanged: (val) => setState(() => _showSeconds = val),
                    ),
                    const SizedBox(height: 20),

                    // ── 4. WEATHER LOCATION ──
                    RepaintBoundary(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_city_rounded, size: 16, color: activeTheme.primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                '4. Weather Location',
                                style: AppTheme.getFontStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _cityCtrl,
                            decoration: InputDecoration(
                              labelText: 'City Name',
                              hintText: 'e.g. Deoband, Delhi, Karachi, Mumbai, Lucknow',
                              prefixIcon: Icon(Icons.location_city_rounded, color: activeTheme.primaryColor),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            children: ['Deoband', 'Delhi', 'Karachi', 'Mumbai', 'Lucknow', 'Lahore'].map((city) {
                              return ActionChip(
                                label: Text(city, style: const TextStyle(fontSize: 11)),
                                onPressed: () => setState(() => _cityCtrl.text = city),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Footer Actions ──
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activeTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save & Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _handleSave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Interactive Live Clock Preview Card
  Widget _buildLivePreviewCard(ClockDesign design, ClockTheme theme, bool isDark) {
    return RepaintBoundary(
      child: ValueListenableBuilder<DateTime>(
        valueListenable: _clockTicker,
        builder: (context, now, _) {
          final dateStr = DateFormat('EEE, dd MMM yyyy').format(now);

          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? design.cardBgDark : design.cardBgLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: design.cardBorderColor.withAlpha(isDark ? 110 : 80),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: design.cardShadowColor,
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.remove_red_eye_rounded, size: 15, color: design.accentColor),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _isAnalog ? 'Live Analog Preview' : 'Live Digital Preview',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: design.accentColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: design.primaryColor.withAlpha(isDark ? 50 : 25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        design.name,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : design.primaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 115,
                        height: 115,
                        child: RepaintBoundary(
                          child: _isAnalog
                              ? CustomPaint(
                                  painter: AnalogClockPainter(
                                    dateTime: now,
                                    isDark: isDark,
                                    design: design,
                                    theme: theme,
                                  ),
                                )
                              : DigitalClockFace(
                                  dateTime: now,
                                  isDark: isDark,
                                  design: design,
                                  size: 115,
                                  is24Hour: _is24Hour,
                                  showSeconds: _showSeconds,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            design.name,
                            style: AppTheme.getFontStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? design.textColorDark : design.textColorLight,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            design.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 13, color: design.accentColor),
                              const SizedBox(width: 5),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChoiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required Color primaryColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withAlpha(isDark ? 50 : 20)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : Colors.grey,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
