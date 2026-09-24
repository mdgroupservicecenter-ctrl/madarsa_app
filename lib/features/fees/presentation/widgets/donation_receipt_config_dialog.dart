import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/donation_receipt_settings.dart';

class DonationReceiptConfigDialog extends StatefulWidget {
  final String? title;
  final List<String>? initialFeeReceiptNos;
  final List<String>? initialDonationReceiptNos;
  const DonationReceiptConfigDialog({
    super.key,
    this.title,
    this.initialFeeReceiptNos,
    this.initialDonationReceiptNos,
  });

  static Future<DonationReceiptSettingsModel?> show(
    BuildContext context, {
    Color? barrierColor,
    String? title,
    List<String>? initialFeeReceiptNos,
    List<String>? initialDonationReceiptNos,
  }) {
    return showDialog<DonationReceiptSettingsModel>(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (ctx) => DonationReceiptConfigDialog(
        title: title,
        initialFeeReceiptNos: initialFeeReceiptNos,
        initialDonationReceiptNos: initialDonationReceiptNos,
      ),
    );
  }

  @override
  State<DonationReceiptConfigDialog> createState() => _DonationReceiptConfigDialogState();
}

class _DonationReceiptConfigDialogState extends State<DonationReceiptConfigDialog> {
  bool _isLoading = true;
  late TextEditingController _prefixCtrl;

  late bool _enableAlphabet;
  late TextEditingController _startAlphabetCtrl;
  late TextEditingController _endAlphabetCtrl;
  late TextEditingController _alphabetPrefixCtrl;

  late bool _enableYear;
  late String _yearFormat;
  late TextEditingController _customYearCtrl;

  late TextEditingController _digitPaddingCtrl;
  late TextEditingController _startingNumberCtrl;

  late bool _syncReceiptNumbers;
  List<String> _feeExistingReceiptNos = [];
  List<String> _donationExistingReceiptNos = [];

  @override
  void initState() {
    super.initState();
    _prefixCtrl = TextEditingController(text: 'DN-');
    _startAlphabetCtrl = TextEditingController(text: 'A');
    _endAlphabetCtrl = TextEditingController(text: 'Z');
    _alphabetPrefixCtrl = TextEditingController(text: 'A');

    final current2DigitYear = DateFormat('yy').format(DateTime.now());
    _customYearCtrl = TextEditingController(text: current2DigitYear);

    _digitPaddingCtrl = TextEditingController(text: '5');
    _startingNumberCtrl = TextEditingController(text: '1');
    _syncReceiptNumbers = true;
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final s = await DonationReceiptSettings.loadSettings();
    final now = DateTime.now();
    final defaultYear = s.yearFormat == '4digit' ? DateFormat('yyyy').format(now) : DateFormat('yy').format(now);

    List<String> feeNos = widget.initialFeeReceiptNos ?? [];
    List<String> donationNos = widget.initialDonationReceiptNos ?? [];
    if (widget.initialFeeReceiptNos == null || widget.initialDonationReceiptNos == null) {
      try {
        if (widget.initialFeeReceiptNos == null) {
          feeNos = await DonationReceiptSettings.getAllExistingReceiptNos(receiptType: 'fee');
        }
        if (widget.initialDonationReceiptNos == null) {
          donationNos = await DonationReceiptSettings.getAllExistingReceiptNos(receiptType: 'donation');
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _prefixCtrl.text = s.customPrefix;
        _enableAlphabet = s.enableAlphabet;
        _startAlphabetCtrl.text = s.startAlphabet;
        _endAlphabetCtrl.text = s.endAlphabet;
        _alphabetPrefixCtrl.text = s.alphabetPrefix;

        _enableYear = s.enableYear;
        _yearFormat = s.yearFormat;
        _customYearCtrl.text = s.customYearValue.isNotEmpty ? s.customYearValue : defaultYear;

        _digitPaddingCtrl.text = '${s.digitPadding}';
        _startingNumberCtrl.text = '${s.startingNumber}';
        _syncReceiptNumbers = s.syncReceiptNumbers;
        _feeExistingReceiptNos = feeNos;
        _donationExistingReceiptNos = donationNos;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _startAlphabetCtrl.dispose();
    _endAlphabetCtrl.dispose();
    _alphabetPrefixCtrl.dispose();
    _customYearCtrl.dispose();
    _digitPaddingCtrl.dispose();
    _startingNumberCtrl.dispose();
    super.dispose();
  }

  DonationReceiptSettingsModel _currentModel() {
    final starting = int.tryParse(_startingNumberCtrl.text) ?? 1;
    final padding = int.tryParse(_digitPaddingCtrl.text) ?? 5;
    return DonationReceiptSettingsModel(
      customPrefix: _prefixCtrl.text.trim(),
      enableAlphabet: _enableAlphabet,
      startAlphabet: _startAlphabetCtrl.text.trim().isEmpty ? 'A' : _startAlphabetCtrl.text.trim(),
      endAlphabet: _endAlphabetCtrl.text.trim().isEmpty ? 'Z' : _endAlphabetCtrl.text.trim(),
      alphabetPrefix: _alphabetPrefixCtrl.text.trim().isEmpty ? 'A' : _alphabetPrefixCtrl.text.trim(),
      enableYear: _enableYear,
      yearFormat: _yearFormat,
      customYearValue: _customYearCtrl.text.trim(),
      digitPadding: padding >= 0 ? padding : 0,
      startingNumber: starting > 0 ? starting : 1,
      syncReceiptNumbers: _syncReceiptNumbers,
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
    final unifiedNextNo = DonationReceiptGenerator.generateNextReceiptNo(
      existingReceiptNos: [..._feeExistingReceiptNos, ..._donationExistingReceiptNos],
      settings: model,
    );
    final feeNextNo = DonationReceiptGenerator.generateNextReceiptNo(
      existingReceiptNos: _feeExistingReceiptNos,
      settings: model,
    );
    final donationNextNo = DonationReceiptGenerator.generateNextReceiptNo(
      existingReceiptNos: _donationExistingReceiptNos,
      settings: model,
    );

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
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D6B4E), Color(0xFF138A65)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFACC15), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title ?? 'RECEIPT NUMBER CONFIG',
                            style: AppTheme.getFontStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFACC15),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Customize Prefix, Year, Sequence & Digits',
                            style: AppTheme.getFontStyle(fontSize: 11, color: Colors.white70),
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
                    // Live Preview Box
                    if (_syncReceiptNumbers)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF262638) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF3B3B52) : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'LIVE RECEIPT NUMBER PREVIEW:',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.grey.shade400 : Colors.green.shade800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'SYNCED SERIES',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withAlpha(20),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    unifiedNextNo,
                                    style: AppTheme.getFontStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: isDark ? Colors.white : AppTheme.primaryColor,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '(Fee & Donation donu ka next receipt no.)',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF262638) : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF3B3B52) : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'LIVE RECEIPT NUMBER PREVIEW:',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.grey.shade400 : Colors.amber.shade900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withAlpha(30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'INDEPENDENT SERIES',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'FEE RECEIPT',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          feeNextNo,
                                          style: AppTheme.getFontStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'DONOR RECEIPT',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          donationNextNo,
                                          style: AppTheme.getFontStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '(Fee or Donor receipts ki alag alag series chalegi)',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    // Sync Switch Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _syncReceiptNumbers
                            ? (isDark ? const Color(0xFF132F23) : const Color(0xFFE8F5E9))
                            : (isDark ? const Color(0xFF2A2A38) : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _syncReceiptNumbers
                              ? (isDark ? const Color(0xFF2E7D32) : const Color(0xFF81C784))
                              : (isDark ? const Color(0xFF474857) : const Color(0xFFCBD5E1)),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _syncReceiptNumbers
                                  ? (isDark ? const Color(0xFF2E7D32).withAlpha(60) : const Color(0xFF4CAF50).withAlpha(40))
                                  : Colors.grey.withAlpha(40),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _syncReceiptNumbers ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                              color: _syncReceiptNumbers
                                  ? (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32))
                                  : Colors.grey.shade500,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Sync Fee & Donation Numbers',
                                        style: AppTheme.getFontStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: _syncReceiptNumbers
                                            ? Colors.green.withAlpha(40)
                                            : Colors.orange.withAlpha(40),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _syncReceiptNumbers ? 'SYNCED' : 'SEPARATE',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: _syncReceiptNumbers ? Colors.green : Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _syncReceiptNumbers
                                      ? 'ON: Fee or Donation donu ek sath mil kar ek hi series me chalenge.'
                                      : 'OFF: Fee or Donation donu ki alag alag independent series chalegi.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            key: const Key('sync_receipt_numbers_switch'),
                            value: _syncReceiptNumbers,
                            activeThumbColor: AppTheme.primaryColor,
                            activeTrackColor: AppTheme.primaryColor.withAlpha(120),
                            onChanged: (val) {
                              setState(() {
                                _syncReceiptNumbers = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 1. Custom Prefix
                    Text('1. Receipt Prefix', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _prefixCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'e.g. DN- or REC- or DON-',
                        helperText: 'Common prefix placed at beginning of receipt number',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: AppTheme.getFontStyle(fontSize: 13),
                    ),

                    const SizedBox(height: 14),

                    // 2. Year in prefix
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('2. Include Year in Prefix', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              Text('Embed year (e.g. 26 or 2026)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _enableYear,
                          activeThumbColor: AppTheme.primaryColor,
                          onChanged: (val) => setState(() => _enableYear = val),
                        ),
                      ],
                    ),
                    if (_enableYear) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text('2-Digit (26)'),
                            selected: _yearFormat == '2digit',
                            onSelected: (sel) {
                              if (sel) _updateYearFormat('2digit');
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('4-Digit (2026)'),
                            selected: _yearFormat == '4digit',
                            onSelected: (sel) {
                              if (sel) _updateYearFormat('4digit');
                            },
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // 3. Alphabet Series
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('3. Alphabet Series Prefix', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              Text('Include series letter (e.g. A, B, C)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _enableAlphabet,
                          activeThumbColor: AppTheme.primaryColor,
                          onChanged: (val) => setState(() => _enableAlphabet = val),
                        ),
                      ],
                    ),
                    if (_enableAlphabet) ...[
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _alphabetPrefixCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Series Alphabet (A, B, C...)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: AppTheme.getFontStyle(fontSize: 13),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // 4. Digit Padding & Starting Number
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('4. Digit Length', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _digitPaddingCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'e.g. 5 (00001)',
                                  helperText: 'Zero-padding digits',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('5. Starting Number', style: AppTheme.getFontStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _startingNumberCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: 'e.g. 1',
                                  helperText: 'Initial sequence start',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                style: AppTheme.getFontStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Save Format'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () async {
                            final newModel = _currentModel();
                            await DonationReceiptSettings.saveSettings(newModel);
                            if (context.mounted) Navigator.pop(context, newModel);
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
}
