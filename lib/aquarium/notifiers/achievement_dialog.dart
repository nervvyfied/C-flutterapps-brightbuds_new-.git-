import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../models/achievement_definition.dart';
import 'package:provider/provider.dart';
import '../notifiers/achievement_notifier.dart';

class AchievementDialog extends StatefulWidget {
  final AchievementDefinition achievement;
  const AchievementDialog({super.key, required this.achievement});

  @override
  State<AchievementDialog> createState() => _AchievementDialogState();
}

class _AchievementDialogState extends State<AchievementDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.read<AchievementNotifier>();

    return Stack(
      alignment: Alignment.center,
      children: [
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirectionality: BlastDirectionality.explosive,
          shouldLoop: false,
          numberOfParticles: 25,
        ),
        AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            "🏆 Achievement Unlocked!",
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(widget.achievement.iconAsset, width: 100, height: 100),
              const SizedBox(height: 12),
              Text(
                "You unlocked ${widget.achievement.title}!",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(widget.achievement.description, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    notifier.clear();
                    Navigator.of(context).pop();
                    Navigator.of(context, rootNavigator: true)
                    .pushNamed("/achievements");
                  },
                  child: const Text("Go to Achievements"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
