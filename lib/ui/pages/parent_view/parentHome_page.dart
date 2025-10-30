// ignore_for_file: file_names, unused_field, unused_element, use_build_context_synchronously, deprecated_member_use

import 'package:brightbuds_new/cbt/catalogs/cbt_catalog.dart';
import 'package:brightbuds_new/cbt/pages/parent_cbt_page.dart';
import 'package:brightbuds_new/cbt/providers/cbt_provider.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentAccount_page.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '/data/models/parent_model.dart';
import '/data/repositories/user_repository.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/journal_provider.dart';
import '../../../data/providers/task_provider.dart';
import '../../../data/providers/selected_child_provider.dart';

class ParentDashboardPage extends StatefulWidget {
  final String parentId;

  const ParentDashboardPage({super.key, required this.parentId});

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  final UserRepository _userRepo = UserRepository();
  ParentUser? _parent;
  bool _loading = true;
  final GlobalKey _childChartKey = GlobalKey();
  final GlobalKey _taskChartKey = GlobalKey();
  final Set<String> _notifiedTaskIds = {};

  DateTime _startOfWeek() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
  }

  DateTime _endOfWeek() {
    return _startOfWeek().add(const Duration(days: 6));
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadParentData();

      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      // Listen to child changes once
      selectedChildProv.addListener(() {
        _listenToJournalEntries();
        _updateCBTListenerForSelectedChild();
      });
    });
  }

  @override
  void dispose() {
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    selectedChildProv.removeListener(_listenToJournalEntries);

    final cbtProv = Provider.of<CBTProvider>(context, listen: false);
    cbtProv.clear(); // 🧹 optional: clears cache/listeners

    super.dispose();
  }

  void _updateCBTListenerForSelectedChild() async {
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    final cbtProv = Provider.of<CBTProvider>(context, listen: false);

    final child = selectedChildProv.selectedChild;
    if (child == null || child['cid'] == null || child['cid'].isEmpty) return;

    final parentId = _parent?.uid ?? widget.parentId;
    final childId = child['cid'];

    // Initialize Hive if not yet
    await cbtProv.initHive();

    // Load and sync CBTs
    await cbtProv.loadLocalCBT(childId);
    await cbtProv.loadRemoteCBT(parentId, childId);

    // Start listening for real-time Firestore updates
    cbtProv.updateRealtimeListenerForChild(parentId, childId);
  }

  Future<void> _loadParentData() async {
    setState(() => _loading = true);

    _notifiedTaskIds.clear();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final parentModel = auth.currentUserModel;
    if (parentModel == null || parentModel is! ParentUser) {
      setState(() => _loading = false);
      return;
    }

    final parent = await _userRepo.fetchParentAndCache(parentModel.uid);

    setState(() {
      _parent = parent;
      _loading = false;
    });

    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    // Load CBTs for currently selected child
    _updateCBTListenerForSelectedChild();

    // Listen for child changes
    selectedChildProv.addListener(() {
      _updateCBTListenerForSelectedChild();
      _listenToJournalEntries();
    });

    // Start listening to journals for current child
    _listenToJournalEntries();
  }

  void _listenToJournalEntries() {
    final journalProv = Provider.of<JournalProvider>(context, listen: false);
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    final child = selectedChildProv.selectedChild;
    if (child == null || child['cid'] == null || child['cid'].isEmpty) return;

    final parentId = _parent?.uid ?? widget.parentId;
    final childId = child['cid'];

    if (parentId.isEmpty || childId.isEmpty) return;

    // 🔁 Attach Firestore listener for this child's journal entries
    journalProv.loadEntries(parentId: parentId, childId: childId);
  }

  // ---------------- Task Completion Notification ----------------
  void _showTaskCompletionSnackBar({
    required String childName,
    required String taskId, // pass the task id
    required String taskName,
  }) {
    // If already notified, do nothing
    if (_notifiedTaskIds.contains(taskId)) return;

    final snackBar = SnackBar(
      content: Text('$childName has completed "$taskName" ✅'),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.deepPurpleAccent,
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: Colors.white,
        onPressed: () {
          // Mark as notified if user dismisses
          _notifiedTaskIds.add(taskId);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);

    // Automatically mark as notified so it won't show again after auto-dismiss
    _notifiedTaskIds.add(taskId);
  }

  Future<void> exportChildDataToPdfWeb(Map<String, dynamic> childData) async {
    final pdf = pw.Document();

    final name = childData['name'] ?? 'Unknown';
    final balance = childData['balance']?.toString() ?? '0';
    final moodCounts = Map<String, int>.from(childData['moodCounts'] ?? {});
    final done = childData['done']?.toString() ?? '0';
    final notDone = childData['notDone']?.toString() ?? '0';

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "$name's Report",
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text("Child Name: $name"),
              pw.Text("Balance: $balance"),
              pw.SizedBox(height: 20),
              pw.Text(
                "Mood Counts This Week:",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              ...moodCounts.entries.map((e) => pw.Text("${e.key}: ${e.value}")),
              pw.SizedBox(height: 20),
              pw.Text(
                "Task Status:",
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text("Done: $done"),
              pw.Text("Not Done: $notDone"),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: "child_$name.pdf",
    );
  }

  static const List<String> _moodOrder = [
    'calm',
    'sad',
    'happy',
    'angry',
    'confused',
    'scared',
  ];
  static const Map<String, Color> _moodColors = {
    'calm': Color(0xFF6FA8DC),
    'sad': Color(0xFF4A6FB1),
    'happy': Color(0xFF6CC24A),
    'angry': Color(0xFFE04F4F),
    'confused': Color(0xFFF6A623),
    'scared': Color(0xFF9B59B6),
  };
  static const Map<String, String> _moodEmojis = {
    'calm': '😌',
    'sad': '😢',
    'happy': '😄',
    'angry': '😡',
    'confused': '😕',
    'scared': '😨',
  };
  static const Map<String, Color> _taskColor = {
    'done': Colors.deepPurpleAccent,
    'notDone': Colors.yellow,
  };
  Map<String, int> _moodCountsThisWeek(
    JournalProvider journalProv,
    String childId,
  ) {
    final entries = journalProv.getEntries(childId);
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final counts = {for (var m in _moodOrder) m: 0};

    for (final e in entries) {
      final d = e.createdAt;
      if (!d.isBefore(startOfWeek) &&
          !d.isAfter(startOfWeek.add(const Duration(days: 6)))) {
        final moodKey = e.mood.toLowerCase();
        if (counts.containsKey(moodKey)) counts[moodKey] = counts[moodKey]! + 1;
      }
    }
    return counts;
  }

  String _getWeeklyTopMood(JournalProvider journalProv, String childId) {
    final counts = _moodCountsThisWeek(journalProv, childId);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return '—';
    final sorted = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  List<PieChartSectionData> _buildGaugeSections(
    JournalProvider journalProv,
    String childId,
  ) {
    final counts = _moodCountsThisWeek(journalProv, childId);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return [];

    final sections = counts.entries.where((e) => e.value > 0).map((e) {
      return PieChartSectionData(
        value: e.value.toDouble(),
        color: _moodColors[e.key]!,
        radius: 50,
        showTitle: false,
      );
    }).toList();

    sections.add(
      PieChartSectionData(
        value: total.toDouble(),
        color: Colors.transparent,
        radius: 50,
        showTitle: false,
      ),
    );

    return sections;
  }

  List<Widget> _buildChildCharts(
    JournalProvider journalProv,
    TaskProvider taskProv,
    Map<String, dynamic> activeChild,
    SelectedChildProvider selectedChildProv,
  ) {
    final childTasks = taskProv.tasks
        .where((t) => t.childId == activeChild['cid'])
        .toList();
    final done = childTasks.where((t) => t.isDone).length;
    final notDone = childTasks.where((t) => !t.isDone).length;
    final weeklyTopMood = _getWeeklyTopMood(journalProv, activeChild['cid']);

    // ✅ Show SnackBar once per completed task
    for (var task in childTasks) {
      if (task.isDone && !task.verified == true) {
        Future.microtask(() {
          _showTaskCompletionSnackBar(
            childName: activeChild['name'] ?? 'Child',
            taskId: task.id, // pass task id
            taskName: task.name,
          );
        });
      }
    }

    return [
      const SizedBox(height: 10),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFFA6C26F),
        elevation: 3,
        child: ListTile(
          title: Text(
            "${activeChild['name']}'s Report",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            tooltip: "Export to PDF",
            onPressed: () {
              final journalProv = Provider.of<JournalProvider>(
                context,
                listen: false,
              );
              final taskProv = Provider.of<TaskProvider>(
                context,
                listen: false,
              );

              final moodCounts = <String, int>{};
              final childId = activeChild['cid'] ?? '';
              if (childId.isNotEmpty) {
                final entries = journalProv.getEntries(childId);
                final now = DateTime.now();
                final startOfWeek = DateTime(
                  now.year,
                  now.month,
                  now.day,
                ).subtract(Duration(days: now.weekday - 1));

                for (var mood in _moodOrder) {
                  moodCounts[mood] = 0;
                }

                for (final e in entries) {
                  final d = e.createdAt;
                  if (!d.isBefore(startOfWeek) &&
                      !d.isAfter(startOfWeek.add(Duration(days: 6)))) {
                    final key = e.mood.toLowerCase();
                    if (moodCounts.containsKey(key)) {
                      moodCounts[key] = moodCounts[key]! + 1;
                    }
                  }
                }
              }

              final childTasks = taskProv.tasks
                  .where((t) => t.childId == childId)
                  .toList();
              final done = childTasks.where((t) => t.isDone).length;
              final notDone = childTasks.where((t) => !t.isDone).length;

              final fullChildData = {
                ...activeChild,
                'moodCounts': moodCounts,
                'done': done,
                'notDone': notDone,
              };

              exportChildDataToPdfWeb(fullChildData);
            },
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
              margin: const EdgeInsets.only(right: 6),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 100,
                      child: OverflowBox(
                        maxHeight: 200,
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          key: _childChartKey,
                          child: SizedBox(
                            height: 200,
                            width: 200,
                            child: PieChart(
                              PieChartData(
                                sections: _buildGaugeSections(
                                  journalProv,
                                  activeChild['cid'],
                                ),
                                centerSpaceRadius: 20,
                                startDegreeOffset: 180,
                                sectionsSpace: 2,
                                borderData: FlBorderData(show: false),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _moodOrder.map((mood) {
                        final count =
                            _moodCountsThisWeek(
                              journalProv,
                              activeChild['cid'],
                            )[mood] ??
                            0;
                        return Column(
                          children: [
                            Text(
                              _moodEmojis[mood] ?? '•',
                              style: const TextStyle(fontSize: 14),
                            ),
                            Container(
                              width: 12,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _moodColors[mood],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "This week's top mood is: $weeklyTopMood, assign a Power Boost?",
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    ElevatedButton.icon(
                      onPressed: () {
                        final parentId = widget.parentId;
                        final childId = activeChild['cid'];

                        if (childId == null || childId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('No active child selected!'),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ParentCBTPage(
                              parentId: parentId,
                              childId: childId,
                              suggestedMood: weeklyTopMood,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: const Text(
                        "Assign Power Boost",
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFECE00),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 3,
              margin: const EdgeInsets.only(left: 6),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 200,
                      child: Center(
                        child: PieChart(
                          PieChartData(
                            startDegreeOffset: -90,
                            sectionsSpace: 2,
                            centerSpaceRadius: 20,
                            sections: [
                              PieChartSectionData(
                                value: notDone.toDouble(),
                                color: Colors.yellow,
                                radius: 50,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: done.toDouble(),
                                color: Colors.deepPurpleAccent,
                                radius: 50,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$notDone Not Done',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text('$done Done', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final journalProv = Provider.of<JournalProvider>(context);
    final taskProv = Provider.of<TaskProvider>(context);
    final selectedChildProv = Provider.of<SelectedChildProvider>(context);
    final cbtProv = Provider.of<CBTProvider>(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Ensure selected child is not null
    final activeChild =
        selectedChildProv.selectedChild ??
        {
          "cid": "",
          "name": "No Child",
          "balance": 0,
          "parentUid": widget.parentId,
        };

    final parentName = _parent?.name ?? "Parent";
    final parentEmail = _parent?.email ?? "";

    // Get assigned CBT exercises for the selected child
    final childId = activeChild['cid'] ?? '';
    final assignedCBT = childId.isNotEmpty
        ? cbtProv.getCurrentWeekAssignments(childId: childId)
        : [];

    return Scaffold(
      backgroundColor: const Color(0xFF8657F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF8657F3),
        elevation: 0,
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: ParentAccountSidebar(parentId: widget.parentId),
      body: RefreshIndicator(
        onRefresh: _loadParentData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- Greeting Area ----------------
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Text(
                      parentName.isNotEmpty ? parentName[0].toUpperCase() : 'P',
                      style: const TextStyle(
                        color: Color(0xFF8657F3),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome Back, $parentName!",
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          parentEmail,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ---------------- Dashboard Container ----------------
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ---------------- Child Charts ----------------
                    ..._buildChildCharts(
                      journalProv,
                      taskProv,
                      activeChild,
                      selectedChildProv,
                    ),

                    // ---------------- Scrollable CBT Exercises ----------------
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Assigned CBT Exercises",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurpleAccent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            assignedCBT.isEmpty
                                ? const Text(
                                    "No CBT exercises assigned this week.",
                                    style: TextStyle(color: Colors.black),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: assignedCBT.length,
                                    itemBuilder: (context, index) {
                                      final assigned = assignedCBT[index];

                                      // Look up the full exercise by ID
                                      final exercise = CBTLibrary.getById(
                                        assigned.exerciseId,
                                      );

                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          exercise.title,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: assigned.completed
                                            ? const Text(
                                                "Completed ✅",
                                                style: TextStyle(
                                                  color: Colors.greenAccent,
                                                ),
                                              )
                                            : const Text(
                                                "Pending ⏳",
                                                style: TextStyle(
                                                  color: Colors.orangeAccent,
                                                ),
                                              ),
                                        trailing: Icon(
                                          assigned.completed
                                              ? Icons.check_circle
                                              : Icons.pending,
                                          color: assigned.completed
                                              ? Colors.greenAccent
                                              : Colors.orangeAccent,
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
