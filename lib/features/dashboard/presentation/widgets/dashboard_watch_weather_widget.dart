import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/clock_theme_service.dart';
import '../../../../core/services/salat_time_service.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/app_date_helper.dart';
import '../../../settings/presentation/screens/salat_timings_settings_screen.dart';
import '../../../settings/presentation/widgets/watch_weather_settings_dialog.dart';
import 'analog_clock_painter.dart';
import 'digital_clock_painter.dart';

class DashboardWatchWeatherWidget extends StatefulWidget {
  final bool isDark;
  final String hijriDate;

  const DashboardWatchWeatherWidget({
    super.key,
    required this.isDark,
    required this.hijriDate,
  });

  @override
  State<DashboardWatchWeatherWidget> createState() => _DashboardWatchWeatherWidgetState();
}

class _DashboardWatchWeatherWidgetState extends State<DashboardWatchWeatherWidget> {
  static const _prefKeyIsAnalog = 'dashboard_is_analog_clock';
  static const _prefKey24Hour = 'dashboard_is_24_hour';
  static const _prefKeyShowSeconds = 'dashboard_show_seconds';
  bool _isAnalog = true;
  bool _is24Hour = false;
  bool _showSeconds = false;
  DateTime _now = DateTime.now();
  Timer? _timer;
  late final ValueNotifier<DateTime> _clockTicker;
  int _lastMinute = -1;

  WeatherData? _weather;
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    _clockTicker = ValueNotifier<DateTime>(_now);
    _lastMinute = _now.minute;
    _loadClockMode();
    _startClockTimer();
    _loadWeather();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTicker.dispose();
    super.dispose();
  }

  void _startClockTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now();
      _clockTicker.value = now;
      if (now.minute != _lastMinute) {
        _lastMinute = now.minute;
        setState(() {
          _now = now;
        });
      }
    });
  }

  Future<void> _loadClockMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isAnalog = prefs.getBool(_prefKeyIsAnalog) ?? true;
        _is24Hour = prefs.getBool(_prefKey24Hour) ?? false;
        _showSeconds = prefs.getBool(_prefKeyShowSeconds) ?? false;
      });
    }
  }

  Future<void> _toggleClockMode() async {
    final newMode = !_isAnalog;
    setState(() => _isAnalog = newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyIsAnalog, newMode);
  }

  Future<void> _loadWeather({String? city}) async {
    setState(() => _isLoadingWeather = true);
    // Load cache first for instant UI
    final cached = await WeatherService.getCachedWeather();
    if (cached != null && mounted && _weather == null) {
      setState(() => _weather = cached);
    }
    // Fetch live
    try {
      final fresh = await WeatherService.fetchWeather(cityOverride: city);
      if (mounted) {
        setState(() {
          _weather = fresh;
          _isLoadingWeather = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _showChangeCityDialog() async {
    final currentCity = _weather?.cityName ?? await WeatherService.getSavedCity();
    final ctrl = TextEditingController(text: currentCity);

    if (!mounted) {
      ctrl.dispose();
      return;
    }
    final selectedCity = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Row(
          children: [
            const Icon(Icons.location_city_rounded, color: Color(0xFF0D6B4E), size: 22),
            const SizedBox(width: 8),
            Text(
              context.tr('change_weather_city'),
              style: AppTheme.getFontStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: RepaintBoundary(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('enter_city_weather'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.tr('city_name_hint'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D6B4E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(context.tr('apply')),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (selectedCity != null && selectedCity.isNotEmpty) {
      final preset = SalatTimeService.findPresetCity(selectedCity);
      if (preset != null) {
        await SalatTimeService.setCityAndCoordinates(
          preset.name,
          preset.latitude,
          preset.longitude,
          tz: preset.timeZone,
        );
      }
      _loadWeather(city: selectedCity);
    }
  }

  @override
  Widget build(BuildContext context) {
    final langCode = Localizations.localeOf(context).languageCode;
    final dateStr = AppDateHelper.formatGregorian(_now, langCode);

    return ValueListenableBuilder<ClockDesign>(
      valueListenable: ClockThemeService.currentAnalogDesignNotifier,
      builder: (context, analogDesign, _) {
        return ValueListenableBuilder<ClockDesign>(
          valueListenable: ClockThemeService.currentDigitalDesignNotifier,
          builder: (context, digitalDesign, _) {
            final currentDesign = _isAnalog ? analogDesign : digitalDesign;
            final currentTheme = ClockTheme.fromDesign(currentDesign);

            return ValueListenableBuilder<List<SalatPrayer>>(
              valueListenable: SalatTimeService.prayersNotifier,
              builder: (context, prayers, _) {
                final nextPrayerInfo = SalatTimeService.getNextPrayer(_now);

                return LayoutBuilder(
                  builder: (context, _) {
                    final barContent = Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── 1. The Isolated Watch Face (140x140 with RepaintBoundary) ──
                        _buildWatchFace(currentDesign, currentTheme),

                        const SizedBox(width: 18),

                        // ── 2. Integrated Info: 2 Spacious Rows (Large, prominent text filling the banner!) ──
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Row 1: Gregorian Date + Hijri Date + Action Buttons
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildGregorianPill(dateStr),
                                if (widget.hijriDate.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  _buildHijriPill(widget.hijriDate),
                                ],
                                const SizedBox(width: 10),
                                _buildActionButtons(currentDesign),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Row 2: Next Salat + Live Weather Pills
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (nextPrayerInfo != null) ...[
                                  _buildNextSalatPill(nextPrayerInfo, currentTheme),
                                  const SizedBox(width: 10),
                                ],
                                _buildWeatherPill(),
                              ],
                            ),
                          ],
                        ),
                      ],
                    );

                    return FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: barContent,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// 1. Banner-Spanning Watch Face (Pure Round Shape, 140px diameter, GPU-isolated)
  Widget _buildWatchFace(
    ClockDesign design,
    ClockTheme theme,
  ) {
    const clockSize = 140.0;

    return RepaintBoundary(
      child: ValueListenableBuilder<DateTime>(
        valueListenable: _clockTicker,
        builder: (context, currentTime, _) {
          if (_isAnalog) {
            return Container(
              width: clockSize,
              height: clockSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(90),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipOval(
                child: CustomPaint(
                  size: const Size(clockSize, clockSize),
                  painter: AnalogClockPainter(
                    dateTime: currentTime,
                    isDark: true,
                    design: design,
                    theme: theme,
                  ),
                ),
              ),
            );
          } else {
            return Container(
              width: clockSize,
              height: clockSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(110),
                    blurRadius: 12,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DigitalClockFace(
                  dateTime: currentTime,
                  isDark: true,
                  design: design,
                  size: clockSize,
                  is24Hour: _is24Hour,
                  showSeconds: _showSeconds,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  /// 2. Action Buttons (Settings Dialog, Analog/Digital toggle, Refresh)
  Widget _buildActionButtons(ClockDesign design) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Settings Dialog
        Tooltip(
          message: context.tr('watch_salat_settings'),
          child: InkWell(
            onTap: () async {
              await WatchWeatherSettingsDialog.show(context);
              _loadClockMode();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
              ),
              child: const Icon(Icons.tune_rounded, size: 17, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 5),
        // Toggle Analog / Digital
        Tooltip(
          message: _isAnalog
              ? context.tr('switch_to_digital')
              : context.tr('switch_to_analog'),
          child: InkWell(
            onTap: _toggleClockMode,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
              ),
              child: Icon(
                _isAnalog ? Icons.pin_rounded : Icons.schedule_rounded,
                size: 17,
                color: const Color(0xFFFFD700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 5),
        // Refresh Weather
        Tooltip(
          message: context.tr('refresh_weather'),
          child: InkWell(
            onTap: _isLoadingWeather ? null : () => _loadWeather(),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
              ),
              child: _isLoadingWeather
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded, size: 17, color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }

  /// 3. Next Salat Pill
  Widget _buildNextSalatPill(NextPrayerInfo info, ClockTheme theme) {
    final isZawal = SalatTimeService.isZawalPeriod(_now);
    if (isZawal) {
      return InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalatTimingsSettingsScreen()),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withAlpha(95), width: 1.1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.redAccent),
              const SizedBox(width: 6),
              Text(
                context.tr('zawal_period_prohibited'),
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final langCode = Localizations.localeOf(context).languageCode;
    final p = info.prayer;
    final prayerKey = 'prayer_${p.name.toLowerCase()}';
    final localizedPrayer = context.tr(prayerKey) != prayerKey ? context.tr(prayerKey) : p.name;
    final jamatFormatted = AppDateHelper.formatJamatTime(p.jamatTime, langCode, is24Hour: _is24Hour);
    final remainingFormatted = AppDateHelper.formatTimeRemaining(info.timeRemaining, langCode);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalatTimingsSettingsScreen()),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(p.icon, size: 18, color: const Color(0xFFFFD700)),
            const SizedBox(width: 7),
            Text(
              '${context.tr('next_prayer')}: $localizedPrayer',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '• $jamatFormatted',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withAlpha(225),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withAlpha(55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                remainingFormatted,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFD700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 4. Live Weather Pill
  Widget _buildWeatherPill() {
    final weather = _weather;
    final conditionText = AppDateHelper.localizeWeatherCondition(context, weather?.condition);
    return InkWell(
      onTap: _showChangeCityDialog,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              weather?.icon ?? Icons.wb_sunny_rounded,
              size: 19,
              color: const Color(0xFFFFD700),
            ),
            const SizedBox(width: 6),
            Text(
              weather != null ? '${weather.temperature.toStringAsFixed(0)}°C' : '--°C',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              conditionText,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Colors.white.withAlpha(220),
              ),
            ),
            const SizedBox(width: 7),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_on_rounded, size: 13, color: Colors.white.withAlpha(180)),
                const SizedBox(width: 3),
                Text(
                  weather?.cityName ?? context.tr('city'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withAlpha(210),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
            if (weather != null) ...[
              const SizedBox(width: 7),
              Icon(Icons.water_drop_rounded, size: 12, color: Colors.lightBlueAccent.shade100),
              const SizedBox(width: 3),
              Text(
                '${weather.humidity}%',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withAlpha(200)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 5. Gregorian Date Pill
  Widget _buildGregorianPill(String dateStr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(45), width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, color: Colors.white.withAlpha(210), size: 17),
          const SizedBox(width: 7),
          Text(
            dateStr,
            style: AppTheme.getFontStyle(
              fontSize: 15.5,
              color: Colors.white.withAlpha(240),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 6. Hijri Date Pill
  Widget _buildHijriPill(String hijriDate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withAlpha(50),
            const Color(0xFFFFA000).withAlpha(35),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFD700).withAlpha(80), width: 1.1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mosque_rounded, color: Color(0xFFFFD700), size: 18),
          const SizedBox(width: 7),
          Text(
            hijriDate,
            style: AppTheme.getFontStyle(
              fontSize: 16,
              color: const Color(0xFFFFD700),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }


  // ignore: unused_element
  Widget _buildNextSalatBadge(NextPrayerInfo info, ClockTheme theme, bool isCardDark) {
    final isZawal = SalatTimeService.isZawalPeriod(_now);
    if (isZawal) {
      return InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalatTimingsSettingsScreen()),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withAlpha(isCardDark ? 40 : 15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.red.withAlpha(isCardDark ? 80 : 50),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Zawal Period • Prohibited Time',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(isCardDark ? 80 : 35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Prohibited Time',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final p = info.prayer;
    final hours = info.timeRemaining.inHours;
    final minutes = info.timeRemaining.inMinutes % 60;
    final remainingStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    final jamatFormatted = SalatTimeService.formatTime(p.jamatTime);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalatTimingsSettingsScreen()),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.primaryColor.withAlpha(isCardDark ? 40 : 15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.primaryColor.withAlpha(isCardDark ? 80 : 45),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(p.icon, size: 14, color: theme.primaryColor),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Next: ${p.name}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isCardDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '• $jamatFormatted',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.primaryColor.withAlpha(isCardDark ? 85 : 40),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'in $remainingStr',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isCardDark ? Colors.white : theme.primaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAnalogSection(
    ClockDesign design,
    ClockTheme theme,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
    bool isCardDark,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableW = constraints.maxWidth;
        // Adaptive clock dial size: standard 146px on desktop/card width >= 320px, scales down on ultra narrow widths
        final clockDialSize = (availableW < 320) ? 120.0 : 146.0;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Analog Clock Dial with Active Design & Theme (Enlarged size)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: clockDialSize,
                height: clockDialSize,
                child: CustomPaint(
                  painter: AnalogClockPainter(
                    dateTime: _now,
                    isDark: isCardDark,
                    design: design,
                    theme: theme,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Accompanying Watch Details & Dates (Digital watch digits removed)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              // Design Badge with Icon & Name
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withAlpha(isCardDark ? 40 : 20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.primaryColor.withAlpha(isCardDark ? 80 : 40),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(design.icon, size: 12, color: theme.accentColor),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        design.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.accentColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Urdu Name
              Text(
                design.urduName,
                style: TextStyle(
                  fontFamily: 'JameelNooriNastaleeq',
                  fontSize: 13,
                  color: isCardDark ? Colors.white70 : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // Gregorian Date
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 13,
                    color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (widget.hijriDate.isNotEmpty) ...[
                const SizedBox(height: 5),
                // Hijri Date
                Row(
                  children: [
                    Icon(
                      Icons.nights_stay_rounded,
                      size: 13,
                      color: theme.accentColor,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        widget.hijriDate,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.accentColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  },
);
  }

  // ignore: unused_element
  Widget _buildDigitalSection(
    ClockDesign design,
    ClockTheme theme,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
    bool isCardDark,
  ) {
    switch (design.id) {
      case 'digital_white_led_status':
        return _buildWhiteLedStatusCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_red_led_leaf_md':
        return _buildRedLedLeafMdCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_cyan_weather_schedule':
        return _buildCyanWeatherScheduleCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_dot_matrix_white':
        return _buildDotMatrixWhiteCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_eink_paper_md':
        return _buildEinkPaperMdCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_green_flip_md':
      case 'digital_flip_retro':
        return _buildGreenFlipMdCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_binary_matrix_amber':
      case 'digital_cyber_neon':
        return _buildBinaryMatrixAmberCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
      case 'digital_cyan_vfd':
      case 'digital_masjid_led':
      case 'digital_arabic_calligraphy':
      case 'digital_sport_hud':
      case 'digital_minimalist_oled':
      default:
        return _buildCyanVfdCard(design, theme, isCardDark, dateStr, timeStr, secStr, amPmStr);
    }
  }

  /// 1. White LED & Status Icons
  Widget _buildWhiteLedStatusCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151921),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
        boxShadow: const [
          BoxShadow(color: Color(0x33D4AF37), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.watch_later_outlined, size: 12, color: Color(0xFFD4AF37)),
              SizedBox(width: 5),
              Text(
                'MD GROUP • WHITE LED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFD4AF37),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.white70, blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 0.8),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Colored Status Icons Bar (Calendar / Sun / Mosque)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 4,
            children: [
              _buildMiniStatusBadge(Icons.calendar_today_rounded, const Color(0xFF38BDF8), dateStr),
              if (_weather != null)
                _buildMiniStatusBadge(
                  Icons.wb_sunny_rounded,
                  Colors.amber,
                  '${_weather!.temperature.toStringAsFixed(0)}°C',
                ),
              if (widget.hijriDate.isNotEmpty)
                _buildMiniStatusBadge(Icons.mosque_rounded, const Color(0xFF10B981), widget.hijriDate),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusBadge(IconData icon, Color color, String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withAlpha(60), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 2. Red LED Leaf & MD Group
  Widget _buildRedLedLeafMdCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0505),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDC2626), width: 1.8),
        boxShadow: const [
          BoxShadow(color: Color(0x44DC2626), blurRadius: 14, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Green Leaf Emblem at Top Center
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 1,
                width: 30,
                color: const Color(0xFFDC2626).withAlpha(80),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.eco_rounded, size: 14, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 8),
              Container(
                height: 1,
                width: 30,
                color: const Color(0xFFDC2626).withAlpha(80),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Glowing Red 7-Segment Time
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFEF4444),
                  shadows: [
                    Shadow(color: Color(0xFFEF4444), blurRadius: 14),
                    Shadow(color: Color(0xFFB91C1C), blurRadius: 24),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF87171),
                  shadows: [
                    Shadow(color: Color(0xFFEF4444), blurRadius: 10),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withAlpha(45),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFEF4444), width: 0.8),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFEE2E2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Centered Gold MD GROUP Logo
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.star_rounded, size: 10, color: Color(0xFFD4AF37)),
              SizedBox(width: 4),
              Text(
                'MD GROUP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFD4AF37),
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.star_rounded, size: 10, color: Color(0xFFD4AF37)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.hijriDate.isNotEmpty ? '${widget.hijriDate} • $dateStr' : dateStr,
            style: const TextStyle(fontSize: 10, color: Color(0xFFFCA5A5)),
          ),
        ],
      ),
    );
  }

  /// 3. Cyan Dual Dashboard
  Widget _buildCyanWeatherScheduleCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF071C24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF06B6D4), width: 1.8),
        boxShadow: const [
          BoxShadow(color: Color(0x4406B6D4), blurRadius: 14, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header with Leaf + MD Group Dashboard
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: const [
                    Icon(Icons.eco_rounded, size: 12, color: Color(0xFF34D399)),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'MD GROUP DASHBOARD',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF22D3EE),
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withAlpha(40),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Color(0xFF67E8F9)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF22D3EE),
                  shadows: [
                    Shadow(color: Color(0xFF06B6D4), blurRadius: 14),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF67E8F9),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Dual Schedule Badges (Matching 19:30 | 12:00 in image)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF06B6D4).withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF06B6D4).withAlpha(80), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.nightlight_round, size: 10, color: Color(0xFF22D3EE)),
                    SizedBox(width: 4),
                    Text(
                      '19:30 Isha',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFCFFAFE)),
                    ),
                  ],
                ),
              ),
              const Text('|', style: TextStyle(color: Color(0xFF06B6D4), fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.amber.withAlpha(80), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.wb_sunny_rounded, size: 10, color: Colors.amber),
                    SizedBox(width: 4),
                    Text(
                      '12:00 Zohr',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 4. Dot Matrix White LED
  Widget _buildDotMatrixWhiteCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    final activeDotIndex = (_now.second / 5).floor() % 12;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1219),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.8),
        boxShadow: const [
          BoxShadow(color: Color(0x33D4AF37), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                '● MD GROUP DOT-MATRIX ●',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4AF37),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2.5,
                  shadows: [
                    Shadow(color: Colors.white60, blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white38, width: 0.8),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 12 Dot LED Progress Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(12, (i) {
              final isLit = i <= activeDotIndex;
              return Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLit ? const Color(0xFFD4AF37) : Colors.white12,
                  boxShadow: isLit
                      ? const [BoxShadow(color: Color(0xFFD4AF37), blurRadius: 4)]
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ],
      ),
    );
  }

  /// 5. White E-Ink Paper Dial
  Widget _buildEinkPaperMdCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2.0),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.diamond_rounded, size: 10, color: Color(0xFFB45309)),
              SizedBox(width: 4),
              Text(
                'MD GROUP E-INK DISPLAY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB45309),
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.diamond_rounded, size: 10, color: Color(0xFFB45309)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1C1917),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF78350F),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1917),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.hijriDate.isNotEmpty ? '${widget.hijriDate} • $dateStr' : dateStr,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF44403C)),
          ),
        ],
      ),
    );
  }

  /// 6. Green Luxury Split-Flap
  Widget _buildGreenFlipMdCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    final parts = timeStr.split(':');
    final hourPart = parts.isNotEmpty ? parts[0] : '00';
    final minPart = parts.length > 1 ? parts[1] : '00';

    Widget buildFlipTile(String text) {
      return Container(
        width: 58,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF063B29),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFFFDE047),
                letterSpacing: 2,
              ),
            ),
            // Horizontal split slit line across middle of flap
            Positioned(
              left: 0,
              right: 0,
              child: Container(
                height: 1.2,
                color: const Color(0xFF032218),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF082B1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4AF37), width: 2.0),
        boxShadow: const [
          BoxShadow(color: Color(0x44D4AF37), blurRadius: 12, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.eco_rounded, size: 12, color: Color(0xFFD4AF37)),
              SizedBox(width: 4),
              Text(
                'MD GROUP LUXURY FLIP',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFD4AF37),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              buildFlipTile(hourPart),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFFDE047))),
              ),
              buildFlipTile(minPart),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      amPmStr,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF082B1E)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    ':$secStr s',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFDE047)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(dateStr, style: const TextStyle(fontSize: 10, color: Color(0xFFD1FAE5))),
        ],
      ),
    );
  }

  /// 7. Binary Matrix Terminal
  Widget _buildBinaryMatrixAmberCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF080D12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF97316), width: 1.8),
        boxShadow: const [
          BoxShadow(color: Color(0x33F97316), blurRadius: 14, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                '>_ MD_GROUP // SYS_01',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
              Text(
                'LIVE_FEED',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF97316),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Subtle Binary Watermark Line
          const Text(
            '01001101 01000100 00100000 01010011 01011001 01010011',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 8,
              color: Color(0x3310B981),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF97316),
                  shadows: [
                    Shadow(color: Color(0xFFEA580C), blurRadius: 14),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFDBA74),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  amPmStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'SYS_TIMESTAMP: $dateStr',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 9.5,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  /// 8. Electric Cyan VFD
  Widget _buildCyanVfdCard(
    ClockDesign design,
    ClockTheme theme,
    bool isDark,
    String dateStr,
    String timeStr,
    String secStr,
    String amPmStr,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF041217),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF06B6D4), width: 2.0),
        boxShadow: const [
          BoxShadow(color: Color(0x4406B6D4), blurRadius: 16, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                '[ VFD TUBE // MD GROUP ]',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF06B6D4),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '[ $timeStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF22D3EE),
                  shadows: [
                    Shadow(color: Color(0xFF06B6D4), blurRadius: 12),
                    Shadow(color: Color(0xFF22D3EE), blurRadius: 22),
                  ],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                ':$secStr',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF67E8F9),
                  shadows: [
                    Shadow(color: Color(0xFF06B6D4), blurRadius: 10),
                  ],
                ),
              ),
              Text(
                ' $amPmStr ]',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF06B6D4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.hijriDate.isNotEmpty ? '${widget.hijriDate} • $dateStr' : dateStr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFF67E8F9),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildWeatherSection(bool isCardDark) {
    final weather = _weather;

    return Row(
      children: [
        // Weather Icon with animated/colored circle
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.amber.withAlpha(isCardDark ? 40 : 20),
            shape: BoxShape.circle,
          ),
          child: Icon(
            weather?.icon ?? Icons.wb_sunny_rounded,
            color: Colors.amber.shade700,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),

        // Temperature & Condition
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    weather != null ? '${weather.temperature.toStringAsFixed(0)}°C' : '--°C',
                    style: AppTheme.getFontStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isCardDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      weather?.condition ?? 'Loading...',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              // City with Edit button
              InkWell(
                onTap: _showChangeCityDialog,
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 11,
                      color: isCardDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 2),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        weather?.cityName ?? 'Set Location',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade600,
                          decoration: TextDecoration.underline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.edit_rounded,
                      size: 9,
                      color: isCardDark ? const Color(0xFF94A3B8) : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Humidity & Wind Stats
        if (weather != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop_rounded, size: 10, color: Colors.blue),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.humidity}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.air_rounded, size: 10, color: Colors.teal),
                  const SizedBox(width: 2),
                  Text(
                    '${weather.windSpeed.toStringAsFixed(0)} km/h',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isCardDark ? const Color(0xFFCBD5E1) : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}
