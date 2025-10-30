// ignore_for_file: file_names

import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import '../models/fish_definition.dart';
import 'unlockNotifier.dart';

class UnlockDialog extends StatefulWidget {
  final FishDefinition fish;

  const UnlockDialog({super.key, required this.fish});

  @override
  State<UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<UnlockDialog> {
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
    final unlockNotifier = context.read<UnlockNotifier>();

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
            "🎉 New Unlock!",
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(widget.fish.storeIconAsset, width: 100, height: 100),
              const SizedBox(height: 12),
              Text(
                "You unlocked ${widget.fish.name}!",
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(widget.fish.description, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    unlockNotifier.clear();
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed("/achievements");
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
