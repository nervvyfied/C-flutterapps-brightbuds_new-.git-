import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../widgets/cbt_exercise_viewer.dart';
import '../catalogs/cbt_catalog.dart';
import '/utils/network_helper.dart';

class ChildCBTPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const ChildCBTPage({
    super.key,
    required this.parentId,
    required this.childId,
  });

  @override
  State<ChildCBTPage> createState() => _ChildCBTPageState();
}

class _ChildCBTPageState extends State<ChildCBTPage> {
  bool _isOffline = false;
  bool _isSyncing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final cbtProvider = context.read<CBTProvider>();
    // Start the real-time listener
    cbtProvider.startRealtimeCBTUpdates(widget.parentId, widget.childId);
    _loadCBT();
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  Future<void> _loadCBT() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final cbtProvider = context.read<CBTProvider>();

    // Load local CBT first (offline-first)
    await cbtProvider.loadLocalCBT(widget.childId);

    // Check connectivity
    await _checkConnectivity();

    // If online, sync pending completions and fetch remote
    if (!_isOffline) {
      if (!mounted) return;
      setState(() => _isSyncing = true);

      await cbtProvider.syncPendingCompletions(widget.childId);
      await cbtProvider.loadRemoteCBT(widget.parentId, widget.childId);

      if (!mounted) return;
      setState(() => _isSyncing = false);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/general_bg.png', fit: BoxFit.fill),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Power Boosts label
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8657F3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'Power Boosts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isOffline)
                  Container(
                    width: double.infinity,
                    color: Colors.redAccent,
                    padding: const EdgeInsets.all(8),
                    child: const Text(
                      "You're offline. CBT completions will sync when online.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                if (_isSyncing)
                  Container(
                    width: double.infinity,
                    color: Colors.blueAccent,
                    padding: const EdgeInsets.all(6),
                    child: const Text(
                      "Syncing CBT data...",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                // ------------------- REAL-TIME CBT LIST -------------------
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Consumer<CBTProvider>(
                          builder: (_, cbtProvider, __) {
                            // Filter only current week's CBTs for this child
                            final currentWeekAssignments = cbtProvider
                                .getCurrentWeekAssignments()
                                .where((a) => a.childId == widget.childId)
                                .toList();

                            if (currentWeekAssignments.isEmpty) {
                              return const Center(
                                child: Text(
                                  "No CBT exercises assigned this week.",
                                ),
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: RefreshIndicator(
                                onRefresh: _loadCBT,
                                child: ListView.builder(
                                  itemCount: currentWeekAssignments.length,
                                  itemBuilder: (_, index) {
                                    final assigned =
                                        currentWeekAssignments[index];
                                    final exercise = CBTLibrary.getById(
                                      assigned.exerciseId,
                                    );

                                    if (exercise == null)
                                      return const SizedBox.shrink();

                                    final isCompleted = cbtProvider.isCompleted(
                                      widget.childId,
                                      exercise.id,
                                    );

                                    return CBTCard(
                                      exercise: exercise,
                                      isParentView: false,
                                      isCompleted: isCompleted,
                                      onStart: () async {
                                        final assignedEntry = cbtProvider
                                            .assigned
                                            .firstWhereOrNull(
                                              (a) =>
                                                  a.exerciseId == exercise.id &&
                                                  a.childId == widget.childId,
                                            );
                                        if (assignedEntry == null) return;

                                        if (!cbtProvider.canExecute(
                                          assignedEntry,
                                        )) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'You already completed this CBT for now.',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        if (!mounted) return;
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
                                      },
                                      onComplete: () async {
                                        final assignedEntry = cbtProvider
                                            .assigned
                                            .firstWhereOrNull(
                                              (a) =>
                                                  a.exerciseId == exercise.id &&
                                                  a.childId == widget.childId,
                                            );
                                        if (assignedEntry == null) return;

                                        final success = await cbtProvider
                                            .markAsCompleted(
                                              widget.parentId,
                                              widget.childId,
                                              assignedEntry.id,
                                            );

                                        if (!mounted) return;
                                        if (!success) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cannot complete again within recurrence window.',
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Well done! Exercise completed.',
                                              ),
                                            ),
                                          );

                                          await _checkConnectivity();
                                          if (!_isOffline) {
                                            if (!mounted) return;
                                            setState(() => _isSyncing = true);
                                            await cbtProvider
                                                .syncPendingCompletions(
                                                  widget.childId,
                                                );
                                            if (!mounted) return;
                                            setState(() => _isSyncing = false);
                                          }
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
