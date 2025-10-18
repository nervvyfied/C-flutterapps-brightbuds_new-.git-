import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull
import '../providers/cbt_provider.dart';
import '../widgets/cbt_card.dart';
import '../widgets/cbt_exercise_viewer.dart';
import '../catalogs/cbt_catalog.dart';
import '/ui/pages/role_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

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
  bool _isOffline = false;
  bool _isSyncing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCBT();
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  Future<void> _loadCBT() async {
    setState(() => _isLoading = true);
    final cbtProvider = context.read<CBTProvider>();

    // 1️⃣ Load local CBT first (offline-first)
    await cbtProvider.loadLocalCBT(widget.parentId, widget.childId);

    // 2️⃣ Check connectivity
    await _checkConnectivity();

    // 3️⃣ If online, sync pending completions and fetch remote
    if (!_isOffline) {
      setState(() => _isSyncing = true);
      await cbtProvider.syncPendingCompletions(widget.childId);
      await cbtProvider.loadRemoteCBT(widget.parentId, widget.childId);
      setState(() => _isSyncing = false);
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cbtProvider = context.watch<CBTProvider>();
    final currentWeekAssignments = cbtProvider.getCurrentWeekAssignments()
        .where((a) => a.childId == widget.childId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text("Hello, ${widget.childName}"),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
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
                : currentWeekAssignments.isEmpty
                    ? const Center(child: Text("No CBT exercises assigned this week."))
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: RefreshIndicator(
                          onRefresh: _loadCBT,
                          child: ListView.builder(
                            itemCount: currentWeekAssignments.length,
                            itemBuilder: (_, index) {
                              final assigned = currentWeekAssignments[index];
                              final exercise = CBTLibrary.getById(assigned.exerciseId);

                              if (exercise == null) return const SizedBox.shrink();

                              final isCompleted =
                                  cbtProvider.isCompleted(widget.childId, exercise.id);

                              return CBTCard(
                                exercise: exercise,
                                isParentView: false,
                                isCompleted: isCompleted,
                                onStart: () async {
                                  final assignedEntry = cbtProvider.assigned
                                      .firstWhereOrNull((a) =>
                                          a.exerciseId == exercise.id &&
                                          a.childId == widget.childId);

                                  if (assignedEntry == null) return;

                                  if (!cbtProvider.canExecute(assignedEntry)) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'You already completed this CBT for now.'),
                                      ),
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

                                  await _loadCBT();
                                },
                                onComplete: () async {
                                  final assignedEntry = cbtProvider.assigned
                                      .firstWhereOrNull((a) =>
                                          a.exerciseId == exercise.id &&
                                          a.childId == widget.childId);

                                  if (assignedEntry == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('This exercise is not assigned.'),
                                      ),
                                    );
                                    return;
                                  }

                                  final success = await cbtProvider
                                      .markAsCompleted(
                                          widget.parentId, widget.childId, assignedEntry.id);

                                  if (!success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Cannot complete again within recurrence window.'),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Well done! Exercise completed.'),
                                      ),
                                    );

                                    // Sync if online
                                    await _checkConnectivity();
                                    if (!_isOffline) {
                                      setState(() => _isSyncing = true);
                                      await cbtProvider.syncPendingCompletions(widget.childId);
                                      setState(() => _isSyncing = false);
                                    }

                                    await _loadCBT();
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
