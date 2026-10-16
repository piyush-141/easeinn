import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium, fluid micro-animation widget that provides an ultra-responsive
/// tactile scale & depth compression effect upon clicking or holding.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final double pressedOpacity;
  final Duration pressDuration;
  final Duration releaseDuration;
  final Curve pressCurve;
  final Curve releaseCurve;
  final bool enableHaptic;
  final HitTestBehavior behavior;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.95,
    this.pressedOpacity = 0.94,
    this.pressDuration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 140),
    this.pressCurve = Curves.easeOutCubic,
    this.releaseCurve = Curves.easeOutBack,
    this.enableHaptic = true,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _isDown = false;
  DateTime? _downTime;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.releaseDuration,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.pressCurve,
      reverseCurve: widget.releaseCurve,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedOpacity,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.pressCurve,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _isDown = true;
    _downTime = DateTime.now();
    if (widget.enableHaptic) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }
    _controller.animateTo(
      1.0,
      duration: widget.pressDuration,
      curve: widget.pressCurve,
    );
  }

  void _handleTapUp(TapUpDetails details) async {
    if (!_isDown) return;
    _isDown = false;

    // Ensure the compression is clearly visible even on rapid taps
    if (_downTime != null) {
      final elapsed = DateTime.now().difference(_downTime!);
      if (elapsed < widget.pressDuration) {
        await Future.delayed(widget.pressDuration - elapsed);
      }
    }

    if (!mounted) return;
    _controller.animateTo(
      0.0,
      duration: widget.releaseDuration,
      curve: widget.releaseCurve,
    );
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _handleTapCancel() {
    if (!_isDown) return;
    _isDown = false;
    _controller.animateTo(
      0.0,
      duration: widget.releaseDuration,
      curve: widget.releaseCurve,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _isDown = true;
    _downTime = DateTime.now();
    if (widget.enableHaptic) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }
    _controller.animateTo(
      1.0,
      duration: widget.pressDuration,
      curve: widget.pressCurve,
    );
  }

  void _handlePointerUp(PointerUpEvent event) async {
    if (!_isDown) return;
    _isDown = false;
    if (_downTime != null) {
      final elapsed = DateTime.now().difference(_downTime!);
      if (elapsed < widget.pressDuration) {
        await Future.delayed(widget.pressDuration - elapsed);
      }
    }
    if (!mounted) return;
    _controller.animateTo(
      0.0,
      duration: widget.releaseDuration,
      curve: widget.releaseCurve,
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (!_isDown) return;
    _isDown = false;
    _controller.animateTo(
      0.0,
      duration: widget.releaseDuration,
      curve: widget.releaseCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasExplicitCallback = widget.onTap != null || widget.onLongPress != null;

    Widget core = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          alignment: Alignment.center,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );

    if (hasExplicitCallback) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: widget.behavior,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onLongPress: widget.onLongPress != null
              ? () {
                  if (widget.enableHaptic) {
                    try {
                      HapticFeedback.mediumImpact();
                    } catch (_) {}
                  }
                  widget.onLongPress!();
                }
              : null,
          child: core,
        ),
      );
    }

    // When used as a pure wrapper around an inner button/InkWell:
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: core,
    );
  }
}
