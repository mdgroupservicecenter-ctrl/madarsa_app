import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:madarsa_app/core/theme/app_theme.dart';

/// A professional, movable (draggable by header) and resizable (draggable by corners/edges)
/// desktop-style dialog window.
class MovableResizableDialog extends StatefulWidget {
  final Widget? title;
  final Widget content;
  final Widget? actions;
  final Widget? headerLeading;
  final double initialWidth;
  final double initialHeight;
  final double minWidth;
  final double minHeight;
  final double? maxWidth;
  final double? maxHeight;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry? headerPadding;
  final BoxDecoration? headerDecoration;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final bool showMaximizeButton;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final bool isDraggable;
  final bool isResizable;
  final bool clipContent;

  const MovableResizableDialog({
    super.key,
    this.title,
    required this.content,
    this.actions,
    this.headerLeading,
    this.initialWidth = 840,
    this.initialHeight = 620,
    this.minWidth = 360,
    this.minHeight = 300,
    this.maxWidth,
    this.maxHeight,
    this.contentPadding = const EdgeInsets.all(16.0),
    this.headerPadding,
    this.headerDecoration,
    this.backgroundColor,
    this.borderRadius,
    this.showMaximizeButton = true,
    this.showCloseButton = true,
    this.onClose,
    this.isDraggable = true,
    this.isResizable = true,
    this.clipContent = true,
  });

  @override
  State<MovableResizableDialog> createState() => _MovableResizableDialogState();
}

class _MovableResizableDialogState extends State<MovableResizableDialog> {
  Offset? _offset;
  double? _width;
  double? _height;
  bool _isMaximized = false;

  // Stored dimensions before maximizing
  Offset? _preMaximizeOffset;
  double? _preMaximizeWidth;
  double? _preMaximizeHeight;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _height = widget.initialHeight;
  }

  void _toggleMaximize(Size screenSize) {
    setState(() {
      if (_isMaximized) {
        // Restore
        _isMaximized = false;
        _offset = _preMaximizeOffset;
        _width = _preMaximizeWidth ?? widget.initialWidth;
        _height = _preMaximizeHeight ?? widget.initialHeight;
      } else {
        // Maximize
        _preMaximizeOffset = _offset;
        _preMaximizeWidth = _width;
        _preMaximizeHeight = _height;

        _isMaximized = true;
        _offset = const Offset(12, 12);
        _width = screenSize.width - 24;
        _height = screenSize.height - 24;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 700;

    final effectiveMinWidth = math.min(widget.minWidth, screenSize.width * 0.95);
    final effectiveMinHeight = math.min(widget.minHeight, screenSize.height * 0.85);
    final effectiveMaxWidth = widget.maxWidth ?? (screenSize.width - 20);
    final effectiveMaxHeight = widget.maxHeight ?? (screenSize.height - 20);

    // Responsive fallback on small phone screens
    if (isMobile) {
      _width = screenSize.width * 0.96;
      _height = math.min(_height ?? widget.initialHeight, screenSize.height * 0.92);
      _offset = Offset.zero;
    } else {
      _width = (_width ?? widget.initialWidth).clamp(effectiveMinWidth, effectiveMaxWidth);
      _height = (_height ?? widget.initialHeight).clamp(effectiveMinHeight, effectiveMaxHeight);
    }

    final curWidth = _width!;
    final curHeight = _height!;

    // Center offset on first build if not set
    if (_offset == null) {
      final left = (screenSize.width - curWidth) / 2.0;
      final top = (screenSize.height - curHeight) / 2.0;
      _offset = Offset(math.max(0.0, left), math.max(0.0, top));
    } else if (!_isMaximized && !isMobile) {
      // Keep clamped inside viewport
      final maxLeft = math.max(0.0, screenSize.width - curWidth);
      final maxTop = math.max(0.0, screenSize.height - curHeight);
      _offset = Offset(
        _offset!.dx.clamp(0.0, maxLeft),
        _offset!.dy.clamp(0.0, maxTop),
      );
    }

    final radius = widget.borderRadius ?? BorderRadius.circular(isMobile ? 16 : 20);
    final dialogBg = widget.backgroundColor ?? (isDark ? const Color(0xFF1E1E2E) : Colors.white);

    final windowWidget = Material(
      color: Colors.transparent,
      child: Container(
        width: curWidth,
        height: curHeight,
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 120 : 50),
              blurRadius: 36,
              spreadRadius: 2,
              offset: const Offset(0, 14),
            ),
            if (!isDark)
              BoxShadow(
                color: AppTheme.primaryColor.withAlpha(15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(12),
            width: 1.0,
          ),
        ),
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: widget.clipContent ? Clip.antiAlias : Clip.none,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Draggable Title Bar / Header ─────────────────────────
                  _buildHeader(isDark, screenSize, isMobile),

                  // ── Dialog Content ───────────────────────────────────────
                  Expanded(
                    child: widget.content,
                  ),

                  // ── Dialog Actions / Footer ──────────────────────────────
                  if (widget.actions != null) widget.actions!,
                ],
              ),

              // ── Resizing Handles (Desktop & Wide Mode) ────────────────────
              if (widget.isResizable && !isMobile && !_isMaximized) ...[
                // Right border resize handle
                Positioned(
                  top: 48,
                  right: 0,
                  bottom: 16,
                  width: 10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _width = (_width! + details.delta.dx).clamp(
                            effectiveMinWidth,
                            effectiveMaxWidth,
                          );
                        });
                      },
                    ),
                  ),
                ),

                // Bottom border resize handle
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  height: 10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDown,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _height = (_height! + details.delta.dy).clamp(
                            effectiveMinHeight,
                            effectiveMaxHeight,
                          );
                        });
                      },
                    ),
                  ),
                ),

                // Bottom-Right corner diagonal resize grip
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 24,
                  height: 24,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanUpdate: (details) {
                        setState(() {
                          _width = (_width! + details.delta.dx).clamp(
                            effectiveMinWidth,
                            effectiveMaxWidth,
                          );
                          _height = (_height! + details.delta.dy).clamp(
                            effectiveMinHeight,
                            effectiveMaxHeight,
                          );
                        });
                      },
                      child: Container(
                        alignment: Alignment.bottomRight,
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 14,
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (isMobile) {
      return Center(
        child: windowWidget,
      );
    }

    return Stack(
      children: [
        Positioned(
          left: _offset!.dx,
          top: _offset!.dy,
          child: windowWidget,
        ),
      ],
    );
  }

  Widget _buildHeader(bool isDark, Size screenSize, bool isMobile) {
    final headerContent = Container(
      padding: widget.headerPadding ??
          EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 18,
            vertical: isMobile ? 10 : 12,
          ),
      decoration: widget.headerDecoration ??
          BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF043927), const Color(0xFF0D6B4E)]
                  : [const Color(0xFF0D6B4E), const Color(0xFF14A06E)],
            ),
          ),
      child: Row(
        children: [
          if (widget.headerLeading != null) ...[
            widget.headerLeading!,
            const SizedBox(width: 10),
          ],
          if (widget.title != null)
            Expanded(
              child: widget.title!,
            ),
          if (widget.title == null) const Spacer(),

          // Window Controls (Minimize / Maximize / Close)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isDraggable && !isMobile) ...[
                Tooltip(
                  message: 'Drag to move window',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.open_with_rounded,
                      size: 16,
                      color: Colors.white.withAlpha(160),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (widget.showMaximizeButton && !isMobile) ...[
                InkWell(
                  onTap: () => _toggleMaximize(screenSize),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _isMaximized
                          ? Icons.fullscreen_exit_rounded
                          : Icons.crop_square_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.showCloseButton)
                InkWell(
                  onTap: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (widget.isDraggable && !isMobile && !_isMaximized) {
      return MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) {
            setState(() {
              _offset = Offset(
                (_offset?.dx ?? 0) + details.delta.dx,
                (_offset?.dy ?? 0) + details.delta.dy,
              );
            });
          },
          child: headerContent,
        ),
      );
    }

    return headerContent;
  }
}
