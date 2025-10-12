import 'package:flutter/material.dart';
import '../models/cbt_exercise_model.dart';

class CBTCard extends StatelessWidget {
  final CBTExercise exercise;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final bool isCompleted;

  const CBTCard({
    super.key,
    required this.exercise,
    required this.onStart,
    required this.onComplete,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exercise.title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isCompleted ? Colors.green[700] : Colors.black87,
                    ),
                  ),
                ),
                if (isCompleted)
                  const Icon(Icons.check_circle, color: Colors.green, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              exercise.description,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${exercise.mood.toUpperCase()} • ${exercise.duration}',
                  style: TextStyle(color: Colors.blueGrey[600]),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text(isCompleted ? 'Assigned' : 'Assign'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
