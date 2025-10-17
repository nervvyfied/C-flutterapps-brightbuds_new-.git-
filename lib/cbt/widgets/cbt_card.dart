import 'package:flutter/material.dart';
import '../models/cbt_exercise_model.dart';

class CBTCard extends StatelessWidget {
  final CBTExercise exercise;
  final VoidCallback? onStart;
  final VoidCallback? onAssign;
  final VoidCallback? onUnassign;
  final VoidCallback? onComplete;
  final bool isCompleted;
  final bool isParentView; // if true, show assign/unassign controls
  final bool isAssigned;
  final bool isSuggested;

  const CBTCard({
    super.key,
    required this.exercise,
    this.onStart,
    this.onAssign,
    this.onUnassign,
    this.onComplete,
    this.isCompleted = false,
    this.isParentView = false,
    this.isAssigned = false,
    this.isSuggested = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isSuggested ? (isCompleted ? Colors.green[50] : Colors.yellow[50]) : (isCompleted ? Colors.green[50] : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: isSuggested ? Border.all(color: Colors.orangeAccent, width: 1.6) : null,
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
                  '${exercise.mood.toUpperCase()} • ${exercise.duration} • ${exercise.recurrence.toUpperCase()}',
                  style: TextStyle(color: Colors.blueGrey[600]),
                ),
                Row(
                  children: [
                    if (isParentView) ...[
                      if (!isAssigned)
                        ElevatedButton.icon(
                          onPressed: onAssign,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Assign'),
                        )
                      else
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: onUnassign,
                          icon: const Icon(Icons.remove_circle, size: 18),
                          label: const Text('Unassign'),
                        ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: isCompleted ? null : onStart, // 🔒 disable if completed
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCompleted ? Colors.grey : Colors.blue,
                        ),
                        icon: Icon(
                          isCompleted ? Icons.check : Icons.play_arrow,
                          size: 18,
                        ),
                        label: Text(isCompleted ? 'Completed' : 'Start'),
                      ),
                    ],
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
