import 'package:brightbuds_new/cbt/models/assigned_cbt_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/cbt_catalog.dart';
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../models/cbt_exercise_model.dart';

class ParentCBTPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String? suggestedMood;

  const ParentCBTPage({
    super.key,
    required this.parentId,
    required this.childId,
    this.suggestedMood,
  });

  @override
  State<ParentCBTPage> createState() => _ParentCBTPageState();
}

class _ParentCBTPageState extends State<ParentCBTPage> {
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CBTProvider>().loadLocalCBT(widget.parentId, widget.childId);
      // Optional: attempt remote sync if online
      context.read<CBTProvider>().syncPendingCompletions(widget.parentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final assignedIds =
        cbtProvider.getCurrentWeekAssignments().map((a) => a.exerciseId).toSet();
    final exercises = CBTLibrary.all;

    // 🔹 Filter by category (mood)
    List<CBTExercise> filtered = _selectedCategory == 'All'
        ? exercises
        : exercises
            .where((e) => e.mood.toLowerCase() == _selectedCategory.toLowerCase())
            .toList();

    // 🔹 Find suggested CBT based on passed mood
    final moodToSuggest = widget.suggestedMood?.toLowerCase() ?? 'calm';
    CBTExercise suggested = exercises.firstWhere(
      (e) => e.mood.toLowerCase() == moodToSuggest,
      orElse: () => exercises.first,
    );

    // 🔹 Reorder so suggested CBT appears first in "All"
    if (_selectedCategory == 'All') {
      filtered.sort((a, b) {
        if (a.id == suggested.id) return -1;
        if (b.id == suggested.id) return 1;
        return 0;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign CBT Exercises'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: _buildCategoryTabs(),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final exercise = filtered[index];
            final isAssigned = assignedIds.contains(exercise.id);
            final isSuggested = exercise.id == suggested.id;

            return CBTCard(
              exercise: exercise,
              isParentView: true,
              isAssigned: isAssigned,
              isSuggested: isSuggested,
              onAssign: () async {
                if (isAssigned) return;
                await cbtProvider.assignManualCBT(
                    widget.parentId, widget.childId, exercise);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${exercise.title} assigned!')),
                );
              },
              onUnassign: () async {
                // ✅ Proper null-safe handling
                AssignedCBT? assignedEntry;
                try {
                  assignedEntry = cbtProvider.assigned.firstWhere(
                    (a) =>
                        a.exerciseId == exercise.id &&
                        a.childId == widget.childId,
                  );
                } catch (_) {
                  assignedEntry = null;
                }
                if (assignedEntry == null) return;

                await cbtProvider.unassignCBT(
                    widget.parentId, widget.childId, assignedEntry.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${exercise.title} unassigned.')),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final hasSuggestedAssigned = assignedIds.contains(suggested.id);
          if (!hasSuggestedAssigned) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Please assign the suggested CBT first!')),
            );
          } else {
            Navigator.pop(context);
          }
        },
        label: const Text('Done Assigning'),
        icon: const Icon(Icons.check),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    final moods = ['All', 'Happy', 'Sad', 'Angry', 'Calm', 'Anxious', 'Confused'];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: moods.length,
        itemBuilder: (context, index) {
          final cat = moods[index];
          final isSelected = cat == _selectedCategory;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: ChoiceChip(
              label: Text(cat),
              selected: isSelected,
              selectedColor: Colors.blueAccent,
              labelStyle: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87),
              onSelected: (_) => setState(() => _selectedCategory = cat),
            ),
          );
        },
      ),
    );
  }
}
