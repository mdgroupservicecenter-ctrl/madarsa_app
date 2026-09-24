import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/branding/app_branding.dart';
import '../../../../core/branding/app_branding_cubit.dart';
import '../../../../shared/widgets/app_logo_widget.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(AuthLoginRequested(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = size.width > 800;
    final branding = context.watch<AppBrandingCubit>().state;

    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.errorColor,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF0A0A15),
                      const Color(0xFF0F1A0F),
                      const Color(0xFF0A0A15),
                    ]
                  : [
                      const Color(0xFF0D3B12),
                      const Color(0xFF1B5E20),
                      const Color(0xFF2E7D32),
                    ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: isWide
                        ? _buildWideLayout(isDark, branding)
                        : _buildNarrowLayout(isDark, branding),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout(bool isDark, AppBranding branding) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 550),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            // Left - Branding
            Expanded(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppTheme.primaryColor.withAlpha(230),
                      AppTheme.primaryDark,
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppLogoWidget(
                      logoPath: branding.logoPath,
                      size: 84,
                      iconSize: 44,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      branding.appNameUrdu,
                      style: AppTheme.getFontStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      branding.appNameEnglish,
                      style: AppTheme.getFontStyle(
                        fontSize: 16,
                        color: Colors.white.withAlpha(200),
                        letterSpacing: 1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withAlpha(15),
                        border: Border.all(
                          color: Colors.white.withAlpha(25),
                        ),
                      ),
                      child: Text(
                        '🔒 Secure • 📱 Multi-Platform • 🌐 Multi-Language',
                        style: AppTheme.getFontStyle(
                          fontSize: 12,
                          color: Colors.white.withAlpha(180),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Right - Form
            Expanded(
              flex: 5,
              child: Container(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                padding: const EdgeInsets.all(40),
                child: _buildLoginForm(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(bool isDark, AppBranding branding) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: isDark
            ? const Color(0xFF1A1A2E).withAlpha(240)
            : Colors.white.withAlpha(245),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(60),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo
            AppLogoWidget(
              logoPath: branding.logoPath,
              size: 72,
              iconSize: 36,
            ),
            const SizedBox(height: 20),
            Text(
              branding.appNameUrdu,
              style: AppTheme.getFontStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppTheme.primaryDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to continue',
              style: AppTheme.getFontStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
            _buildLoginForm(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title (only for wide layout)
          if (MediaQuery.of(context).size.width > 800) ...[
            Text(
              context.tr('welcome'),
              style: AppTheme.getFontStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sign in to your account',
              style: AppTheme.getFontStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 32),
          ],
          // Username
          TextFormField(
            controller: _usernameController,
            autofocus: true,
            style: AppTheme.getFontStyle(
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
            decoration: InputDecoration(
              labelText: context.tr('username'),
              prefixIcon: Icon(
                Icons.person_outline_rounded,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('field_required');
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleLogin(),
          ),
          const SizedBox(height: 16),
          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: AppTheme.getFontStyle(
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
            decoration: InputDecoration(
              labelText: context.tr('password'),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return context.tr('field_required');
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleLogin(),
          ),
          const SizedBox(height: 24),
          // Login Button
          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final isLoading = state is AuthLoading;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 52,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: isLoading ? 0 : 2,
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.tr('login_button'),
                          style: AppTheme.getFontStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Version
          Center(
            child: Text(
              'v1.0.0',
              style: AppTheme.getFontStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
