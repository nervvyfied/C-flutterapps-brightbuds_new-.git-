import 'package:flutter/material.dart';
import '../models/cbt_exercise_model.dart';

class CBTExerciseViewer extends StatelessWidget {
  final CBTExercise exercise;
  final String childId;

  const CBTExerciseViewer({
    super.key,
    required this.exercise,
    required this.childId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              exercise.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              exercise.description,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                // later this triggers animation + audio logic
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Launching ${exercise.title}...')),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
    );
  }
}
