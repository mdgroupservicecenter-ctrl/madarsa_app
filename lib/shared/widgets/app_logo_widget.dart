import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/branding/app_branding_cubit.dart';
import '../../core/theme/app_theme.dart';

/// A reusable widget that dynamically renders either the user's custom uploaded app logo
/// or the default mosque icon with the theme's gradient.
class AppLogoWidget extends StatelessWidget {
  final double size;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final double? iconSize;
  final Color? fallbackIconColor;
  final Color? fallbackBackgroundColor;
  final Gradient? fallbackGradient;
  final String? overrideLogoPath;
  final String? logoPath;

  const AppLogoWidget({
    super.key,
    this.size = 42.0,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.border,
    this.boxShadow,
    this.iconSize,
    this.fallbackIconColor,
    this.fallbackBackgroundColor,
    this.fallbackGradient,
    this.overrideLogoPath,
    this.logoPath,
  });

  @override
  Widget build(BuildContext context) {
    final branding = context.watch<AppBrandingCubit>().state;
    final effectiveLogoPath = logoPath ?? overrideLogoPath ?? branding.logoPath;
    final hasLogo = effectiveLogoPath != null &&
        effectiveLogoPath.isNotEmpty &&
        File(effectiveLogoPath).existsSync();

    final effectiveBorderRadius = borderRadius ??
        (shape == BoxShape.circle
            ? null
            : BorderRadius.circular(size * 0.22));

    if (hasLogo) {
      final imageWidget = Image.file(
        File(effectiveLogoPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(context),
      );

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: effectiveBorderRadius,
          border: border ??
              Border.all(
                color: AppTheme.accentColor.withAlpha(120),
                width: 1.5,
              ),
          boxShadow: boxShadow,
          color: Colors.white,
        ),
        clipBehavior: Clip.antiAlias,
        child: shape == BoxShape.circle
            ? ClipOval(child: imageWidget)
            : ClipRRect(
                borderRadius: effectiveBorderRadius ?? BorderRadius.zero,
                child: imageWidget,
              ),
      );
    }

    return _buildFallbackIcon(context);
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final effectiveBorderRadius = borderRadius ??
        (shape == BoxShape.circle
            ? null
            : BorderRadius.circular(size * 0.22));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: effectiveBorderRadius,
        border: border ??
            Border.all(
              color: AppTheme.accentColor.withAlpha(100),
              width: 1.5,
            ),
        color: fallbackBackgroundColor,
        gradient: fallbackGradient ??
            (fallbackBackgroundColor == null
                ? LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryLight,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null),
        boxShadow: boxShadow,
      ),
      child: Center(
        child: Icon(
          Icons.mosque_rounded,
          size: iconSize ?? (size * 0.52),
          color: fallbackIconColor ?? AppTheme.accentColor,
        ),
      ),
    );
  }
}
