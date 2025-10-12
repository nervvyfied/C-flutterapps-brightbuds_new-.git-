import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../models/cbt_exercise_model.dart';
import '../../providers/cbt_provider.dart';

class HappyStretchView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;
  final String parentId;

  const HappyStretchView({super.key, required this.exercise, required this.childId, required this.parentId});

  @override
  State<HappyStretchView> createState() => _HappyStretchViewState();
}

class _HappyStretchViewState extends State<HappyStretchView> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  int _currentTrack = 1;

  bool _isStretchVisible = true;
  bool _showSparkle = true;

  List<String> get _tracks => [
        'audios/happy/01HappyStretch.m4a',
        'audios/happy/02HappyStretch.m4a',
        'audios/happy/03HappyStretch.m4a',
      ];

  @override
  void initState() {
    super.initState();

    // Loop GIFs continuously while audio is playing
    _loopGifs();

    // When audio finishes, move to next track
    _audioPlayer.onPlayerComplete.listen((_) {
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
    await _audioPlayer.play(AssetSource(_tracks[_currentTrack - 1]));
  }

  void _loopGifs() async {
    while (mounted) {
      setState(() => _isStretchVisible = true);
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      setState(() => _isStretchVisible = false);
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
    }
  }

  Future<void> _onCompleted() async {
    final provider = context.read<CBTProvider>();
    await provider.markAsCompleted(widget.parentId, widget.childId, widget.exercise.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Well done! 🌟'),
          content: const Text(
              'You have completed the Happy Stretch exercise!\nKeep spreading happiness!'),
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
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 237, 150),
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: screenWidth * 0.9,
              height: 350,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Stretch / Hug GIF
                  Image.asset(
                    _isStretchVisible
                        ? 'assets/cbt/happy/Stretch_up.gif'
                        : 'assets/cbt/happy/Wide_hug.gif',
                    fit: BoxFit.contain,
                  ),
                  // Sparkles overlay
                  if (_showSparkle)
                    Positioned.fill(
                      child: Lottie.asset(
                        'assets/cbt/sparkle.json',
                        repeat: true,
                        width: 300,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'Segment $_currentTrack / ${_tracks.length}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
