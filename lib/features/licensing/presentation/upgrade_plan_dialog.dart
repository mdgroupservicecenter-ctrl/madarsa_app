import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/licensing/feature_catalog.dart';
import '../../../core/licensing/license_cubit.dart';
import '../../../core/licensing/license_model.dart';
import '../../../core/licensing/license_server_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/movable_resizable_dialog.dart';
import 'upi_payment_dialog.dart';

class UpgradePlanDialog extends StatefulWidget {
  final String? highlightModule;

  const UpgradePlanDialog({super.key, this.highlightModule});

  static Future<void> show(BuildContext context, {String? highlightModule, Color? barrierColor}) {
    return showDialog(
      context: context,
      barrierColor: barrierColor ?? Colors.black54,
      builder: (_) => UpgradePlanDialog(highlightModule: highlightModule),
    );
  }

  @override
  State<UpgradePlanDialog> createState() => _UpgradePlanDialogState();
}

class _UpgradePlanDialogState extends State<UpgradePlanDialog> {
  final _keyController = TextEditingController();
  bool _isActivating = false;
  String? _errorMessage;
  String? _successMessage;
  List<Map<String, dynamic>> _serverPlans = [];
  bool _isLoadingPlans = false;
  final Set<String> _expandedPlanCards = {};
  bool _showCurrentFeatures = false;

  @override
  void initState() {
    super.initState();
    _fetchLivePlans();
  }

  Future<void> _fetchLivePlans() async {
    setState(() => _isLoadingPlans = true);
    try {
      final fbPlans = await FirebaseService.getLivePlans();
      if (fbPlans.isNotEmpty) {
        if (mounted) {
          setState(() {
            _serverPlans = fbPlans;
            _isLoadingPlans = false;
          });
          return;
        }
      }
    } catch (_) {}

    try {
      final baseUrl = await LicenseServerConfig.getCentralServerUrl();
      if (!baseUrl.contains('firestore.googleapis.com')) {
        final dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
        ));
        final endpoint = (baseUrl.endsWith('/licensing') || baseUrl.endsWith('/licensing/'))
            ? '/plans'
            : '/licensing/plans';
        final res = await dio.get(endpoint);
        if (res.statusCode == 200 && res.data != null && res.data['plans'] != null) {
          if (mounted) {
            setState(() {
              _serverPlans = List<Map<String, dynamic>>.from(res.data['plans']);
            });
          }
        }
      }
    } catch (_) {
      try {
        final res = await ApiClient().get('/licensing/plans');
        if (res.statusCode == 200 && res.data != null && res.data['plans'] != null) {
          if (mounted) {
            setState(() {
              _serverPlans = List<Map<String, dynamic>>.from(res.data['plans']);
            });
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoadingPlans = false);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _activateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a valid license key';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isActivating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final res = await context.read<LicenseCubit>().activateKey(key);

    if (mounted) {
      setState(() {
        _isActivating = false;
        if (res.success) {
          _successMessage = res.message;
          _errorMessage = null;
          _keyController.clear();
        } else {
          _errorMessage = res.message;
          _successMessage = null;
        }
      });
    }
  }

  Future<void> _showServerConfigModal() async {
    final currentUrl = await LicenseServerConfig.getCentralServerUrl();
    final ctrl = TextEditingController(text: currentUrl);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: Color(0xFF0D6B4E), size: 20),
            SizedBox(width: 8),
            Text('Central Licensing Server', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If your organization connects to an online or central seller licensing server, specify the URL below:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'License Server Base URL',
                hintText: 'e.g. http://192.168.1.10:3000/api or https://my-server.com/api',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await LicenseServerConfig.setCentralServerUrl(LicenseServerConfig.defaultCentralServerUrl);
              if (ctx.mounted) Navigator.pop(ctx);
              _fetchLivePlans();
            },
            child: const Text('Reset Default'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              await LicenseServerConfig.setCentralServerUrl(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _fetchLivePlans();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _contactSeller(String channel) async {
    const phone = '+919876543210'; // Seller phone / WhatsApp
    if (channel == 'whatsapp') {
      final uri = Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent('Assalam-o-Alaikum! I want to purchase/upgrade my Madarsa App license.')}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return BlocBuilder<LicenseCubit, LicenseState>(
      builder: (context, state) {
        AppLicense license = AppLicense.defaultTrial();
        if (state is LicenseLoaded) {
          license = state.license;
        }

        final screenH = MediaQuery.of(context).size.height;
        return MovableResizableDialog(
          initialWidth: isMobile ? screenWidth * 0.95 : min(740.0, screenWidth - 24),
          initialHeight: min(660.0, screenH - 24),
          minWidth: min(420.0, screenWidth - 24),
          minHeight: min(400.0, screenH - 24),
          headerLeading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stars_rounded, color: Colors.white, size: 20),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subscription & Licensing',
                style: AppTheme.getFontStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Unlock all features according to your organization plan',
                style: AppTheme.getFontStyle(
                  fontSize: 11,
                  color: Colors.white.withAlpha(190),
                ),
              ),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active Plan Status Header Card
                  _buildCurrentStatusCard(license, isDark),
                  const SizedBox(height: 16),

                  if (widget.highlightModule != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withAlpha(isDark ? 35 : 20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE65100).withAlpha(90)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: Color(0xFFE65100), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'The "${widget.highlightModule!.toUpperCase()}" module requires an upgrade to a higher plan.',
                              style: AppTheme.getFontStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.orange.shade200 : const Color(0xFFBF360C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Plan Comparison Cards Grid
                  Text(
                    'CHOOSE YOUR PLAN',
                    style: AppTheme.getFontStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildPlanGrid(license, isDark),
                  const SizedBox(height: 20),

                  // License Key Activation Input Section
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF252538) : const Color(0xFFF4F6F8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.vpn_key_rounded, size: 18, color: Color(0xFF0D6B4E)),
                            const SizedBox(width: 8),
                            Text(
                              'Already have a License Key?',
                              style: AppTheme.getFontStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.dns_rounded, size: 18),
                              tooltip: 'License Server Connection Settings',
                              onPressed: _showServerConfigModal,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _keyController,
                                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                decoration: InputDecoration(
                                  hintText: 'Paste License Key here (e.g. MDL-PRO-...)',
                                  hintStyle: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                                  ),
                                  prefixIcon: const Icon(Icons.key, size: 16),
                                  filled: true,
                                  fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: _isActivating ? null : _activateKey,
                              icon: _isActivating
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.check_circle_outline_rounded, size: 16),
                              label: const Text('Activate'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0D6B4E),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ],
                        if (_successMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _successMessage!,
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _contactSeller('whatsapp'),
                  icon: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF25D366)),
                  label: const Text('WhatsApp Seller', style: TextStyle(color: Color(0xFF25D366))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final selectedPlan = _serverPlans.isNotEmpty ? _serverPlans.first : null;
                    if (selectedPlan != null) {
                      final pPrice = (selectedPlan['price'] as num?)?.toDouble() ?? 6000.0;
                      final pMrp = (selectedPlan['mrp'] as num?)?.toDouble();
                      final pDisc = (selectedPlan['discount'] as num?)?.toDouble() ?? 0.0;
                      final pDiscType = (selectedPlan['discount_type'] ?? 'fixed').toString();
                      double mrpVal = pMrp ?? pPrice;
                      int discPct = 0;
                      if (mrpVal > pPrice && mrpVal > 0) {
                        discPct = pDiscType == 'percent' && pDisc > 0 ? pDisc.round() : (((mrpVal - pPrice) / mrpVal) * 100).round();
                      }
                      final hasDisc = mrpVal > pPrice && discPct > 0;
                      UpiPaymentDialog.show(
                        context,
                        planName: selectedPlan['name']?.toString() ?? 'Madarsa Software Plan',
                        amount: pPrice,
                        mrp: hasDisc ? mrpVal : null,
                        discountLabel: hasDisc ? '$discPct% OFF' : null,
                      );
                    } else {
                      UpiPaymentDialog.show(
                        context,
                        planName: 'Madarsa Software Plan',
                        amount: 6000,
                      );
                    }
                  },
                  icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                  label: const Text('Pay via UPI QR'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D6B4E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancelPlan(BuildContext dialogContext) async {
    final cubit = dialogContext.read<LicenseCubit>();
    final shouldCancel = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 10),
            Text('Cancel Subscription Plan?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Are you sure you want to cancel and deactivate this license from this computer?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
            SizedBox(height: 8),
            Text(
              '• Your PC hardware binding will be released on the server.\n'
              '• The application will return to Free Trial mode.\n'
              '• You can activate a new license key anytime.',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep License'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            icon: const Icon(Icons.cancel_rounded, size: 16),
            label: const Text('Yes, Cancel Plan'),
          ),
        ],
      ),
    );

    if (shouldCancel == true && mounted) {
      setState(() => _isActivating = true);
      final res = await cubit.cancelPlan();
      if (mounted) {
        setState(() {
          _isActivating = false;
          _successMessage = res.message;
          _errorMessage = null;
        });
      }
    }
  }

  Widget _buildFeatureItem(String fId, Color color, bool isDark) {
    final name = FeatureCatalog.getFeatureName(fId);
    final desc = FeatureCatalog.getFeatureDesc(fId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle_rounded, size: 13, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTheme.getFontStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade200 : const Color(0xFF1E293B),
                  ),
                ),
                if (desc != null && desc.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStatusCard(AppLicense license, bool isDark) {
    final tier = license.tier;
    final isNotTrial = license.rawLicenseKey.isNotEmpty && license.rawLicenseKey != 'TRIAL-FREE-EVALUATION';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tier.color.withAlpha(isDark ? 40 : 25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tier.color.withAlpha(90), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tier.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(tier.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          tier.displayName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: tier.color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: license.isExpired ? Colors.red : Colors.green,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            license.isExpired ? 'EXPIRED' : 'ACTIVE',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      license.isLifetime
                          ? 'Permanent Lifetime License (Unlimited Updates & Features)'
                          : (license.isExpired
                              ? 'Expired on ${license.expiresAt?.toIso8601String().split('T').first}'
                              : '${license.daysRemaining} days remaining (Expires on ${license.expiresAt?.toIso8601String().split('T').first})'),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                      ),
                    ),
                    if (license.allowedModules.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      InkWell(
                        onTap: () => setState(() => _showCurrentFeatures = !_showCurrentFeatures),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showCurrentFeatures ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 13,
                                color: tier.color,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _showCurrentFeatures
                                    ? 'Hide My Active Features'
                                    : 'View My Active Plan Features (${license.allowedModules.length})',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: tier.color,
                                ),
                              ),
                              Icon(
                                _showCurrentFeatures ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 14,
                                color: tier.color,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isNotTrial) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _isActivating ? null : () => _confirmCancelPlan(context),
                  icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.red),
                  label: const Text('Cancel Plan', style: TextStyle(color: Colors.red, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ],
          ),
          if (_showCurrentFeatures && license.allowedModules.isNotEmpty) ...[
            const Divider(height: 18),
            Text(
              'Included in your current license:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: license.allowedModules.map((m) => _buildFeatureItem(m, tier.color, isDark)).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanGrid(AppLicense currentLicense, bool isDark) {
    if (_isLoadingPlans && _serverPlans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_serverPlans.isNotEmpty) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _serverPlans.map((plan) {
          final code = (plan['plan_code'] ?? '').toString().toLowerCase();
          final isLifetime = plan['is_lifetime'] == 1 || code == 'lifetime';
          final name = plan['name']?.toString() ?? 'Plan';
          final desc = plan['description']?.toString() ?? '';
          final finalPrice = (plan['price'] as num?)?.toDouble() ?? 0.0;
          final maxDevices = plan['max_devices'] ?? 1;
          final features = List<String>.from(plan['features'] ?? []);

          final rawMrp = (plan['mrp'] as num?)?.toDouble();
          final rawDiscount = (plan['discount'] as num?)?.toDouble() ?? 0.0;
          final discountType = (plan['discount_type'] ?? 'fixed').toString();

          double mrp = rawMrp ?? finalPrice;
          if (mrp < finalPrice) mrp = finalPrice;

          int discountPercent = 0;
          if (mrp > finalPrice && mrp > 0) {
            if (discountType == 'percent' && rawDiscount > 0) {
              discountPercent = rawDiscount.round();
            } else {
              discountPercent = (((mrp - finalPrice) / mrp) * 100).round();
            }
          } else if (rawDiscount > 0) {
            if (discountType == 'percent') {
              discountPercent = rawDiscount.round();
              mrp = finalPrice / (1.0 - (discountPercent / 100.0));
            } else {
              mrp = finalPrice + rawDiscount;
              if (mrp > 0) {
                discountPercent = (((mrp - finalPrice) / mrp) * 100).round();
              }
            }
          }

          final bool hasDiscount = mrp > finalPrice && discountPercent > 0;

          Color color = const Color(0xFF6A1B9A);
          if (code == 'basic') color = const Color(0xFF2E7D32);
          if (code == 'medium') color = const Color(0xFFE65100);
          if (code == 'lifetime' || isLifetime) color = const Color(0xFF0D6B4E);

          final isCurrent = currentLicense.tier.id.toLowerCase() == code && !currentLicense.isExpired;

          final isExpanded = _expandedPlanCards.contains(code);
          final hasManyFeatures = features.length > 5;
          final visibleFeatures = isExpanded ? features : (hasManyFeatures ? features.take(5).toList() : features);
          final hiddenCount = features.length - 5;

          return Container(
            width: 320,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222234) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? color : (isDark ? Colors.white12 : Colors.grey.shade300),
                width: isCurrent ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(isLifetime ? Icons.stars_rounded : Icons.verified_rounded, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(desc, style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                ],
                const SizedBox(height: 8),

                // ── Original Price (MRP) & Discount % ──
                if (hasDiscount) ...[
                  Row(
                    children: [
                      Text(
                        '₹${mrp.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          decoration: TextDecoration.lineThrough,
                          color: isDark ? Colors.red.shade300 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16A34A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$discountPercent% OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],

                // ── Final Price & Allowed Devices ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isLifetime ? '₹${finalPrice.toStringAsFixed(0)} One-Time' : '₹${finalPrice.toStringAsFixed(0)} / year',
                      style: AppTheme.getFontStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: color.withAlpha(isDark ? 40 : 25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withAlpha(90)),
                      ),
                      child: Text(
                        '$maxDevices PC${maxDevices > 1 ? "s" : ""}',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withAlpha(140)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => UpiPaymentDialog.show(
                      context,
                      planName: name,
                      amount: finalPrice,
                      mrp: hasDiscount ? mrp : null,
                      discountLabel: hasDiscount ? '$discountPercent% OFF' : null,
                    ),
                    icon: const Icon(Icons.qr_code_rounded, size: 15),
                    label: const Text('Pay via UPI QR', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${features.length} Features Included:',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    if (hasManyFeatures)
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (isExpanded) {
                              _expandedPlanCards.remove(code);
                            } else {
                              _expandedPlanCards.add(code);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isExpanded ? 'Less' : 'More ($hiddenCount+)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                              Icon(
                                isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                size: 15,
                                color: color,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isExpanded && features.length > 8)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: visibleFeatures.map((f) => _buildFeatureItem(f, color, isDark)).toList(),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: visibleFeatures.map((f) => _buildFeatureItem(f, color, isDark)).toList(),
                  ),
                if (hasManyFeatures) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedPlanCards.remove(code);
                        } else {
                          _expandedPlanCards.add(code);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withAlpha(isDark ? 25 : 15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withAlpha(50)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isExpanded
                                ? 'Show Less ▲'
                                : 'Show all $hiddenCount more features (More ▼)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      );
    }

    // Static Fallback Grid
    final plans = [
      (
        tier: SubscriptionTier.basic,
        title: 'Basic Plan',
        price: '₹6,000 / year',
        amount: 6000.0,
        modules: ['Students, Staff & Hazri', 'Dashboard Summary', 'Basic System Settings'],
        color: const Color(0xFF2E7D32),
      ),
      (
        tier: SubscriptionTier.medium,
        title: 'Medium Plan',
        price: '₹12,000 / year',
        amount: 12000.0,
        modules: ['All Basic Features', 'Classes & Departments', 'Fees Management & Receipts', 'Exams & Marks Cards', 'ID Card Printing'],
        color: const Color(0xFFE65100),
      ),
      (
        tier: SubscriptionTier.pro,
        title: 'Pro Plan',
        price: '₹20,000 / year',
        amount: 20000.0,
        modules: ['All Medium Features', 'Hostel & Kitchen Management', 'Purchases & Inventory', 'Library & Books Tracking', 'Donors & Contributions', 'Full Advanced Reports', 'Multi-User Roles & Security'],
        color: const Color(0xFF6A1B9A),
      ),
      (
        tier: SubscriptionTier.lifetime,
        title: 'Lifetime License ⭐',
        price: '₹45,000 One-Time',
        amount: 45000.0,
        modules: ['All 15 ERP Modules', 'Permanent Lifetime Access', 'No Yearly Renewal', 'VIP Direct Support'],
        color: const Color(0xFF0D6B4E),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: plans.map((p) {
        final isCurrent = currentLicense.tier == p.tier && !currentLicense.isExpired;
        final isExpanded = _expandedPlanCards.contains(p.tier.id);
        final hasManyModules = p.modules.length > 4;
        final visibleModules = isExpanded ? p.modules : (hasManyModules ? p.modules.take(4).toList() : p.modules);
        final hiddenCount = p.modules.length - 4;

        return Container(
          width: 320,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF222234) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrent ? p.color : (isDark ? Colors.white12 : Colors.grey.shade300),
              width: isCurrent ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(p.tier.icon, color: p.color, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    p.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: p.color,
                    ),
                  ),
                  const Spacer(),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.color,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('CURRENT', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.price,
                style: AppTheme.getFontStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: p.color,
                    side: BorderSide(color: p.color.withAlpha(140)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => UpiPaymentDialog.show(
                    context,
                    planName: p.title,
                    amount: p.amount,
                  ),
                  icon: const Icon(Icons.qr_code_rounded, size: 14),
                  label: const Text('Pay via UPI QR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${p.modules.length} Modules Included:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (hasManyModules)
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedPlanCards.remove(p.tier.id);
                          } else {
                            _expandedPlanCards.add(p.tier.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? 'Less' : 'More ($hiddenCount+)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: p.color,
                              ),
                            ),
                            Icon(
                              isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              size: 15,
                              color: p.color,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...visibleModules.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_rounded, size: 13, color: p.color),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            m,
                            style: AppTheme.getFontStyle(fontSize: 11.5, color: isDark ? Colors.grey.shade300 : Colors.grey.shade800),
                          ),
                        ),
                      ],
                    ),
                  )),
              if (hasManyModules) ...[
                const SizedBox(height: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedPlanCards.remove(p.tier.id);
                      } else {
                        _expandedPlanCards.add(p.tier.id);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.color.withAlpha(isDark ? 25 : 15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: p.color.withAlpha(50)),
                    ),
                    child: Text(
                      isExpanded
                          ? 'Show Less ▲'
                          : 'Show all $hiddenCount more modules (More ▼)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: p.color,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
