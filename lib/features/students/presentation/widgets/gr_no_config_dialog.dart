import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/gr_no_settings.dart';

class GrNoConfigDialog extends StatefulWidget {
  const GrNoConfigDialog({super.key});

  static Future<GrNoSettingsModel?> show(BuildContext context, {Color? barrierColor}) {
    return showDialog<GrNoSettingsModel>(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) => const GrNoConfigDialog(),
    );
  }

  @override
  State<GrNoConfigDialog> createState() => _GrNoConfigDialogState();
}

class _GrNoConfigDialogState extends State<GrNoConfigDialog> {
  bool _isLoading = true;
  late bool _enableAlphabet;
  late TextEditingController _startAlphabetCtrl;
  late TextEditingController _endAlphabetCtrl;
  late TextEditingController _alphabetPrefixCtrl;

  late bool _enableYear;
  late String _yearFormat;
  late TextEditingController _customYearCtrl;

  late TextEditingController _digitPaddingCtrl;
  late TextEditingController _startingNumberCtrl;

  @override
  void initState() {
    super.initState();
    _startAlphabetCtrl = TextEditingController(text: 'A');
    _endAlphabetCtrl = TextEditingController(text: 'Z');
    _alphabetPrefixCtrl = TextEditingController(text: 'A');

    final current2DigitYear = DateFormat('yy').format(DateTime.now());
    _customYearCtrl = TextEditingController(text: current2DigitYear);

    _digitPaddingCtrl = TextEditingController(text: '4');
    _startingNumberCtrl = TextEditingController(text: '1');
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final s = await GrNoSettings.loadSettings();
    final now = DateTime.now();
    final defaultYear = s.yearFormat == '4digit' ? DateFormat('yyyy').format(now) : DateFormat('yy').format(now);

    if (mounted) {
      setState(() {
        _enableAlphabet = s.enableAlphabet;
        _startAlphabetCtrl.text = s.startAlphabet;
        _endAlphabetCtrl.text = s.endAlphabet;
        _alphabetPrefixCtrl.text = s.alphabetPrefix;

        _enableYear = s.enableYear;
        _yearFormat = s.yearFormat;
        _customYearCtrl.text = s.customYearValue.isNotEmpty ? s.customYearValue : defaultYear;

        _digitPaddingCtrl.text = '${s.digitPadding}';
        _startingNumberCtrl.text = '${s.startingNumber}';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _startAlphabetCtrl.dispose();
    _endAlphabetCtrl.dispose();
    _alphabetPrefixCtrl.dispose();
    _customYearCtrl.dispose();
    _digitPaddingCtrl.dispose();
    _startingNumberCtrl.dispose();
    super.dispose();
  }

  GrNoSettingsModel _currentModel() {
    final starting = int.tryParse(_startingNumberCtrl.text) ?? 1;
    final padding = int.tryParse(_digitPaddingCtrl.text) ?? 4;
    return GrNoSettingsModel(
      enableAlphabet: _enableAlphabet,
      startAlphabet: _startAlphabetCtrl.text.trim().isEmpty ? 'A' : _startAlphabetCtrl.text.trim(),
      endAlphabet: _endAlphabetCtrl.text.trim().isEmpty ? 'Z' : _endAlphabetCtrl.text.trim(),
      alphabetPrefix: _alphabetPrefixCtrl.text.trim().isEmpty ? 'A' : _alphabetPrefixCtrl.text.trim(),
      enableYear: _enableYear,
      yearFormat: _yearFormat,
      customYearValue: _customYearCtrl.text.trim(),
      digitPadding: padding >= 0 ? padding : 0,
      startingNumber: starting > 0 ? starting : 1,
    );
  }

  void _updateYearFormat(String fmt) {
    setState(() {
      _yearFormat = fmt;
      final now = DateTime.now();
      if (fmt == '4digit') {
        _customYearCtrl.text = DateFormat('yyyy').format(now);
      } else if (fmt == '2digit') {
        _customYearCtrl.text = DateFormat('yy').format(now);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final model = _currentModel();
    final sampleGrNo = model.buildGrNo(model.startingNumber);
    final prefix = model.buildPrefix();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 16,
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      child: Container(
        width: min(480.0, MediaQuery.of(context).size.width - 32),
        constraints: BoxConstraints(maxHeight: min(720.0, MediaQuery.of(context).size.height - 32)),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── HEADER GRADIENT BANNER ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.settings_suggest_rounded, color: Color(0xFFD4AF37), size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'G.R. NO. FORMAT CONFIGURATOR',
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFD4AF37),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Modular Format Series (A26-0001, 26-0001, 000001...)',
                            style: AppTheme.getFontStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── LIVE SAMPLE PREVIEW CARD ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: isDark ? 0.2 : 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'LIVE G.R. NO. SAMPLE PREVIEW',
                            style: AppTheme.getFontStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : AppTheme.primaryColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F3814) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              sampleGrNo,
                              style: AppTheme.getFontStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : const Color(0xFF0F3814),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            prefix.isNotEmpty
                                ? 'Prefix: "$prefix" | Digits: ${model.digitPadding} | Sequence: "${model.formatSequence(model.startingNumber)}"'
                                : 'No Prefix (Numeric Only) | Digits: ${model.digitPadding} | Sequence: "${model.formatSequence(model.startingNumber)}"',
                            style: AppTheme.getFontStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── PART 1: ALPHABET PREFIX RANGE (START TO END) ──
                    Card(
                      elevation: 0,
                      color: isDark ? const Color(0xFF252538) : Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppTheme.primaryColor,
                              title: Text(
                                'Alphabet Prefix Range',
                                style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Enable letter series with Start & End range (e.g. A to Z)',
                                style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                              ),
                              value: _enableAlphabet,
                              onChanged: (val) => setState(() => _enableAlphabet = val),
                            ),
                            if (_enableAlphabet) ...[
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Start Letter:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          height: 38,
                                          child: TextField(
                                            controller: _startAlphabetCtrl,
                                            textCapitalization: TextCapitalization.characters,
                                            maxLength: 3,
                                            decoration: InputDecoration(
                                              counterText: '',
                                              hintText: 'A',
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onChanged: (val) {
                                              if (_alphabetPrefixCtrl.text.isEmpty) {
                                                _alphabetPrefixCtrl.text = val;
                                              }
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('End Letter:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          height: 38,
                                          child: TextField(
                                            controller: _endAlphabetCtrl,
                                            textCapitalization: TextCapitalization.characters,
                                            maxLength: 3,
                                            decoration: InputDecoration(
                                              counterText: '',
                                              hintText: 'Z',
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Active Letter:', style: AppTheme.getFontStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          height: 38,
                                          child: TextField(
                                            controller: _alphabetPrefixCtrl,
                                            textCapitalization: TextCapitalization.characters,
                                            maxLength: 3,
                                            decoration: InputDecoration(
                                              counterText: '',
                                              hintText: 'A',
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            onChanged: (_) => setState(() {}),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── PART 2: YEAR CODE (DEFAULT CURRENT YEAR & EDITABLE) ──
                    Card(
                      elevation: 0,
                      color: isDark ? const Color(0xFF252538) : Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppTheme.primaryColor,
                              title: Text(
                                'Year Code (Default Current Year)',
                                style: AppTheme.getFontStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'Enable academic year in GR No. Shows current year by default, fully editable.',
                                style: AppTheme.getFontStyle(fontSize: 11, color: Colors.grey),
                              ),
                              value: _enableYear,
                              onChanged: (val) => setState(() => _enableYear = val),
                            ),
                            if (_enableYear) ...[
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(value: '2digit', label: Text('2-Digit')),
                                      ButtonSegment(value: '4digit', label: Text('4-Digit')),
                                    ],
                                    selected: {_yearFormat},
                                    onSelectionChanged: (set) => _updateYearFormat(set.first),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _customYearCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Editable Year',
                                        hintText: 'e.g. 26 or 2026',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── AUTOMATIC HYPHEN INFO BANNER ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF57C00).withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF57C00).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Automatic Hyphen (-): Added after Alphabet/Year (e.g. A26-0001, 26-0001). If neither is enabled, no hyphen is added.',
                              style: AppTheme.getFontStyle(
                                fontSize: 10.5,
                                color: isDark ? Colors.white70 : const Color(0xFFE65100),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── PART 3: CUSTOM DIGIT PADDING LENGTH & START NUMBER ──
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Custom Digit Padding:',
                                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _digitPaddingCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 4 for 0001, 6 for 000001',
                                  labelText: 'Number of Digits',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Starting Sequence:',
                                style: AppTheme.getFontStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _startingNumberCtrl,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'e.g. 1 or 101',
                                  labelText: 'Start Number',
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Quick Digit Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('3 Digits (001)', 3),
                          const SizedBox(width: 6),
                          _buildPresetChip('4 Digits (0001)', 4),
                          const SizedBox(width: 6),
                          _buildPresetChip('5 Digits (00001)', 5),
                          const SizedBox(width: 6),
                          _buildPresetChip('6 Digits (000001)', 6),
                          const SizedBox(width: 6),
                          _buildPresetChip('No Padding (1)', 0),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── ACTION BUTTONS ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.save_rounded, color: Colors.white),
                          label: const Text(
                            'Save & Apply Format',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final newSettings = _currentModel();
                            await GrNoSettings.saveSettings(newSettings);
                            if (context.mounted) {
                              Navigator.pop(context, newSettings);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int paddingVal) {
    final currentPadding = int.tryParse(_digitPaddingCtrl.text) ?? 4;
    final isSelected = currentPadding == paddingVal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() {
          _digitPaddingCtrl.text = '$paddingVal';
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (isDark ? Colors.white10 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.getFontStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }
}
