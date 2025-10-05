import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../providers/cbt_provider.dart';
import '../../models/cbt_exercise_model.dart';

class GratitudeRainbowView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;

  const GratitudeRainbowView({
    super.key,
    required this.exercise,
    required this.childId,
  });

  @override
  State<GratitudeRainbowView> createState() => _GratitudeRainbowViewState();
}

class _GratitudeRainbowViewState extends State<GratitudeRainbowView>
    with TickerProviderStateMixin {
  final List<String> _bands = [
    'assets/cbt/sad/red_band.png',
    'assets/cbt/sad/orange_band.png',
    'assets/cbt/sad/yellow_band.png',
    'assets/cbt/sad/green_band.png',
    'assets/cbt/sad/blue_band.png',
    'assets/cbt/sad/indigo_band.png',
    'assets/cbt/sad/violet_band.png',
  ];


  late List<AnimationController> _bandControllers;
  late List<AnimationController> _cloudControllers;
  late List<Animation<double>> _cloudOpacity;
  late List<Animation<Offset>> _cloudLeftOffset;
  late List<Animation<Offset>> _cloudRightOffset;

  late List<bool> _revealed;
  late List<bool> _sparkleVisible;

  bool _allCompleted = false;

  @override
  void initState() {
    super.initState();

    _bandControllers = List.generate(
      _bands.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      ),
    );

    _cloudControllers = List.generate(
      _bands.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      ),
    );

    _cloudOpacity = _cloudControllers.map((controller) {
      return TweenSequence([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 75),
      ]).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    _cloudLeftOffset = _cloudControllers.map((controller) {
      return Tween<Offset>(
        begin: const Offset(0, 0),
        end: const Offset(-1.5, 0),
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    _cloudRightOffset = _cloudControllers.map((controller) {
      return Tween<Offset>(
        begin: const Offset(0, 0),
        end: const Offset(1.5, 0),
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    _revealed = List.generate(_bands.length, (_) => false);
    _sparkleVisible = List.generate(_bands.length, (_) => false);
  }

  Future<void> _revealBand(int index) async {
  if (_revealed[index]) return;

  _revealed[index] = true;

  // Start both band + cloud animations at the same time
  _bandControllers[index].forward();
  _cloudControllers[index].forward();

  // Show sparkles while clouds animate
  setState(() => _sparkleVisible[index] = true);
  await Future.delayed(const Duration(milliseconds: 1800)); // longer sparkle duration
  setState(() => _sparkleVisible[index] = false);

  // Check if all completed
  if (_revealed.every((r) => r)) {
    setState(() => _allCompleted = true);
    await Future.delayed(const Duration(seconds: 1));
    _onCompleted();
  }
}


  Future<void> _onCompleted() async {
    final provider = context.read<CBTProvider>();
    await provider.markAsCompleted('parentId', widget.childId, widget.exercise.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Amazing! 🌈'),
          content: const Text(
              'You have built your Gratitude Rainbow!\nGreat job noticing the good things today.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    for (var c in _bandControllers) c.dispose();
    for (var c in _cloudControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bandSpacing = 35.0;
    final bandWidth = screenWidth * 1.25;
    final double baseBottom = 120.0;

    return Scaffold(
      backgroundColor: Colors.blue[100],
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/cbt/sad/sky_bg.png', fit: BoxFit.cover),
          ),

          // 🌈 Bands + clouds + sparkles
          for (int i = 0; i < _bands.length; i++)
            Positioned(
              // reverse the vertical position so index 0 is highest
              bottom: baseBottom + (_bands.length - 1 - i) * bandSpacing,
              left: -(bandWidth - screenWidth) / 2,
              child: SizedBox(
                width: bandWidth,
                // each band is its own Stack: band, clouds (hidden initially), sparkles
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // band reveal (center -> edges)
                    AnimatedBuilder(
                      animation: _bandControllers[i],
                      builder: (_, child) {
                        return ClipRect(
                          clipper: _CenterRevealClipper(_bandControllers[i].value),
                          child: child,
                        );
                      },
                      child: Image.asset(_bands[i], width: bandWidth, fit: BoxFit.fill),
                    ),

                  // Clouds animation (start invisible, fade in + move + fade out)
                  AnimatedBuilder(
                    animation: _cloudControllers[i],
                    builder: (_, __) {
                      return Opacity(
                        opacity: _cloudOpacity[i].value,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SlideTransition(
                              position: _cloudLeftOffset[i],
                              child: Image.asset(
                                'assets/cbt/sad/cloud.png',
                                width: bandWidth / 2,
                                fit: BoxFit.fill,
                              ),
                            ),
                            SlideTransition(
                              position: _cloudRightOffset[i],
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Image.asset(
                                  'assets/cbt/sad/cloud.png',
                                  width: bandWidth / 2,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // ✨ Sparkles (both sides)
                  if (_sparkleVisible[i]) ...[
                    Positioned(
                      left: 20,
                      child: Lottie.asset(
                        'assets/cbt/sparkle.json',
                        width: 240,
                        repeat: false,
                      ),
                    ),
                    Positioned(
                      right: 20,
                      child: Lottie.asset(
                        'assets/cbt/sparkle.json',
                        width: 240,
                        repeat: false,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 🎇 Final sparkle overlay when all completed
          if (_allCompleted)
            Center(
              child: SizedBox(
                width: 220,
                child: Lottie.asset('assets/cbt/sparkle.json', repeat: false),
              ),
            ),

          // Buttons
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  _bands.length,
                  (index) => ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Colors.white),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    onPressed: () => _revealBand(index),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterRevealClipper extends CustomClipper<Rect> {
  final double progress;

  _CenterRevealClipper(this.progress);

  @override
  Rect getClip(Size size) {
    final center = size.width / 2;
    final halfWidth = center * progress;
    return Rect.fromLTRB(center - halfWidth, 0, center + halfWidth, size.height);
  }

  @override
  bool shouldReclip(covariant _CenterRevealClipper oldClipper) =>
      oldClipper.progress != progress;
}
