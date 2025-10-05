import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class CBTPlayerWidget extends StatefulWidget {
  final String mood; // calm, happy, angry
  final VoidCallback onCompleted;

  const CBTPlayerWidget({super.key, required this.mood, required this.onCompleted});

  @override
  State<CBTPlayerWidget> createState() => _CBTPlayerWidgetState();
}

class _CBTPlayerWidgetState extends State<CBTPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  int _currentTrack = 1;
  bool _isPlaying = false;

  List<String> get _tracks => [
        'assets/audios/${widget.mood}/01${_title()}.mp3',
        'assets/audios/${widget.mood}/02${_title()}.mp3',
        'assets/audios/${widget.mood}/03${_title()}.mp3',
      ];

  String _title() {
    switch (widget.mood) {
      case 'calm':
        return 'GardenMeditation';
      case 'happy':
        return 'HappyStretch';
      case 'angry':
        return 'BubblePop';
      default:
        return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _playNext();
  }

  Future<void> _playNext() async {
    if (_currentTrack > 3) {
      widget.onCompleted();
      return;
    }

    setState(() => _isPlaying = true);
    await _player.play(AssetSource(_tracks[_currentTrack - 1].replaceFirst('assets/', '')));

    _player.onPlayerComplete.listen((_) {
      setState(() {
        _currentTrack++;
      });
      _playNext();
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Simple placeholder animation — replace later
        AnimatedContainer(
          duration: const Duration(seconds: 2),
          color: widget.mood == 'calm'
              ? Colors.green[200]
              : widget.mood == 'happy'
                  ? Colors.yellow[200]
                  : Colors.red[200],
          child: const Center(child: Text('Playing CBT Exercise...', style: TextStyle(fontSize: 20))),
        ),
        if (_isPlaying)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Track $_currentTrack / 3', style: const TextStyle(fontSize: 16)),
            ),
          ),
      ],
    );
  }
}
