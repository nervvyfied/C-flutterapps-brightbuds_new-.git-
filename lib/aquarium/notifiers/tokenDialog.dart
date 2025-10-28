import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:brightbuds_new/data/models/task_model.dart';

class TokenDialog extends StatelessWidget {
  final List<TaskModel> tasks;
  final ConfettiController confettiController;

  const TokenDialog({required this.tasks, required this.confettiController, super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AlertDialog(
          title: const Text('You received tokens!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: tasks
                .map((task) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${task.reward ?? 0} token(s) for "${task.name}"'),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
        Positioned.fill(
          child: ConfettiWidget(
            confettiController: confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [Colors.yellow, Colors.blue, Colors.pink, Colors.green, Colors.orange],
            numberOfParticles: 30,
            gravity: 0.3,
          ),
        ),
      ],
    );
  }
}
