import 'package:flutter/material.dart';
import '../../../../core/services/prayer_calculation_engine.dart';
import '../../../../core/services/salat_time_service.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_theme.dart';

class SalatTimingsSettingsScreen extends StatefulWidget {
  const SalatTimingsSettingsScreen({super.key});

  @override
  State<SalatTimingsSettingsScreen> createState() => _SalatTimingsSettingsScreenState();
}

class _SalatTimingsSettingsScreenState extends State<SalatTimingsSettingsScreen> {
  bool _isAuto = true;
  CalculationMethod _method = CalculationMethod.karachi;
  JuristicMethod _juristic = JuristicMethod.hanafi;
  String _cityName = 'Deoband';
  double _lat = 29.6976;
  double _lon = 77.6749;
  double _tz = 5.5;
  String _jamatMode = 'offset';
  Map<String, int> _jamatOffsets = {};
  Map<String, int> _minuteAdjustments = {};
  late List<SalatPrayer> _manualPrayers;

  bool _hasChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  void _loadAllSettings() {
    _isAuto = SalatTimeService.isAutoCalculation;
    _method = SalatTimeService.calculationMethod;
    _juristic = SalatTimeService.juristicMethod;
    _cityName = SalatTimeService.cityName;
    _lat = SalatTimeService.latitude;
    _lon = SalatTimeService.longitude;
    _tz = SalatTimeService.timeZone;
    _jamatMode = SalatTimeService.jamatMode;
    _jamatOffsets = Map<String, int>.from(SalatTimeService.jamatOffsets);
    _minuteAdjustments = Map<String, int>.from(SalatTimeService.minuteAdjustments);

    _manualPrayers = SalatTimeService.prayers.map((p) {
      return SalatPrayer(
        id: p.id,
        name: p.name,
        urduName: p.urduName,
        arabicName: p.arabicName,
        azanTime: p.azanTime,
        jamatTime: p.jamatTime,
        icon: p.icon,
        isPrayer: p.isPrayer,
      );
    }).toList();

    _hasChanges = false;
  }

  Future<void> _applyCityChange(String name, double lat, double lon, double tz) async {
    setState(() {
      _cityName = name;
      _lat = lat;
      _lon = lon;
      _tz = tz;
      _hasChanges = true;
    });

    // Apply to service immediately so calculations update across the app
    await SalatTimeService.setCityAndCoordinates(name, lat, lon, tz: tz);
    // Background weather fetch to keep condition updated
    WeatherService.fetchWeather(cityOverride: name);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Location set to $name! Prayer times recalculated. ($name کے اوقاتِ نماز اپڈیٹ ہو گئے ہیں)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0D6B4E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _saveAll() async {
    setState(() => _isSaving = true);
    try {
      await SalatTimeService.setAutoCalculation(_isAuto);
      await SalatTimeService.setCalculationMethod(_method);
      await SalatTimeService.setJuristicMethod(_juristic);
      await SalatTimeService.setCityAndCoordinates(_cityName, _lat, _lon, tz: _tz);
      await SalatTimeService.setJamatConfig(mode: _jamatMode, offsets: _jamatOffsets);
      await SalatTimeService.setMinuteAdjustments(_minuteAdjustments);

      if (!_isAuto) {
        await SalatTimeService.saveManualPrayers(_manualPrayers);
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasChanges = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Salat timings & calculation settings saved! اوقاتِ نماز محفوظ کر لیے گئے ہیں',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Color(0xFF0D6B4E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save settings: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showCityPickerDialog() {
    final ctrl = TextEditingController(text: _cityName);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            title: Row(
              children: [
                const Icon(Icons.location_city_rounded, color: Color(0xFF0D6B4E), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Select City / مقام منتخب کریں',
                  style: AppTheme.getFontStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose a standard Islamic city or type any custom city worldwide:',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      autofocus: false,
                      decoration: InputDecoration(
                        labelText: 'City Name (شہر کا نام)',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.my_location_rounded, size: 18),
                          tooltip: 'Auto-detect from Weather Location',
                          onPressed: () async {
                            final w = await WeatherService.getCachedWeather();
                            if (w != null) {
                              setDialogState(() {
                                ctrl.text = w.cityName;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Standard Presets (معروف اسلامی مراکز):',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: SalatTimeService.standardCities.map((c) {
                        final isSelected = _cityName.toLowerCase() == c.name.toLowerCase();
                        return ActionChip(
                          avatar: isSelected
                              ? const Icon(Icons.check, size: 14, color: Colors.white)
                              : null,
                          label: Text('${c.name} (${c.urduName})'),
                          backgroundColor: isSelected
                              ? const Color(0xFF0D6B4E)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: isSelected ? Colors.white : (isDark ? Colors.white : Colors.black87),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _applyCityChange(c.name, c.latitude, c.longitude, c.timeZone);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6B4E)),
                onPressed: () async {
                  final input = ctrl.text.trim();
                  if (input.isNotEmpty) {
                    Navigator.pop(ctx);
                    final preset = SalatTimeService.findPresetCity(input);
                    if (preset != null) {
                      _applyCityChange(preset.name, preset.latitude, preset.longitude, preset.timeZone);
                    } else {
                      // Geocode city dynamically using WeatherService
                      try {
                        final geo = await WeatherService.geocodeCity(input);
                        if (geo != null) {
                          final lat = geo['lat'] as double;
                          final lon = geo['lon'] as double;
                          final name = geo['name'] as String;
                          final tz = geo['tz'] as double? ?? 5.5;
                          _applyCityChange(name, lat, lon, tz);
                        } else {
                          _applyCityChange(input, _lat, _lon, _tz);
                        }
                      } catch (_) {
                        _applyCityChange(input, _lat, _lon, _tz);
                      }
                    }
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _adjustOffset(String id, int delta) {
    setState(() {
      final current = _jamatOffsets[id] ?? 20;
      final newVal = (current + delta).clamp(0, 120);
      _jamatOffsets[id] = newVal;
      _hasChanges = true;
    });
    // Immediately reflect on service
    SalatTimeService.setJamatConfig(mode: _jamatMode, offsets: _jamatOffsets);
  }

  void _adjustMinute(String id, int delta) {
    setState(() {
      final current = _minuteAdjustments[id] ?? 0;
      final newVal = (current + delta).clamp(-30, 30);
      _minuteAdjustments[id] = newVal;
      _hasChanges = true;
    });
    SalatTimeService.setMinuteAdjustments(_minuteAdjustments);
  }

  Future<void> _pickManualTime(SalatPrayer prayer, bool isAzan) async {
    final initial = isAzan ? prayer.azanTime : prayer.jamatTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: '${prayer.name} (${prayer.urduName}) - ${isAzan ? "Azan Time" : "Jamat Time"}',
    );

    if (picked != null) {
      setState(() {
        if (isAzan) {
          prayer.azanTime = picked;
        } else {
          prayer.jamatTime = picked;
        }
        _hasChanges = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final todaySchedule = PrayerCalculationEngine.calculate(
      date: DateTime.now(),
      latitude: _lat,
      longitude: _lon,
      timeZoneOffsetHours: _tz,
      method: _method,
      juristic: _juristic,
      minuteAdjustments: _minuteAdjustments,
    );

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Salat & Jamat Timings (نماز اور جماعت کے اوقات)'),
        elevation: 0,
        actions: [
          FilledButton.icon(
            onPressed: _hasChanges && !_isSaving ? _saveAll : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save (محفوظ کریں)'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0D6B4E),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.withAlpha(50),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Auto vs Manual Mode Switch Banner ──
            _buildAutoModeSwitchBanner(isDark),
            const SizedBox(height: 18),

            if (_isAuto) ...[
              // ── Location & Coordinates Card ──
              _buildLocationCard(isDark),
              const SizedBox(height: 18),

              // ── Calculation Method & Asr Juristic Card ──
              _buildMethodAndJuristicCard(isDark),
              const SizedBox(height: 18),

              // ── Jamat Policy Card (Offsets) ──
              _buildJamatPolicyCard(isDark),
              const SizedBox(height: 18),

              // ── Complete Islamic Day Schedule Table (Deeniyat Style) ──
              _buildExtendedScheduleTable(todaySchedule, isDark),
              const SizedBox(height: 18),

              // ── Fine-Tuning Adjustments (احتیاطی منٹس) ──
              _buildFineTuningCard(isDark),
            ] else ...[
              // Manual Static Schedule Pickers
              _buildManualScheduleSection(isDark),
            ],

            const SizedBox(height: 24),
            if (_hasChanges)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveAll,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text(
                    'Save All Settings (تمام ترتیبات محفوظ کریں)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D6B4E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoModeSwitchBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0D6B4E).withAlpha(isDark ? 80 : 40),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 6),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D6B4E).withAlpha(isDark ? 40 : 20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF0D6B4E), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Automatic Prayer Times (خودکار حساب برائے مقام)',
                      style: AppTheme.getFontStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Deeniyat Style',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isAuto
                      ? 'Calculates daily prayer times automatically based on astronomical sun position for your city.'
                      : 'Manual Mode: Fixed static prayer times set by the user.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isAuto,
            activeThumbColor: const Color(0xFF0D6B4E),
            onChanged: (val) {
              setState(() {
                _isAuto = val;
                _hasChanges = true;
              });
              SalatTimeService.setAutoCalculation(val);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(isDark ? 40 : 20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.location_on_rounded, color: Colors.blue, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Location & Coordinates (مقام و عرض بلد)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _cityName,
                      style: AppTheme.getFontStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Lat: ${_lat.toStringAsFixed(2)}° • Lon: ${_lon.toStringAsFixed(2)}° (UTC ${_tz >= 0 ? "+$_tz" : "$_tz"})',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _showCityPickerDialog,
            icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
            label: const Text('Change City / مقام بدلیں', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0D6B4E),
              side: const BorderSide(color: Color(0xFF0D6B4E)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodAndJuristicCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: Color(0xFF0D6B4E), size: 20),
              const SizedBox(width: 8),
              Text(
                'Calculation Convention & Juristic Mode (طریقہ حساب اور فقہی مسلک)',
                style: AppTheme.getFontStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Method Selector
          Text(
            'Calculation Convention (معیارِ حساب):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CalculationMethod>(
                value: _method,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                items: CalculationMethod.values.map((m) {
                  final isKarachi = m == CalculationMethod.karachi;
                  return DropdownMenuItem<CalculationMethod>(
                    value: m,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${m.name} (${m.urduName})${isKarachi ? " ★ (Recommended / مستند)" : ""}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isKarachi ? FontWeight.bold : FontWeight.normal,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          m.description,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _method = val;
                      _hasChanges = true;
                    });
                    SalatTimeService.setCalculationMethod(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Asr Juristic Selector
          Row(
            children: [
              Text(
                'Asr Juristic Method (فقہی مسلک برائے عصر):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text('Hanafi (حنفی - 2x Shadow)'),
                selected: _juristic == JuristicMethod.hanafi,
                selectedColor: const Color(0xFF0D6B4E),
                labelStyle: TextStyle(
                  color: _juristic == JuristicMethod.hanafi ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _juristic = JuristicMethod.hanafi;
                      _hasChanges = true;
                    });
                    SalatTimeService.setJuristicMethod(JuristicMethod.hanafi);
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Shafi\'i (شافعی / جمہور - 1x Shadow)'),
                selected: _juristic == JuristicMethod.shafii,
                selectedColor: const Color(0xFF0D6B4E),
                labelStyle: TextStyle(
                  color: _juristic == JuristicMethod.shafii ? Colors.white : null,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                onSelected: (val) {
                  if (val) {
                    setState(() {
                      _juristic = JuristicMethod.shafii;
                      _hasChanges = true;
                    });
                    SalatTimeService.setJuristicMethod(JuristicMethod.shafii);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJamatPolicyCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_rounded, color: Color(0xFF0D6B4E), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Jamat Time Configuration (جماعت کے اوقات کی ترتیب)',
                    style: AppTheme.getFontStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('Offset from Azan (اذان کے بعد وقفہ)'),
                    selected: _jamatMode == 'offset',
                    selectedColor: const Color(0xFF0D6B4E),
                    labelStyle: TextStyle(
                      color: _jamatMode == 'offset' ? Colors.white : null,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _jamatMode = 'offset';
                          _hasChanges = true;
                        });
                        SalatTimeService.setJamatConfig(mode: 'offset', offsets: _jamatOffsets);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Fixed Jamat (مخصوص وقت)'),
                    selected: _jamatMode == 'fixed',
                    selectedColor: const Color(0xFF0D6B4E),
                    labelStyle: TextStyle(
                      color: _jamatMode == 'fixed' ? Colors.white : null,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _jamatMode = 'fixed';
                          _hasChanges = true;
                        });
                        SalatTimeService.setJamatConfig(mode: 'fixed', offsets: _jamatOffsets);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_jamatMode == 'offset') ...[
            Text(
              'Set how many minutes after Azan the Jamat takes place (e.g. Maghrib = 5 min, Isha = 20 min):',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _buildOffsetStepper('fajr', 'Fajr (فجر)', Icons.nights_stay_rounded, isDark),
                _buildOffsetStepper('dhuhr', 'Dhuhr (ظہر)', Icons.wb_sunny_rounded, isDark),
                _buildOffsetStepper('asr', 'Asr (عصر)', Icons.wb_cloudy_rounded, isDark),
                _buildOffsetStepper('maghrib', 'Maghrib (مغرب)', Icons.wb_twilight_rounded, isDark),
                _buildOffsetStepper('isha', 'Isha (عشاء)', Icons.nightlight_round, isDark),
                _buildOffsetStepper('jummah', 'Jummah (جمعہ)', Icons.mosque_rounded, isDark),
              ],
            ),
          ] else ...[
            Text(
              'Azan will calculate automatically by sun position, while Jamat will follow fixed times.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOffsetStepper(String id, String label, IconData icon, bool isDark) {
    final offset = _jamatOffsets[id] ?? 20;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF0D6B4E).withAlpha(isDark ? 60 : 35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF0D6B4E)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 16),
            onPressed: () => _adjustOffset(id, -5),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
          Text(
            '+$offset min',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0D6B4E),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 16),
            onPressed: () => _adjustOffset(id, 5),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildExtendedScheduleTable(CalculatedPrayerTimes sched, bool isDark) {
    String fmt(TimeOfDay t) => SalatTimeService.formatTime(t);

    TimeOfDay getJamat(String id, TimeOfDay azan) {
      if (_jamatMode == 'fixed') {
        final ex = _manualPrayers.firstWhere((p) => p.id == id, orElse: () => _manualPrayers.first);
        return ex.jamatTime;
      }
      final off = _jamatOffsets[id] ?? 20;
      return SalatTimeService.addMinutes(azan, off);
    }

    final items = [
      {'name': 'Sehri End (ختمِ سحری)', 'azan': fmt(sched.sehriEnd), 'jamat': '-', 'color': Colors.indigo, 'icon': Icons.bedtime_rounded},
      {'name': 'Fajr (فجر)', 'azan': fmt(sched.fajr), 'jamat': fmt(getJamat('fajr', sched.fajr)), 'color': const Color(0xFF4338CA), 'icon': Icons.nights_stay_rounded},
      {'name': 'Sunrise (طلوعِ آفتاب)', 'azan': fmt(sched.sunrise), 'jamat': '-', 'color': Colors.amber.shade800, 'icon': Icons.wb_sunny_rounded},
      {'name': 'Ishraq (اشراق)', 'azan': fmt(sched.ishraq), 'jamat': '-', 'color': Colors.amber.shade700, 'icon': Icons.wb_twilight_rounded},
      {'name': 'Chaasht / Duha (چاشت)', 'azan': fmt(sched.chaasht), 'jamat': '-', 'color': Colors.orange, 'icon': Icons.sunny},
      {'name': 'Zawal / Istiwa (زوال - ممنوع وقت)', 'azan': '${fmt(sched.zawalStart)} - ${fmt(sched.zawalEnd)}', 'jamat': 'مکروہ وقت', 'color': Colors.red.shade700, 'icon': Icons.warning_amber_rounded},
      {'name': 'Dhuhr (ظہر)', 'azan': fmt(sched.dhuhr), 'jamat': fmt(getJamat('dhuhr', sched.dhuhr)), 'color': const Color(0xFF0284C7), 'icon': Icons.wb_sunny_rounded},
      {'name': 'Asr (${_juristic.name}) (عصر)', 'azan': fmt(sched.asr), 'jamat': fmt(getJamat('asr', sched.asr)), 'color': const Color(0xFFEA580C), 'icon': Icons.wb_cloudy_rounded},
      {'name': 'Maghrib / Iftaar (مغرب / افطار)', 'azan': fmt(sched.maghrib), 'jamat': fmt(getJamat('maghrib', sched.maghrib)), 'color': const Color(0xFFDC2626), 'icon': Icons.wb_twilight_rounded},
      {'name': 'Isha (عشاء)', 'azan': fmt(sched.isha), 'jamat': fmt(getJamat('isha', sched.isha)), 'color': const Color(0xFF4F46E5), 'icon': Icons.nightlight_round},
      {'name': 'Nisf al-Layl (نصف شب / تہجد)', 'azan': fmt(sched.midnight), 'jamat': '-', 'color': Colors.purple.shade700, 'icon': Icons.dark_mode_rounded},
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 25 : 6),
            blurRadius: 10,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D6B4E).withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.schedule_rounded, color: Color(0xFF0D6B4E), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Today\'s Islamic Schedule (آج کے شرعی اوقات - Deeniyat Timetable)',
                    style: AppTheme.getFontStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6B4E).withAlpha(isDark ? 40 : 15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Auto Computed for $_cityName',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D6B4E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
          const SizedBox(height: 10),

          // Timetable Rows
          ...items.map((row) {
            final color = row['color'] as Color;
            final isZawal = row['name'].toString().contains('Zawal');

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isZawal
                    ? Colors.red.withAlpha(isDark ? 25 : 12)
                    : (isDark ? Colors.transparent : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(8),
                border: isZawal
                    ? Border.all(color: Colors.red.withAlpha(60), width: 1)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(row['icon'] as IconData, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row['name'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isZawal ? FontWeight.bold : FontWeight.w600,
                        color: isZawal
                            ? Colors.red.shade700
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Azan / وقت: ',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        Text(
                          row['azan'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row['jamat'] != '-')
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Jamat: ',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D6B4E).withAlpha(isDark ? 40 : 20),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              row['jamat'] as String,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D6B4E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Expanded(flex: 2, child: SizedBox()),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFineTuningCard(bool isDark) {
    return ExpansionTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      collapsedBackgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      leading: const Icon(Icons.tune_rounded, color: Color(0xFF0D6B4E)),
      title: Text(
        'Minute Safety Adjustments (احتیاطی منٹس / کمی بیشی)',
        style: AppTheme.getFontStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        'Adjust +/- minutes to match your local mosque timetable if needed.',
        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildMinuteStepper('fajr', 'Fajr Offset', isDark),
              _buildMinuteStepper('sunrise', 'Sunrise Offset', isDark),
              _buildMinuteStepper('dhuhr', 'Dhuhr Offset', isDark),
              _buildMinuteStepper('asr', 'Asr Offset', isDark),
              _buildMinuteStepper('maghrib', 'Maghrib Offset', isDark),
              _buildMinuteStepper('isha', 'Isha Offset', isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMinuteStepper(String id, String label, bool isDark) {
    final adj = _minuteAdjustments[id] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove, size: 14),
            onPressed: () => _adjustMinute(id, -1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
          Text(
            '${adj >= 0 ? "+$adj" : "$adj"} min',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: adj == 0 ? Colors.grey : const Color(0xFF0D6B4E),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 14),
            onPressed: () => _adjustMinute(id, 1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildManualScheduleSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Manual Prayer Schedule (دستی اوقات)',
              style: AppTheme.getFontStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Click time to edit / تبدیل کرنے کے لیے وقت پر کلک کریں',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._manualPrayers.map((prayer) => _buildManualPrayerCard(prayer, isDark)),
      ],
    );
  }

  Widget _buildManualPrayerCard(SalatPrayer prayer, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(15) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(prayer.icon, color: const Color(0xFF0D6B4E), size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prayer.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  prayer.urduName,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (prayer.isPrayer) ...[
            InkWell(
              onTap: () => _pickManualTime(prayer, true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Azan: ${SalatTimeService.formatTime(prayer.azanTime)}'),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () => _pickManualTime(prayer, false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D6B4E).withAlpha(isDark ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Jamat: ${SalatTimeService.formatTime(prayer.jamatTime)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D6B4E))),
              ),
            ),
          ] else ...[
            InkWell(
              onTap: () => _pickManualTime(prayer, false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('End: ${SalatTimeService.formatTime(prayer.jamatTime)}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
