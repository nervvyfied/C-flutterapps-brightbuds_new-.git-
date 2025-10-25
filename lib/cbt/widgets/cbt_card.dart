import 'package:flutter/material.dart';
import '../models/cbt_exercise_model.dart';

class CBTCard extends StatelessWidget {
  final CBTExercise exercise;
  final VoidCallback? onStart;
  final VoidCallback? onAssign;
  final VoidCallback? onUnassign;
  final VoidCallback? onComplete;
  final bool isCompleted;
  final bool isParentView;
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
        color: (isSuggested
                ? (isCompleted ? Colors.green[50] : Colors.yellow[50])
                : (isCompleted ? Colors.green[50] : Colors.white))
            ?.withOpacity(0.85),
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
            Text(
              exercise.title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isCompleted ? Colors.green[700] : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              exercise.description,
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            Text(
              '${exercise.mood.toUpperCase()} • ${exercise.recurrence.toUpperCase()}',
              style: TextStyle(color: Colors.blueGrey[600]),
            ),
            const SizedBox(height: 6),
            Text(
              'Duration: ${exercise.duration}',
              style: TextStyle(color: Colors.blueGrey[600]),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isParentView) ...[
                  if (!isAssigned)
                    ElevatedButton.icon(
                      onPressed: onAssign,
                      icon: const Icon(Icons.add, size: 18, color: Colors.white),
                      label: const Text('Assign', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA6C26F)),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: onUnassign,
                      icon: const Icon(Icons.remove_circle, size: 18, color: Colors.white),
                      label: Text(
                        isCompleted ? 'Completed' : 'Assigned', // <-- show completion visually
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCompleted ? Colors.green : const Color(0xFFFD5C68),
                      ),
                    ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: isCompleted ? null : onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCompleted ? Colors.grey : const Color(0xFFA6C26F),
                    ),
                    icon: Icon(
                      isCompleted ? Icons.check : Icons.play_arrow, 
                      size: 18,
                      color: Colors.white
                    ),
                    label: Text(isCompleted ? 'Completed' : 'Start', style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
