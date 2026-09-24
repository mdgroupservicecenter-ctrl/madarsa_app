import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

/// Utility to detect platform type for responsive layouts
class PlatformUtils {
  static bool get isDesktop {
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static bool get isMobile {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}

/// Responsive breakpoints
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

/// Extension for easy responsive layout queries on BuildContext
extension ResponsiveExtension on BuildContext {
  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
  bool get isMobile => screenWidth < Breakpoints.tablet;
  bool get isTablet => screenWidth >= Breakpoints.tablet && screenWidth < Breakpoints.desktop;
  bool get isDesktop => screenWidth >= Breakpoints.desktop;
}
