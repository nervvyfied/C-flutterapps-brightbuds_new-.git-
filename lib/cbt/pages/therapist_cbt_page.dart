// ignore_for_file: use_build_context_synchronously

import 'package:brightbuds_new/cbt/models/assigned_cbt_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/cbt_catalog.dart';
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../models/cbt_exercise_model.dart';

class TherapistCBTPage extends StatefulWidget {
  final String therapistId;
  final String childId;
  final String parentId; // This is the CORRECT parent ID!
  final String? suggestedMood;

  const TherapistCBTPage({
    super.key,
    required this.therapistId,
    required this.childId,
    required this.parentId,
    this.suggestedMood,
  });

  @override
  State<TherapistCBTPage> createState() => _TherapistCBTPageState();
}

class _TherapistCBTPageState extends State<TherapistCBTPage> {
  String _selectedCategory = 'All';
  late String _actualParentId; // Will store the verified parent ID
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // DEBUG: Verify we have the correct IDs
    print('🎯 TherapistCBTPage initialized:');
    print('   Therapist ID: ${widget.therapistId}');
    print('   Child ID: ${widget.childId}');
    print('   Parent ID from parameter: ${widget.parentId}');

    // Set initial parent ID from parameter
    _actualParentId = widget.parentId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _verifyAndLoadCBT();
    });
  }

  Future<void> _verifyAndLoadCBT() async {
    setState(() => _isLoading = true);

    try {
      // Verify that the parentId is NOT the therapistId
      if (widget.parentId == widget.therapistId) {
        print('🚨 ERROR: Parent ID equals Therapist ID!');
        print('🚨 widget.parentId: ${widget.parentId}');
        print('🚨 widget.therapistId: ${widget.therapistId}');

        // Try to find the real parent ID
        _actualParentId = await _getRealParentIdForChild(widget.childId);

        if (_actualParentId.isEmpty || _actualParentId == widget.therapistId) {
          throw Exception('❌ Cannot find valid parent for child');
        }

        print('✅ Found real parent ID: $_actualParentId');
      } else {
        _actualParentId = widget.parentId;
      }

      print('📥 Loading CBT from parent: $_actualParentId');

      // Load CBT from the CORRECT parent's collection
      await context.read<CBTProvider>().loadRemoteCBT(
        _actualParentId,
        widget.childId,
      );
    } catch (e) {
      print('❌ Error loading CBT: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading CBT: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // SIMPLE method to get the real parent ID for a child
  // SIMPLE method to get the real parent ID for a child
  Future<String> _getRealParentIdForChild(String childId) async {
    if (childId.isEmpty) return '';

    print('🔍 Finding real parent for child: $childId');

    try {
      // 1. Check therapist's children collection for parentUID
      final childInTherapist = await FirebaseFirestore.instance
          .collection('therapists')
          .doc(widget.therapistId)
          .collection('children')
          .doc(childId)
          .get();

      if (childInTherapist.exists) {
        final data = childInTherapist.data();
        final parentUID = data?['parentUID'] ?? data?['parentId'];

        if (parentUID != null && parentUID is String && parentUID.isNotEmpty) {
          // CRITICAL: Check this is NOT the therapist ID
          if (parentUID != widget.therapistId) {
            print('✅ Found parentUID in therapist collection: $parentUID');

            // Verify this parent exists in users collection
            final parentDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(parentUID)
                .get();

            if (parentDoc.exists) {
              print('✅ Parent $parentUID exists in users collection');
              return parentUID;
            } else {
              print('⚠️ Parent $parentUID NOT found in users collection');
            }
          } else {
            print('🚨 WARNING: parentUID equals therapistId!');
          }
        }
      }

      // 2. Search through all users (skip if they're therapists)
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(100)
          .get();

      for (final userDoc in usersSnapshot.docs) {
        final userId = userDoc.id;
        final userData = userDoc.data();
        final userRole = userData['role'] as String?;

        // SKIP if this user is a therapist
        if (userRole == 'therapist') {
          print('⏭️ Skipping therapist user: $userId');
          continue;
        }

        try {
          final childDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('children')
              .doc(childId)
              .get();

          if (childDoc.exists) {
            print('✅ Found child in user $userId children collection');
            return userId;
          }
        } catch (e) {
          // Continue checking other users
        }
      }

      print('❌ Could not find parent for child: $childId');
      return '';
    } catch (e) {
      print('❌ Error finding parent: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final assignedIds = cbtProvider
        .getCurrentWeekAssignments(childId: widget.childId)
        .map((a) => a.exerciseId)
        .toSet();
    final exercises = CBTLibrary.all;
    final currentWeekAssignments = cbtProvider.getCurrentWeekAssignments(
      childId: widget.childId,
    );

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
          if (_isLoading) const Center(child: CircularProgressIndicator()),
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Assign CBT Exercises',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                            ],
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
                                assigningSet.contains(exercise.id)) {
                              return;
                            }

                            assigningSet.add(exercise.id);

                            try {
                              print('🎯 Assigning CBT with:');
                              print('   Therapist: ${widget.therapistId}');
                              print('   Child: ${widget.childId}');
                              print('   Parent ID to use: $_actualParentId');

                              await cbtProvider.assignManualCBT(
                                widget.therapistId,
                                widget.childId,
                                exercise,
                                overrideParentId: _actualParentId,
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${exercise.title} assigned!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              print('❌ Error assigning CBT: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to assign: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } finally {
                              assigningSet.remove(exercise.id);
                            }
                          },
                          onUnassign: () async {
                            if (!isAssigned ||
                                assigningSet.contains(exercise.id)) {
                              return;
                            }

                            assigningSet.add(exercise.id);

                            try {
                              // Pass the SAME parent ID to unassignCBT
                              await cbtProvider.unassignCBT(
                                widget.therapistId,
                                widget.childId,
                                assignedEntry!.id,
                                overrideParentId:
                                    _actualParentId, // PASS THE SAME PARENT ID HERE
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${exercise.title} unassigned.',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to unassign: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } finally {
                              assigningSet.remove(exercise.id);
                            }
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
                backgroundColor: Colors.orange,
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
