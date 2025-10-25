import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../../providers/cbt_provider.dart';
import '../../models/cbt_exercise_model.dart';

class BubblePopView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;
  final String parentId;

  const BubblePopView({
    super.key,
    required this.exercise,
    required this.childId,
    required this.parentId
  });

  @override
  State<BubblePopView> createState() => _BubblePopViewState();
}

class _BubblePopViewState extends State<BubblePopView>
    with TickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  int _currentTrack = 1;
  bool _popped = false;
  bool _showPopImage = false;
  bool _showSparkle = false;
  bool _completed = false;

  late AnimationController _breathController;
  late AnimationController _colorController;

  List<String> get _tracks => [
        'audios/angry/01BubblePop.m4a',
        'audios/angry/02BubblePop.m4a',
        'audios/angry/03BubblePop.m4a',
      ];

  @override
  void initState() {
    super.initState();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..forward();

    _player.onPlayerComplete.listen((_) async {
      if (_currentTrack < _tracks.length) {
        setState(() => _currentTrack++);
        await _playNextTrackSequence();
      } else {
        _triggerPopSequence();
      }
    });

    _startTrackSequence();
  }

  Future<void> _startTrackSequence() async {
    await _playNextTrackSequence();
  }

  Future<void> _playNextTrackSequence() async {
    switch (_currentTrack) {
      case 1:
        await _trackOneSequence();
        break;
      case 2:
        await _trackTwoSequence();
        break;
      case 3:
        await _trackThreeSequence();
        break;
    }
  }

  Future<void> _trackOneSequence() async {
    await _player.play(AssetSource(_tracks[0]));
    await Future.delayed(const Duration(seconds: 3)); // wait before inhale

    // gentle single inhale
    await _breathController.forward();
  }

  Future<void> _trackTwoSequence() async {
    await _player.play(AssetSource(_tracks[1]));
    await Future.delayed(const Duration(seconds: 5)); // wait before first exhale

    // perform 4 inhale/exhale cycles
    for (int i = 0; i < 4; i++) {
      await _breathController.reverse(); // exhale
      await Future.delayed(const Duration(milliseconds: 300));
      await _breathController.forward(); // inhale
    }

    // end slightly shrunk (exhale)
    await _breathController.reverse();
  }

  Future<void> _trackThreeSequence() async {
    await _player.play(AssetSource(_tracks[2]));
    await Future.delayed(const Duration(seconds: 3)); // wait before final inhale

    // gentle last inhale then exhale → pop
    await _breathController.forward();
    await _breathController.reverse();

    await _triggerPopSequence();
  }

  Future<void> _triggerPopSequence() async {
    if (_popped) return;
    setState(() => _popped = true);

    _breathController.stop();

    setState(() => _showPopImage = true);
    await Future.delayed(const Duration(milliseconds: 400));
    setState(() => _showPopImage = false);
    await Future.delayed(const Duration(milliseconds: 200));
    setState(() => _showSparkle = true);
    await Future.delayed(const Duration(seconds: 2));

    final provider = context.read<CBTProvider>();
    final assigned = provider.assigned.firstWhere(
    (a) => a.exerciseId == widget.exercise.id && a.childId == widget.childId,
    orElse: () => throw Exception('Assigned CBT not found for this exercise'),
  );

  await provider.markAsCompleted(widget.parentId, widget.childId, assigned.id);

    setState(() => _completed = true);
    if (mounted) _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Great job! 🎈'),
        content: const Text(
          "You released your anger and calmed your mind.\n"
          "Remember this feeling next time you feel upset.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _breathController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.blue[100],
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Background color transition (warm → cool)
          AnimatedBuilder(
            animation: _colorController,
            builder: (_, __) {
              final bg = ColorTween(
                begin: Colors.red.shade200,
                end: Colors.blue.shade200,
              ).animate(_colorController);
              return Container(color: bg.value);
            },
          ),

          // Bubble breathing animation
          if (!_popped)
            AnimatedBuilder(
              animation: Listenable.merge([_breathController, _colorController]),
              builder: (_, __) {
                final scale = 0.9 + 0.35 * Curves.easeInOut.transform(_breathController.value);

                final bubbleColorTween = ColorTween(
                  begin: Colors.redAccent,
                  end: Colors.lightBlueAccent,
                ).animate(_colorController);

                return Transform.scale(
                  scale: scale,
                  child: Image.asset(
                    'assets/cbt/angry/bubble.png',
                    width: screenWidth * 0.65,
                    color: bubbleColorTween.value,
                    colorBlendMode: BlendMode.modulate,
                  ),
                );
              },
            ),

          if (_showPopImage)
            Image.asset('assets/cbt/angry/bubble_pop.png', width: screenWidth * 0.7),

          if (_showSparkle)
            Lottie.asset('assets/cbt/sparkle.json', width: 300, repeat: false),

          // Move instructions to top
Positioned(
  top: 100, // distance from top
  left: 16,
  right: 16,
  child: AnimatedOpacity(
    opacity: _completed ? 0 : 1,
    duration: const Duration(milliseconds: 500),
    child: Column(
      children: [
        Text(
          _currentTrack == 1
              ? "Look at the red bubble... wait... now breathe in slowly."
              : _currentTrack == 2
                  ? "In... and out... follow the bubble’s rhythm."
                  : "One last deep breath... and let it go.",
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
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
