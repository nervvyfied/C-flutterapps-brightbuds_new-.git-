// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../providers/cbt_provider.dart';
import '../../models/cbt_exercise_model.dart';

class GardenMeditationView extends StatefulWidget {
  final CBTExercise exercise;
  final String parentId;
  final String childId;

  const GardenMeditationView({
    super.key,
    required this.exercise,
    required this.parentId,
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
    final assigned = provider.assigned.firstWhere(
    (a) => a.exerciseId == widget.exercise.id && a.childId == widget.childId,
    orElse: () => throw Exception('Assigned CBT not found for this exercise'),
  );

  await provider.markAsCompleted(widget.parentId, widget.childId, assigned.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Well done! 🌸'),
          content: Text('You’ve completed the "${widget.exercise.title}" exercise!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // back to CBT page
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
    // keep animation and UI logic as-is
    return Scaffold(
      backgroundColor: Colors.green[100],
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/cbt/calm/garden_bg.png', fit: BoxFit.cover),
          // ☀️ Sun animation
          Align(
            alignment: const Alignment(0.8, 0),
            child: AnimatedBuilder(
              animation: _sunGlowController,
              builder: (_, child) {
                final scale = Tween<double>(begin: 1.0, end: 1.2).animate(
                    CurvedAnimation(parent: _sunGlowController, curve: Curves.easeInOut));
                return Transform.scale(scale: scale.value, child: child);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset('assets/cbt/calm/sun_glow.png', width: 150),
                  Image.asset('assets/cbt/calm/sun.png', width: 100),
                ],
              ),
            ),
          ),
          // 🌻 Flower animation
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _flowerSwayController,
              builder: (_, child) {
                final offset = Tween<double>(begin: -15, end: 15).animate(
                    CurvedAnimation(parent: _flowerSwayController, curve: Curves.easeInOut));
                return Transform.translate(offset: Offset(offset.value, 0), child: child);
              },
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                margin: const EdgeInsets.only(bottom: 50),
                child: Image.asset('assets/cbt/calm/flower_field.png', fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

