import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/cbt_catalog.dart';
import '../models/cbt_exercise_model.dart';
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../widgets/cbt_exercise_viewer.dart';

class ChildCBTPage extends StatefulWidget {
  final String childId;
  const ChildCBTPage({super.key, required this.childId});

  @override
  State<ChildCBTPage> createState() => _ChildCBTPageState();
}

class _ChildCBTPageState extends State<ChildCBTPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Temporarily use dummy parentId for testing
      await context.read<CBTProvider>().loadCBT('parentId', widget.childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final exercises = CBTLibrary.all; // show all CBTs (dummy list for now)

    return Scaffold(
      appBar: AppBar(
        title: const Text('CBT Exercises'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView.builder(
          itemCount: exercises.length,
          itemBuilder: (context, index) {
            final CBTExercise exercise = exercises[index];
            return CBTCard(
              exercise: exercise,
              isCompleted: false, // TODO: replace with provider check
              onStart: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CBTExerciseViewer(
                      exercise: exercise,
                      childId: widget.childId,
                    ),
                  ),
                );
              },
              onComplete: () async {
                await cbtProvider.markAsCompleted('parentId', widget.childId, exercise.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${exercise.title} marked complete!')),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
