import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_cubit.dart';
import 'core/licensing/license_cubit.dart';
import 'core/licensing/presentation/license_blocked_screen.dart';
import 'core/branding/app_branding.dart';
import 'core/branding/app_branding_cubit.dart';
import 'shared/widgets/app_logo_widget.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_state.dart';
import 'dart:io';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/shell/presentation/app_shell.dart';
import 'core/services/windows_system_branding_service.dart';

class MadarsaApp extends StatefulWidget {
  const MadarsaApp({super.key});

  @override
  State<MadarsaApp> createState() => _MadarsaAppState();
}

class _MadarsaAppState extends State<MadarsaApp> {
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            final branding = context.read<AppBrandingCubit>().state;
            WindowsSystemBrandingService.applySystemBranding(branding);
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<LocaleCubit, LocaleState>(
          builder: (context, localeState) {
            return BlocBuilder<AppBrandingCubit, AppBranding>(
              builder: (context, branding) {
                if (Platform.isWindows) {
                  WindowsSystemBrandingService.updateWindowTitle(branding.appNameEnglish);
                }
                return MaterialApp(
                  title: branding.appNameEnglish,
                  debugShowCheckedModeBanner: false,
                  
                  // Theme
                  theme: AppTheme.lightTheme(localeState.locale.languageCode == 'ur' ? 'JameelNooriNastaleeq' : null),
                  darkTheme: AppTheme.darkTheme(localeState.locale.languageCode == 'ur' ? 'JameelNooriNastaleeq' : null),
                  themeMode: themeState.themeMode,
              
              // Localization
              locale: localeState.locale,
              supportedLocales: const [
                Locale('en'),
                Locale('ur'),
                Locale('hi'),
                Locale('gu'),
              ],
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              
              builder: (context, child) {
                return Stack(
                  children: [
                    ?child,
                    BlocBuilder<LicenseCubit, LicenseState>(
                      builder: (context, licState) {
                        final isLocked = licState is LicenseLoaded &&
                            (licState.license.isBlocked || licState.license.isExpired);
                        if (!isLocked) return const SizedBox.shrink();
                        return Positioned.fill(
                          child: Material(
                            type: MaterialType.transparency,
                            child: LicenseBlockedScreen(license: licState.license),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },

              // Auth-based routing
              home: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, authState) {
                  if (authState is AuthLoading || authState is AuthInitial) {
                    return const _SplashScreen();
                  }
                  if (authState is AuthAuthenticated) {
                    return const AppShell();
                  }
                  return const LoginScreen();
                },
              ),
            );
          },
        );
      },
    );
  },
);
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final branding = context.watch<AppBrandingCubit>().state;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0A0A15), const Color(0xFF0F1A0F)]
                : [AppTheme.primaryColor, AppTheme.primaryDark],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogoWidget(
                logoPath: branding.logoPath,
                size: 90,
                iconSize: 48,
              ),
              const SizedBox(height: 24),
              Text(
                branding.appNameEnglish,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withAlpha(180),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
