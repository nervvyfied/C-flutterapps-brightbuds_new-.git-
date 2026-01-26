import 'package:flutter/material.dart';

class FloatingXP extends StatefulWidget {
  final Offset position;
  final int xp;
  final VoidCallback? onCompleted; // called when animation finishes

  const FloatingXP({
    super.key,
    required this.position,
    required this.xp,
    this.onCompleted,
  });

  @override
  State<FloatingXP> createState() => _FloatingXPState();
}

class _FloatingXPState extends State<FloatingXP>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _animationY;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _animationY = Tween<double>(
      begin: widget.position.dy,
      end: widget.position.dy - 80,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Positioned(
          left: widget.position.dx - 20,
          top: _animationY.value,
          child: Opacity(
            opacity: _opacity.value,
            child: Image.asset(
              'assets/xp.png',
              width: 40,
              height: 40,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
