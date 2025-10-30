// ignore_for_file: file_names
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:lottie/lottie.dart';

class TokenDialog extends StatelessWidget {
  final List<TaskModel> tasks;
  final ConfettiController confettiController;

  const TokenDialog({
    required this.tasks,
    required this.confettiController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Blur background
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          // ignore: deprecated_member_use
          child: Container(color: Colors.black.withOpacity(0.3)),
        ),
        AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          title: Column(
            children: [
              Lottie.asset(
                'assets/star.json',
                width: 100,
                height: 100,
                repeat: false,
              ),
              const SizedBox(height: 8),
              const Text(
                'Congratulations!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8657F3),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'You earned tokens for completing tasks!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: tasks
                  .map(
                    (task) => Card(
                      color: const Color(0xFFF7F2FF),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Image.asset('assets/coin.png', width: 24, height: 24),
                        title: Text(task.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Text(
                          '${task.reward} token(s)',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8657F3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Yay!'),
              ),
            ),
          ],
        ),
        // Confetti overlay
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
