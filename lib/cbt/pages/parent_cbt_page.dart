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
      context.read<CBTProvider>().syncPendingCompletions(widget.parentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final assignedIds = cbtProvider
        .getCurrentWeekAssignments()
        .map((a) => a.exerciseId)
        .toSet();
    final exercises = CBTLibrary.all;
    final currentWeekAssignments = cbtProvider.getCurrentWeekAssignments();

    final Map<String, AssignedCBT> assignedMap = {
      for (var a in currentWeekAssignments) a.exerciseId: a,
    };
    final Set<String> assigningSet = {};

    // Filter exercises by selected mood
    List<CBTExercise> filtered = _selectedCategory == 'All'
        ? exercises
        : exercises
              .where(
                (e) => e.mood.toLowerCase() == _selectedCategory.toLowerCase(),
              )
              .toList();

    // Suggested CBT based on passed mood
    final moodToSuggest = widget.suggestedMood?.toLowerCase() ?? 'calm';
    CBTExercise suggested = exercises.firstWhere(
      (e) => e.mood.toLowerCase() == moodToSuggest,
      orElse: () => exercises.first,
    );

    // Put suggested CBT first if "All" is selected
    if (_selectedCategory == 'All') {
      filtered.sort((a, b) {
        if (a.id == suggested.id) return -1;
        if (b.id == suggested.id) return 1;
        return 0;
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Header container with back icon
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8657F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Assign CBT Exercises',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Sorting buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final gridHeight =
                          3 * 46 + 2 * 6; // 3 rows x 46 height + 2 gaps
                      return Row(
                        children: [
                          // "All" button
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: gridHeight.toDouble(),
                              child: _buildMoodButton(
                                'All',
                                const Color.fromRGBO(255, 255, 255, 1),
                                selected: _selectedCategory == 'All',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 2x3 grid for other moods
                          Expanded(
                            flex: 7,
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Happy',
                                        const Color.fromRGBO(254, 207, 0, 1),
                                        selected: _selectedCategory == 'Happy',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Sad',
                                        const Color.fromARGB(255, 87, 160, 243),
                                        selected: _selectedCategory == 'Sad',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Angry',
                                        const Color.fromARGB(255, 253, 92, 103),
                                        selected: _selectedCategory == 'Angry',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Calm',
                                        const Color.fromARGB(
                                          255,
                                          166,
                                          194,
                                          111,
                                        ),
                                        selected: _selectedCategory == 'Calm',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Scared',
                                        const Color.fromARGB(255, 134, 87, 243),
                                        selected: _selectedCategory == 'Scared',
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _buildMoodButton(
                                        'Confused',
                                        const Color.fromARGB(255, 252, 139, 52),
                                        selected:
                                            _selectedCategory == 'Confused',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // List of CBT cards
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final exercise = filtered[index];
                        final assignedEntry = assignedMap[exercise.id];
                        final isAssigned = assignedEntry != null;
                        final isCompleted = assignedEntry?.completed ?? false;
                        final isSuggested = exercise.id == suggested.id;

                        return CBTCard(
                          exercise: exercise,
                          isParentView: true,
                          isAssigned: isAssigned,
                          isCompleted: isCompleted,
                          isSuggested: isSuggested,
                          onAssign: () async {
                            if (isAssigned ||
                                assigningSet.contains(exercise.id))
                              return;

                            // Mark as assigning
                            assigningSet.add(exercise.id);
                            await cbtProvider.assignManualCBT(
                              widget.parentId,
                              widget.childId,
                              exercise,
                            );
                            // Remove from assigning after done
                            assigningSet.remove(exercise.id);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${exercise.title} assigned!'),
                              ),
                            );
                          },
                          onUnassign: () async {
                            if (!isAssigned ||
                                assigningSet.contains(exercise.id))
                              return;

                            assigningSet.add(exercise.id);
                            await cbtProvider.unassignCBT(
                              widget.parentId,
                              widget.childId,
                              assignedEntry!.id,
                            );
                            assigningSet.remove(exercise.id);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${exercise.title} unassigned.'),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final hasSuggestedAssigned = assignedIds.contains(suggested.id);
          if (!hasSuggestedAssigned) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please assign the suggested CBT first!'),
              ),
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

  Widget _buildMoodButton(String label, Color color, {bool selected = false}) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = label),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.85) : color.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: Colors.black, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Color.fromARGB(255, 0, 0, 0),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
