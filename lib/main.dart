import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app.dart';
import 'core/theme/theme_cubit.dart';
import 'core/localization/locale_cubit.dart';
import 'core/utils/hijri_cubit.dart';
import 'core/licensing/license_cubit.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/bloc/auth_event.dart';

import 'core/branding/app_branding_cubit.dart';
import 'core/services/storage_mode_service.dart';
import 'core/services/firebase_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/clock_theme_service.dart';
import 'core/services/salat_time_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppUpdateService.initVersion();
  await StorageModeService.init();
  await ClockThemeService.init();
  await SalatTimeService.init();
  await FirebaseService.initCredentials();
  if (StorageModeService.isOnlineSyncEnabled) {
    FirebaseService.startLiveCloudSync();
  }
  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<LocaleCubit>(create: (_) => LocaleCubit()),
        BlocProvider<LicenseCubit>(create: (_) => LicenseCubit()),
        BlocProvider<AppBrandingCubit>(
          create: (_) => AppBrandingCubit()..loadBranding(),
        ),
        BlocProvider<AuthBloc>(
          create: (_) => AuthBloc()..add(AuthCheckRequested()),
        ),
        BlocProvider<HijriCubit>(
          create: (_) => HijriCubit()..loadAdjustment(),
        ),
      ],
      child: const MadarsaApp(),
    ),
  );
}
