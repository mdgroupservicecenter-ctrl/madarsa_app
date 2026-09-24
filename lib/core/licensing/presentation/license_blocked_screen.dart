import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../device_hwid_service.dart';
import '../license_cubit.dart';
import '../license_model.dart';
import '../../services/firebase_service.dart';

class LicenseBlockedScreen extends StatefulWidget {
  final AppLicense license;

  const LicenseBlockedScreen({super.key, required this.license});

  @override
  State<LicenseBlockedScreen> createState() => _LicenseBlockedScreenState();
}

class _LicenseBlockedScreenState extends State<LicenseBlockedScreen> {
  String _hwid = 'Loading...';
  bool _isRechecking = false;
  bool _copiedUpi = false;

  // Activation
  final _keyController = TextEditingController();
  bool _isActivating = false;
  String? _activationError;
  String? _activationSuccess;

  // Payment Config
  bool _showPaymentSection = false;
  String _upiId = '';
  String _merchantName = 'Madarsa Software';
  String _whatsappNumber = '';
  String _paymentNote = '';

  @override
  void initState() {
    super.initState();
    _loadHwid();
    _loadPaymentConfig();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadHwid() async {
    final h = await DeviceHwidService.getDeviceHwid();
    if (mounted) {
      setState(() => _hwid = h);
    }
  }

  Future<void> _loadPaymentConfig() async {
    final config = await FirebaseService.getPaymentConfig();
    if (mounted) {
      setState(() {
        if (config != null) {
          _upiId = config['upi_id']?.toString() ?? '';
          _merchantName = config['merchant_name']?.toString() ?? 'Madarsa Software';
          _whatsappNumber = config['whatsapp_number']?.toString() ?? '';
          _paymentNote = config['note']?.toString() ?? '';
        }
      });
    }
  }

  Future<void> _handleRecheck() async {
    setState(() => _isRechecking = true);
    await context.read<LicenseCubit>().syncLiveWithServer();
    if (mounted) {
      setState(() => _isRechecking = false);
    }
  }

  void _copyUpi() {
    if (_upiId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _upiId));
    setState(() => _copiedUpi = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copiedUpi = false);
    });
  }

  Future<void> _handleActivateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _activationError = 'Please enter a license key');
      return;
    }

    setState(() {
      _isActivating = true;
      _activationError = null;
      _activationSuccess = null;
    });

    final res = await context.read<LicenseCubit>().activateKey(key);
    if (mounted) {
      setState(() {
        _isActivating = false;
        if (res.success) {
          _activationSuccess = res.message;
        } else {
          _activationError = res.message;
        }
      });
    }
  }

  String get _upiUrl {
    final cleanUpi = _upiId.trim();
    final cleanPn = Uri.encodeComponent(_merchantName.trim());
    final note = Uri.encodeComponent('Madarsa Software Renewal - $_hwid');
    return 'upi://pay?pa=$cleanUpi&pn=$cleanPn&cu=INR&tn=$note';
  }

  Future<void> _sendWhatsApp() async {
    final phone = _whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final msg = Uri.encodeComponent(
      'Assalam-o-Alaikum!\n'
      'I need to renew/unblock my Madarsa Management Software license.\n\n'
      '• Machine HWID: $_hwid\n'
      '• Status: ${widget.license.isBlocked ? "Blocked/Deleted" : "Expired"}\n\n'
      'Please send me the plan details or activation key.',
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
    final isBlocked = widget.license.isBlocked;
    final primaryColor = isBlocked ? Colors.red : Colors.orange;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            width: 580,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: primaryColor.withAlpha(140), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withAlpha(40),
                  blurRadius: 35,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header Icon ──
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: primaryColor.withAlpha(25),
                    shape: BoxShape.circle,
                    border: Border.all(color: primaryColor.withAlpha(100), width: 1.5),
                  ),
                  child: Icon(
                    isBlocked ? Icons.gpp_bad_rounded : Icons.lock_clock_rounded,
                    color: primaryColor,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Title ──
                Text(
                  isBlocked
                      ? 'ACCESS RESTRICTED / رسائی بند ہے'
                      : 'PLAN EXPIRED / پلان کی مدت ختم ہو چکی ہے',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isBlocked
                      ? (widget.license.blockedMessage ??
                          'This computer or license has been rejected/blocked by administrator.')
                      : 'Your subscription plan has expired. Please renew your plan to continue using all modules.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
                const SizedBox(height: 20),

                // ── Activate License Key Section ──
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131D31),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0F766E).withAlpha(90)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.vpn_key_rounded, size: 16, color: Color(0xFF14B8A6)),
                          SizedBox(width: 8),
                          Text(
                            'Activate New License Key',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _keyController,
                              style: const TextStyle(fontSize: 12.5, color: Colors.white, fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                hintText: 'Paste License Key (e.g. MDL-PRO-...)',
                                hintStyle: const TextStyle(fontSize: 11.5, color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF0A0F1D),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: Colors.white12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: _isActivating ? null : _handleActivateKey,
                            icon: _isActivating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle_rounded, size: 16),
                            label: const Text('Activate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      if (_activationError != null) ...[
                        const SizedBox(height: 6),
                        Text(_activationError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                      ],
                      if (_activationSuccess != null) ...[
                        const SizedBox(height: 6),
                        Text(_activationSuccess!, style: const TextStyle(color: Colors.greenAccent, fontSize: 11.5, fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // ── UPI Payment Toggle & Section ──
                if (_showPaymentSection) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131D31),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        if (_upiId.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: QrImageView(
                              data: _upiUrl,
                              version: QrVersions.auto,
                              size: 160.0,
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
                          const SizedBox(height: 8),
                          Text(
                            _merchantName,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0F1D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.account_balance_rounded, size: 14, color: Color(0xFF14B8A6)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(_upiId, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                                ),
                                InkWell(
                                  onTap: _copyUpi,
                                  child: Text(
                                    _copiedUpi ? 'Copied!' : 'Copy UPI',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _copiedUpi ? Colors.green : const Color(0xFF14B8A6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_paymentNote.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _paymentNote,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                          ],
                        ] else
                          const Text(
                            'Seller UPI ID is not configured yet. Please contact seller directly on WhatsApp.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Action Buttons ──
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isRechecking ? null : _handleRecheck,
                        icon: _isRechecking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: Text(_isRechecking ? 'Checking...' : 'Re-check Status'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF38BDF8),
                          side: const BorderSide(color: Color(0xFF0284C7)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => setState(() => _showPaymentSection = !_showPaymentSection),
                        icon: Icon(_showPaymentSection ? Icons.qr_code_rounded : Icons.payment_rounded, size: 16),
                        label: Text(_showPaymentSection ? 'Hide QR' : 'Pay via UPI'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _sendWhatsApp,
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
