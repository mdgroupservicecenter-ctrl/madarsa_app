import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/licensing/device_hwid_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/movable_resizable_dialog.dart';

class UpiPaymentDialog extends StatefulWidget {
  final String planName;
  final double amount;
  final double? mrp;
  final String? discountLabel;

  const UpiPaymentDialog({
    super.key,
    required this.planName,
    required this.amount,
    this.mrp,
    this.discountLabel,
  });

  static void show(
    BuildContext context, {
    required String planName,
    required double amount,
    double? mrp,
    String? discountLabel,
  }) {
    showDialog(
      context: context,
      builder: (_) => UpiPaymentDialog(
        planName: planName,
        amount: amount,
        mrp: mrp,
        discountLabel: discountLabel,
      ),
    );
  }

  @override
  State<UpiPaymentDialog> createState() => _UpiPaymentDialogState();
}

class _UpiPaymentDialogState extends State<UpiPaymentDialog> {
  bool _isLoading = true;
  String _upiId = '';
  String _merchantName = 'Madarsa Software';
  String _whatsappNumber = '';
  String _paymentNote = '';
  String _hwid = '...';
  bool _copiedUpi = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final hwid = await DeviceHwidService.getDeviceHwid();
    final config = await FirebaseService.getPaymentConfig();

    if (mounted) {
      setState(() {
        _hwid = hwid;
        if (config != null) {
          _upiId = config['upi_id']?.toString() ?? '';
          _merchantName = config['merchant_name']?.toString() ?? 'Madarsa Software';
          _whatsappNumber = config['whatsapp_number']?.toString() ?? '';
          _paymentNote = config['note']?.toString() ?? '';
        }
        _isLoading = false;
      });
    }
  }

  String get _upiUrl {
    final cleanUpi = _upiId.trim();
    final cleanPn = Uri.encodeComponent(_merchantName.trim());
    final amt = widget.amount.toStringAsFixed(2);
    final note = Uri.encodeComponent('${widget.planName} License - $_hwid');
    return 'upi://pay?pa=$cleanUpi&pn=$cleanPn&am=$amt&cu=INR&tn=$note';
  }

  void _copyUpi() {
    if (_upiId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _upiId));
    setState(() => _copiedUpi = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copiedUpi = false);
    });
  }

  Future<void> _launchUpiApp() async {
    final uri = Uri.parse(_upiUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No UPI app found. Please scan the QR code using any UPI app (GPay/PhonePe/Paytm).'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please scan the QR code using GPay, PhonePe, or Paytm.'),
          ),
        );
      }
    }
  }

  Future<void> _sendWhatsAppConfirmation() async {
    final phone = _whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
      'Assalam-o-Alaikum!\n'
      'I have sent the payment for Madarsa Management Software.\n\n'
      '• Plan: ${widget.planName}\n'
      '• Amount: ₹${widget.amount.toStringAsFixed(0)}\n'
      '• Machine HWID: $_hwid\n\n'
      'Please verify and activate my license key.',
    );
    final url = phone.isNotEmpty
        ? 'https://wa.me/$phone?text=$msg'
        : 'https://wa.me/?text=$msg';

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isCompact = screenW < 600;

    return MovableResizableDialog(
      initialWidth: isCompact ? screenW * 0.95 : 560,
      initialHeight: (screenH * 0.88).clamp(520, 720),
      minWidth: 380,
      minHeight: 460,
      headerLeading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(30),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UPI Payment & Instant Renewal',
            style: AppTheme.getFontStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            'Pay via Google Pay, PhonePe, Paytm or BHIM UPI',
            style: AppTheme.getFontStyle(
              fontSize: 11,
              color: Colors.white.withAlpha(190),
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Plan & Amount Header Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF0D6B4E),
                          const Color(0xFF0F766E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D6B4E).withAlpha(40),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.planName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (widget.discountLabel != null && widget.discountLabel!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade400,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.discountLabel!,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (widget.mrp != null && widget.mrp! > widget.amount)
                              Text(
                                'MRP ₹${widget.mrp!.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            Text(
                              '₹${widget.amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Dynamic QR Code Card ──
                  if (_upiId.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 50 : 15),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: QrImageView(
                              data: _upiUrl,
                              version: QrVersions.auto,
                              size: 190.0,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: Color(0xFF0D6B4E),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _merchantName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Scan with GPay, PhonePe, Paytm, or any UPI App',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withAlpha(80)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Seller UPI ID is not configured yet. Please contact software seller directly on WhatsApp.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),

                  // ── UPI ID Copy Row ──
                  if (_upiId.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131A2A) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_rounded, size: 16, color: Color(0xFF0D6B4E)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('UPI ID:', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                Text(
                                  _upiId,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: _copyUpi,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: _copiedUpi ? Colors.green.withAlpha(30) : const Color(0xFF0D6B4E).withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _copiedUpi ? Colors.green : const Color(0xFF0D6B4E),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _copiedUpi ? Icons.check : Icons.copy,
                                    size: 13,
                                    color: _copiedUpi ? Colors.green : const Color(0xFF0D6B4E),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _copiedUpi ? 'Copied' : 'Copy',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _copiedUpi ? Colors.green : const Color(0xFF0D6B4E),
                                    ),
                                  ),
                                 ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_paymentNote.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _paymentNote,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 18),

                  // ── Buttons ──
                  Row(
                    children: [
                      if (_upiId.isNotEmpty) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0D6B4E),
                              side: const BorderSide(color: Color(0xFF0D6B4E)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _launchUpiApp,
                            icon: const Icon(Icons.open_in_new_rounded, size: 16),
                            label: const Text('Open UPI App', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _sendWhatsAppConfirmation,
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text('Send on WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      actions: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
