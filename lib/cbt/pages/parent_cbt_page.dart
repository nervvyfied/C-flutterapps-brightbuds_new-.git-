import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/cbt_catalog.dart';
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';

class ParentCBTPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const ParentCBTPage({super.key, required this.parentId, required this.childId});

  @override
  State<ParentCBTPage> createState() => _ParentCBTPageState();
}

class _ParentCBTPageState extends State<ParentCBTPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CBTProvider>().loadAssignedCBTs(widget.parentId, widget.childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final assignedIds = cbtProvider.getCurrentWeekAssignments().map((a) => a.exerciseId).toSet();
    final exercises = CBTLibrary.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Assign CBT Exercises')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          itemCount: exercises.length,
          itemBuilder: (context, index) {
            final exercise = exercises[index];
            final isAssigned = assignedIds.contains(exercise.id);

            return CBTCard(
              exercise: exercise,
              isCompleted: isAssigned, // indicate it's already assigned
              onStart: () async {
                if (!isAssigned) {
                  await cbtProvider.assignManualCBT(
                      widget.parentId, widget.childId, exercise);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${exercise.title} assigned!')),
                  );
                }
              },
              onComplete: () {}, // No completion logic here
            );
          },
        ),
      ),
    );
  }
}
