import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../providers/cbt_provider.dart';
import '../../models/cbt_exercise_model.dart';

class GratitudeRainbowView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;
  final String parentId;

  const GratitudeRainbowView({
    super.key,
    required this.exercise,
    required this.childId,
    required this.parentId,
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
  if (_revealed[index]) return; // already revealed
  if (_allCompleted) return; // prevent further presses after completion

  _revealed[index] = true;

  _bandControllers[index].forward();
  _cloudControllers[index].forward();

  // Sparkle animation
  setState(() => _sparkleVisible[index] = true);
  await Future.delayed(const Duration(milliseconds: 1800));
  if (!mounted) return;
  setState(() => _sparkleVisible[index] = false);

  // Check all completed (ensure called only once)
  if (_revealed.every((r) => r) && !_allCompleted) {
    setState(() => _allCompleted = true);
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) _onCompleted();
  }
}


  Future<void> _onCompleted() async {
    final provider = context.read<CBTProvider>();
    final assigned = provider.assigned.firstWhere(
    (a) => a.exerciseId == widget.exercise.id && a.childId == widget.childId,
    orElse: () => throw Exception('Assigned CBT not found for this exercise'),
  );

  await provider.markAsCompleted(widget.parentId, widget.childId, assigned.id);

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
  const double baseBottom = 120.0;

  return Scaffold(
    backgroundColor: Colors.blue[100],
    appBar: AppBar(title: Text(widget.exercise.title)),
    body: SafeArea( // ✅ prevents overlap with status/navigation bars
      child: Stack(
        children: [
          // ☁️ Background
          Positioned.fill(
            child: Image.asset(
              'assets/cbt/sad/sky_bg.png',
              fit: BoxFit.cover,
            ),
          ),

          // 🌈 Bands + Clouds + Sparkles
          for (int i = 0; i < _bands.length; i++)
            Positioned(
              bottom: baseBottom + (_bands.length - 1 - i) * bandSpacing,
              left: -(bandWidth - screenWidth) / 2,
              child: SizedBox(
                width: bandWidth,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Band reveal
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

                    // Cloud animation
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

                    // ✨ Sparkles
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

          // 🌟 Final sparkle overlay
          if (_allCompleted)
            Center(
              child: SizedBox(
                width: 220,
                child: Lottie.asset(
                  'assets/cbt/sparkle.json',
                  repeat: false,
                ),
              ),
            ),

          // 🧘 Instruction text + buttons
          // 🩵 Bottom section
// 🧘 Instruction text + rainbow buttons
Align(
  alignment: Alignment.bottomCenter,
  child: SafeArea(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instruction text (slightly higher)
          const Padding(
            padding: EdgeInsets.only(bottom: 50.0),
            child: Text(
              'For each color, think or say aloud\none thing you are thankful for 🌈',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color.fromARGB(255, 0, 0, 0),
                fontSize: 24,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),

          // Rainbow buttons
          LayoutBuilder(
            builder: (context, constraints) {
              final buttonWidth = (constraints.maxWidth - 8 * 6) / 7;
              final rainbowColors = [
                Colors.red,
                Colors.orange,
                Colors.yellow,
                Colors.green,
                Colors.blue,
                Colors.indigo,
                Colors.purple,
              ];

              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  _bands.length,
                  (index) => SizedBox(
                    width: buttonWidth.clamp(40, 70),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rainbowColors[index],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: Colors.white),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => _revealBand(index),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  ),
),


        ],
      ),
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
