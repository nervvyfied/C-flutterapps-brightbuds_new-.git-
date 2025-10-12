import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../widgets/cbt_exercise_viewer.dart';
import '../catalogs/cbt_catalog.dart';
import '/ui/pages/role_page.dart';

class ChildCBTPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;

  const ChildCBTPage({
    super.key,
    required this.parentId,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildCBTPage> createState() => _ChildCBTPageState();
}

class _ChildCBTPageState extends State<ChildCBTPage> {
  @override
  void initState() {
    super.initState();
    // Load CBT exercises for this child
    Future.microtask(() {
      context.read<CBTProvider>().loadCBT(widget.parentId, widget.childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();

    // Filter current week assignments
    final currentWeekAssignments =
        cbtProvider.getCurrentWeekAssignments().where((a) => a.childId == widget.childId).toList();

    return Scaffold(
      body: cbtProvider.assigned.isEmpty
          ? const Center(child: Text("No CBT exercises assigned this week."))
          : ListView.builder(
              itemCount: currentWeekAssignments.length,
              itemBuilder: (_, index) {
                final assigned = currentWeekAssignments[index];
                final exercise = CBTLibrary.getById(assigned.exerciseId);

                if (exercise == null) {
                  return const SizedBox.shrink(); // Skip if exercise not found
                }

                return CBTCard(
                  exercise: exercise,
                  isCompleted: cbtProvider.isCompleted(widget.childId, exercise.id),
                  onStart: () async {
                    // Open the CBT viewer
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CBTExerciseViewer(
                          exercise: exercise,
                          childId: widget.childId,
                          parentId: widget.parentId,
                        ),
                      ),
                    );

                    // Refresh provider after completing/viewing
                    await cbtProvider.loadCBT(widget.parentId, widget.childId);
                  },
                  onComplete: () async {
                    // Optionally mark as complete manually
                    await cbtProvider.markAsCompleted(
                        widget.parentId, widget.childId, assigned.id);
                  },
                );
              },
            ),
    );
  }
}
