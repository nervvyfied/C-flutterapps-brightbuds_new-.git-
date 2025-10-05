import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../providers/cbt_provider.dart';
import '../../models/cbt_exercise_model.dart';

class GardenMeditationView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;

  const GardenMeditationView({
    super.key,
    required this.exercise,
    required this.childId,
  });

  @override
  State<GardenMeditationView> createState() => _GardenMeditationViewState();
}

class _GardenMeditationViewState extends State<GardenMeditationView>
    with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  int _currentTrack = 1;
  bool _isPlaying = false;

  late AnimationController _sunGlowController;
  late AnimationController _flowerSwayController;

  List<String> get _tracks => [
        'audios/calm/01GardenMeditation.m4a',
        'audios/calm/02GardenMeditation.m4a',
        'audios/calm/03GardenMeditation.m4a',
      ];

  @override
  void initState() {
    super.initState();

    _sunGlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _flowerSwayController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _player.onPlayerComplete.listen((_) {
      if (_currentTrack < _tracks.length) {
        setState(() => _currentTrack++);
        _playCurrentTrack();
      } else {
        _onCompleted();
      }
    });

    _playCurrentTrack();
  }

  Future<void> _playCurrentTrack() async {
    if (_currentTrack > _tracks.length) return;
    setState(() => _isPlaying = true);
    await _player.play(AssetSource(_tracks[_currentTrack - 1]));
  }

  Future<void> _onCompleted() async {
    final provider = context.read<CBTProvider>();
    await provider.markAsCompleted('parentId', widget.childId, widget.exercise.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Well done! 🌸'),
          content: const Text(
              'You’ve completed the Garden Meditation.\nYou are calm, safe, and strong.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Return to CBT page
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
    _player.dispose();
    _sunGlowController.dispose();
    _flowerSwayController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;

  // Sun pulse
  final sunGlow = Tween<double>(begin: 0.5, end: 1.5).animate(
    CurvedAnimation(parent: _sunGlowController, curve: Curves.easeInOut),
  );

  // Flower sway in pixels
  final sway = Tween<double>(begin: -15, end: 15).animate(
    CurvedAnimation(parent: _flowerSwayController, curve: Curves.easeInOut),
  );

  return Scaffold(
    backgroundColor: Colors.green[100],
    appBar: AppBar(title: Text(widget.exercise.title)),
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/cbt/calm/garden_bg.png', fit: BoxFit.cover),

        // ☀️ Sun + glow
        Align(
          alignment: const Alignment(0.8, -0.8),
          child: AnimatedBuilder(
            animation: sunGlow,
            builder: (_, child) {
              return Transform.scale(
                scale: sunGlow.value,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset('assets/cbt/calm/sun_glow.png', width: 150),
                    Image.asset('assets/cbt/calm/sun.png', width: 100),
                  ],
                ),
              );
            },
          ),
        ),

        // 🌻 Flower field swaying left/right at bottom
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedBuilder(
            animation: sway,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(sway.value, 0),
                child: child,
              );
            },
            child: Container(
              width: screenWidth * 0.9,
              margin: const EdgeInsets.only(bottom: 16),
              child: Image.asset(
                'assets/cbt/calm/flower_field.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // 🎵 Progress overlay + Back button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Track $_currentTrack / ${_tracks.length}',
                        style: const TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


}
