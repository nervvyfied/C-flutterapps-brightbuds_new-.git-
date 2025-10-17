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
          : Padding(
              padding: const EdgeInsets.all(16), // ✨ add padding here
              child: ListView.builder(
                itemCount: currentWeekAssignments.length,
                itemBuilder: (_, index) {
                  final assigned = currentWeekAssignments[index];
                  final exercise = CBTLibrary.getById(assigned.exerciseId);

                  if (exercise == null) {
                    return const SizedBox.shrink();
                  }

                  return CBTCard(
                    exercise: exercise,
                    isParentView: false,
                    isCompleted: cbtProvider.isCompleted(widget.childId, exercise.id),
                    onStart: () async {
                      final assignedEntry = cbtProvider.assigned.firstWhere(
                        (a) => a.exerciseId == exercise.id && a.childId == widget.childId,
                      );

                      if (!cbtProvider.canExecute(assignedEntry)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('You already completed this CBT for now.')),
                        );
                        return;
                      }

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

                      await cbtProvider.loadCBT(widget.parentId, widget.childId);
                    },
                    onComplete: () async {
                      final assignedEntry = cbtProvider.assigned.any(
                        (a) => a.exerciseId == exercise.id && a.childId == widget.childId,
                      )
                          ? cbtProvider.assigned.firstWhere(
                              (a) => a.exerciseId == exercise.id && a.childId == widget.childId,
                            )
                          : null;

                      if (assignedEntry == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This exercise is not assigned.')),
                        );
                        return;
                      }

                      final success = await cbtProvider.markAsCompleted(
                        widget.parentId,
                        widget.childId,
                        assignedEntry.id,
                      );

                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot complete again within recurrence window.')),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Well done! Exercise completed.')),
                        );
                      }
                    },
                  );
                },
              ),
            ),
    );
  }
}
