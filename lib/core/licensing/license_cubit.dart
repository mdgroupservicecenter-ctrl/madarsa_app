import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'license_model.dart';
import 'license_service.dart';

abstract class LicenseState extends Equatable {
  const LicenseState();
  @override
  List<Object?> get props => [];
}

class LicenseInitial extends LicenseState {}

class LicenseLoading extends LicenseState {}

class LicenseLoaded extends LicenseState {
  final AppLicense license;
  final String? feedbackMessage;
  final bool isError;

  const LicenseLoaded({
    required this.license,
    this.feedbackMessage,
    this.isError = false,
  });

  @override
  List<Object?> get props => [license, feedbackMessage, isError];

  LicenseLoaded copyWith({
    AppLicense? license,
    String? feedbackMessage,
    bool? isError,
  }) {
    return LicenseLoaded(
      license: license ?? this.license,
      feedbackMessage: feedbackMessage,
      isError: isError ?? false,
    );
  }
}

class LicenseCubit extends Cubit<LicenseState> {
  Timer? _heartbeatTimer;

  LicenseCubit() : super(LicenseInitial()) {
    loadLicense();
    _startHeartbeatTimer();
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    // Periodically sync live permissions with seller server every 10 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      syncLiveWithServer();
    });
  }

  @override
  Future<void> close() {
    _heartbeatTimer?.cancel();
    return super.close();
  }

  /// Load active license on startup and trigger initial live sync
  Future<void> loadLicense() async {
    emit(LicenseLoading());
    try {
      final license = await LicenseService.getActiveLicense();
      emit(LicenseLoaded(license: license));
      // Background sync with server for live permissions update
      syncLiveWithServer();
    } catch (_) {
      emit(LicenseLoaded(license: AppLicense.defaultTrial()));
    }
  }

  /// Live sync permissions and status with the central server
  Future<void> syncLiveWithServer() async {
    if (state is! LicenseLoaded) return;
    final current = (state as LicenseLoaded).license;
    try {
      final updated = await LicenseService.syncHeartbeatWithServer(current);
      if (updated != null && !isClosed) {
        emit(LicenseLoaded(license: updated));
      }
    } catch (_) {}
  }

  /// Activate a new license key
  Future<({bool success, String message})> activateKey(String key) async {
    final result = await LicenseService.activateKey(key);
    if (result.success && result.license != null) {
      emit(LicenseLoaded(
        license: result.license!,
        feedbackMessage: result.message,
        isError: false,
      ));
      return (success: true, message: result.message);
    } else {
      if (state is LicenseLoaded) {
        final current = (state as LicenseLoaded).license;
        emit(LicenseLoaded(
          license: current,
          feedbackMessage: result.message,
          isError: true,
        ));
      }
      return (success: false, message: result.message);
    }
  }

  /// Cancel / Deactivate the active plan and revert to trial mode
  Future<({bool success, String message})> cancelPlan() async {
    final result = await LicenseService.deactivateActiveLicense();
    final trialLic = await LicenseService.getActiveLicense();
    emit(LicenseLoaded(
      license: trialLic,
      feedbackMessage: result.message,
      isError: false,
    ));
    return result;
  }

  /// Check if a specific parent module is accessible
  bool hasModuleAccess(String moduleKey) {
    if (state is LicenseLoaded) {
      return (state as LicenseLoaded).license.hasModuleAccess(moduleKey);
    }
    return true;
  }

  /// Check if a specific granular sub-feature is accessible
  bool hasFeatureAccess(String featureKey) {
    if (state is LicenseLoaded) {
      return (state as LicenseLoaded).license.hasFeatureAccess(featureKey);
    }
    return true;
  }

  /// Helper to check if a module is locked
  bool isModuleLocked(String moduleKey) {
    return !hasModuleAccess(moduleKey);
  }

  /// Helper to check if a sub-feature is locked
  bool isFeatureLocked(String featureKey) {
    return !hasFeatureAccess(featureKey);
  }
}
