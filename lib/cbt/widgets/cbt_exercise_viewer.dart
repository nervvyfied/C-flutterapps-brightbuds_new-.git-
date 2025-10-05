import 'package:brightbuds_new/cbt/widgets/cbt_exercises/bubble_pop_view.dart';
import 'package:brightbuds_new/cbt/widgets/cbt_exercises/happy_stretch_view.dart';
import 'package:brightbuds_new/cbt/widgets/cbt_exercises/step_stone_view.dart';
import 'package:brightbuds_new/cbt/widgets/cbt_exercises/worry_box_view.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../models/cbt_exercise_model.dart';
import '../providers/cbt_provider.dart';
import 'cbt_exercises/garden_meditation_view.dart';
import 'cbt_exercises/gratitude_rainbow_view.dart';

class CBTExerciseViewer extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;

  const CBTExerciseViewer({
    super.key,
    required this.exercise,
    required this.childId,
  });

  @override
  State<CBTExerciseViewer> createState() => _CBTExerciseViewerState();
}

class _CBTExerciseViewerState extends State<CBTExerciseViewer> {
  final AudioPlayer _player = AudioPlayer();
  int _currentTrack = 0; // start at 0
  bool _isPlaying = false;

  List<String> get _tracks {
    switch (widget.exercise.mood) {
      case 'calm':
        return [
          'audios/calm/01GardenMeditation.m4a',
          'audios/calm/02GardenMeditation.m4a',
          'audios/calm/03GardenMeditation.m4a',
        ];
      case 'happy':
        return [
          'audios/happy/01HappyStretch.m4a',
          'audios/happy/02HappyStretch.m4a',
          'audios/happy/03HappyStretch.m4a',
        ];
      case 'angry':
        return [
          'audios/angry/01BubblePop.m4a',
          'audios/angry/02BubblePop.m4a',
          'audios/angry/03BubblePop.m4a',
        ];
      default:
        return [];
    }
  }

  @override
  void initState() {
    super.initState();

    // 🌟 Redirect to special animated CBT views
    if (widget.exercise.id == 'calm_garden') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GardenMeditationView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }

    if (widget.exercise.id == 'sad_rainbow') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GratitudeRainbowView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }

    if (widget.exercise.id == 'happy_stretch') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HappyStretchView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }

    if (widget.exercise.id == 'confused_stepstone') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StepStoneView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }

    if (widget.exercise.id == 'angry_bubble') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BubblePopView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }

    if (widget.exercise.id == 'scared_worrybox') {
      Future.microtask(() {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WorryBoxView(
              exercise: widget.exercise,
              childId: widget.childId,
            ),
          ),
        );
      });
      return;
    }



    _playNext();
  }

  Future<void> _playNext() async {
    if (_currentTrack >= _tracks.length) {
      await _onCompleted();
      return;
    }

    setState(() {
      _isPlaying = true;
    });

    await _player.play(AssetSource(_tracks[_currentTrack]));

    _player.onPlayerComplete.listen((_) {
      setState(() {
        _currentTrack++;
        _isPlaying = false;
      });
      if (_currentTrack < _tracks.length) {
        _playNext();
      } else {
        _onCompleted();
      }
    });
  }

  Future<void> _onCompleted() async {
    final provider = context.read<CBTProvider>();
    await provider.markAsCompleted(
        'parentId', widget.childId, widget.exercise.id);

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Well done!'),
          content: Text('You’ve completed the "${widget.exercise.title}" exercise!'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(context); // return to CBT page
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moodColor = {
      'calm': Colors.green[200],
      'happy': Colors.yellow[200],
      'angry': Colors.red[200],
    }[widget.exercise.mood] ??
        Colors.blueGrey[100];

    return Scaffold(
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: AnimatedContainer(
        duration: const Duration(seconds: 2),
        color: moodColor,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Track ${_currentTrack + 1} / ${_tracks.length}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text(
                'Playing ${widget.exercise.title}',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 40),
              if (_isPlaying)
                const CircularProgressIndicator()
              else if (_currentTrack >= _tracks.length)
                const Icon(Icons.check_circle, color: Colors.green, size: 60),
            ],
          ),
        ),
      ),
    );
  }
}
