// ignore_for_file: use_build_context_synchronously

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
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    final cbtProvider = context.read<CBTProvider>();
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

    // Load offline first
    await cbtProvider.loadLocalCBT(widget.childId);

    // Check connectivity
    await _checkConnectivity();

    // If online, sync and fetch remote
    if (!_isOffline) {
      if (!mounted) return;
      setState(() => _isSyncing = true);

      await cbtProvider.loadRemoteCBT(widget.parentId, widget.childId);
      await cbtProvider.syncPendingCompletions(widget.parentId, widget.childId);

      if (!mounted) return;
      setState(() => _isSyncing = false);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _openExercise(exercise, String assignmentId) async {
    if (_isNavigating) return;
    _isNavigating = true;

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

    // Reset start session confirmation
    await context.read<CBTProvider>().resetStartSession(
      widget.parentId,
      widget.childId,
      assignmentId,
    );

    _isNavigating = false;
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();

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

                // Header
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

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Builder(
                          builder: (_) {
                            // Only show approved exercises
                            final assignments = cbtProvider
                                .getCurrentWeekAssignments()
                                .where(
                                  (a) =>
                                      a.childId == widget.childId &&
                                      (a.isApproved ?? false),
                                )
                                .toList();

                            if (assignments.isEmpty) {
                              return const Center(
                                child: Text(
                                  "No approved CBT exercises assigned this week.",
                                ),
                              );
                            }

                            return RefreshIndicator(
                              onRefresh: _loadCBT,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: assignments.length,
                                itemBuilder: (_, index) {
                                  final assigned = assignments[index];
                                  final exercise = CBTLibrary.getById(
                                    assigned.exerciseId,
                                  );

                                  final isCompleted = cbtProvider.isCompleted(
                                          widget.childId,
                                          exercise.id,
                                        );

                                  // 🔹 Auto-start exercise if already confirmed
                                  final confirmed =
                                      assigned.isConfirmed ?? false;
                                  if (confirmed &&
                                      !_isNavigating &&
                                      exercise != null) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) async {
                                          if (!mounted) return;
                                          final stillConfirmed =
                                              assigned.isConfirmed ?? false;
                                          if (!stillConfirmed) return;
                                          await _openExercise(
                                            exercise,
                                            assigned.id,
                                          );
                                        });
                                  }

                                  return CBTCard(
                                    exercise: exercise,
                                    isParentView: false,
                                    isCompleted: isCompleted,

                                    onStart: () async {
                                      final approved =
                                          assigned.isApproved ?? false;
                                      final requested =
                                          assigned.isRequested ?? false;
                                      final confirmed =
                                          assigned.isConfirmed ?? false;

                                      if (!approved) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'This CBT is not yet approved by parent.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      if (!cbtProvider.canExecute(assigned)) {
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

                                      if (!requested && !confirmed) {
                                        // Request parent approval first
                                        await cbtProvider.requestStartApproval(
                                          widget.parentId,
                                          widget.childId,
                                          assigned.id,
                                        );
                                      }

                                      // At this point either requested = true, or confirmed = true
                                      if (!confirmed) {
                                        if (!mounted) return;

                                        // Show waiting modal
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => WillPopScope(
                                            onWillPop: () async => false,
                                            child: AlertDialog(
                                              content: Row(
                                                children: const [
                                                  CircularProgressIndicator(),
                                                  SizedBox(width: 16),
                                                  Expanded(
                                                    child: Text(
                                                      'Waiting for parent to start the exercise...',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );

                                        // Polling loop: check every second
                                        while (true) {
                                          await Future.delayed(
                                            const Duration(seconds: 1),
                                          );
                                          await cbtProvider.loadLocalCBT(
                                            widget.childId,
                                          );
                                          final updated = cbtProvider
                                              .getCurrentWeekAssignments()
                                              .firstWhereOrNull(
                                                (a) => a.id == assigned.id,
                                              );

                                          final isNowConfirmed =
                                              updated?.isConfirmed ?? false;
                                          final isNowRequested =
                                              updated?.isRequested ?? false;

                                          // Close modal if parent confirmed or request canceled
                                          if (!isNowRequested || isNowConfirmed)
                                            break;
                                          if (!mounted) return;
                                        }

                                        // Dismiss the waiting modal
                                        if (mounted)
                                          Navigator.of(context).pop();

                                        // If parent confirmed, open exercise
                                        if ((cbtProvider
                                                    .getCurrentWeekAssignments()
                                                    .firstWhereOrNull(
                                                      (a) =>
                                                          a.id == assigned.id,
                                                    )
                                                    ?.isConfirmed ??
                                                false) &&
                                            exercise != null) {
                                          await _openExercise(
                                            exercise,
                                            assigned.id,
                                          );
                                        }

                                        return;
                                      }

                                      // Already confirmed → short loading before opening
                                      if (confirmed) {
                                        if (!mounted) return;

                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (context) => WillPopScope(
                                            onWillPop: () async => false,
                                            child: AlertDialog(
                                              content: Row(
                                                children: const [
                                                  CircularProgressIndicator(),
                                                  SizedBox(width: 16),
                                                  Expanded(
                                                    child: Text(
                                                      'Starting exercise...',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );

                                        await Future.delayed(
                                          const Duration(milliseconds: 500),
                                        );
                                        await _openExercise(
                                          exercise,
                                          assigned.id,
                                        );

                                        if (mounted)
                                          Navigator.of(context).pop();
                                      }
                                    },

                                    onComplete: () async {
                                      final success = await cbtProvider
                                          .markAsCompleted(
                                            widget.parentId,
                                            widget.childId,
                                            assigned.id,
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
                                        return;
                                      }

                                      // Reset request/confirmation flags
                                      assigned.isRequested = false;
                                      assigned.isConfirmed = false;
                                      await cbtProvider.updateAssignedCBT(
                                        assigned,
                                      );
                                      await cbtProvider.loadLocalCBT(
                                        widget.childId,
                                      );

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
                                        setState(() => _isSyncing = true);

                                        await cbtProvider
                                            .syncPendingCompletions(
                                              widget.parentId,
                                              widget.childId,
                                            );

                                        if (!mounted) return;
                                        setState(() => _isSyncing = false);
                                      }
                                    },
                                  );
                                },
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
