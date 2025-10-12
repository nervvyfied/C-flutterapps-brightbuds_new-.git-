import 'dart:io';
import 'dart:ui';
import 'package:brightbuds_new/cbt/pages/parent_cbt_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParentData());
  }

  Future<void> _loadParentData() async {
    setState(() => _loading = true);

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
  }

  Future<void> exportChildDataToPdfWeb(Map<String, dynamic> childData) async {
    final pdf = pw.Document();

    final cid = childData['cid'] ?? 'Unknown';
    final name = childData['name'] ?? 'Unknown';
    final balance = childData['balance']?.toString() ?? '0';
    final streak = childData['streak']?.toString() ?? '0';
    final moodCounts = Map<String, int>.from(childData['moodCounts'] ?? {});
    final done = childData['done']?.toString() ?? '0';
    final notDone = childData['notDone']?.toString() ?? '0';

    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Child ID: $cid",
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text("Child Name: $name"),
              pw.Text("Balance: $balance"),
              pw.Text("Streak: $streak"),
              pw.SizedBox(height: 20),
              pw.Text("Mood Counts This Week:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ...moodCounts.entries.map((e) => pw.Text("${e.key}: ${e.value}")),
              pw.SizedBox(height: 20),
              pw.Text("Task Status:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
    'scared'
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

  Map<String, int> _moodCountsThisWeek(JournalProvider journalProv, String childId) {
    final entries = journalProv.getEntries(childId);
    final now = DateTime.now();
    final startOfWeek =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final counts = {for (var m in _moodOrder) m: 0};

    for (final e in entries) {
      final d = e.createdAt;
      if (!d.isBefore(startOfWeek) && !d.isAfter(startOfWeek.add(const Duration(days: 6)))) {
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

  List<PieChartSectionData> _buildGaugeSections(JournalProvider journalProv, String childId) {
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

    sections.add(PieChartSectionData(
      value: total.toDouble(),
      color: Colors.transparent,
      radius: 50,
      showTitle: false,
    ));

    return sections;
  }

  List<Widget> _buildChildCharts(JournalProvider journalProv,
      TaskProvider taskProv, Map<String, dynamic> activeChild, SelectedChildProvider selectedChildProv) {
    final childTasks =
        taskProv.tasks.where((t) => t.childId == activeChild['cid']).toList();
    final done = childTasks.where((t) => t.isDone).length;
    final notDone = childTasks.where((t) => !t.isDone).length;
    final weeklyTopMood = _getWeeklyTopMood(journalProv, activeChild['cid']);

    return [
      const SizedBox(height: 12),
      // Child ID Card
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        child: ListTile(
          title: const Text('Child ID'),
          subtitle: Text(activeChild['cid'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          trailing: IconButton(
            icon: const Icon(Icons.download),
            tooltip: "Export to PDF",
            onPressed: () {
              final journalProv = Provider.of<JournalProvider>(context, listen: false);
              final taskProv = Provider.of<TaskProvider>(context, listen: false);

              final moodCounts = <String, int>{};
              final childId = activeChild['cid'] ?? '';
              if (childId.isNotEmpty) {
                final entries = journalProv.getEntries(childId);
                final now = DateTime.now();
                final startOfWeek = DateTime(now.year, now.month, now.day)
                    .subtract(Duration(days: now.weekday - 1));

                for (var mood in _moodOrder) {
                  moodCounts[mood] = 0;
                }

                for (final e in entries) {
                  final d = e.createdAt;
                  if (!d.isBefore(startOfWeek) && !d.isAfter(startOfWeek.add(Duration(days: 6)))) {
                    final key = e.mood.toLowerCase();
                    if (moodCounts.containsKey(key)) moodCounts[key] = moodCounts[key]! + 1;
                  }
                }
              }

              final childTasks = taskProv.tasks.where((t) => t.childId == childId).toList();
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
      // Mood & Task Charts
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                                sections: _buildGaugeSections(journalProv, activeChild['cid']),
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
                            _moodCountsThisWeek(journalProv, activeChild['cid'])[mood] ?? 0;
                        return Column(
                          children: [
                            Text(_moodEmojis[mood] ?? '•',
                                style: const TextStyle(fontSize: 14)),
                            Container(
                              width: 12,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _moodColors[mood],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text('$count',
                                style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
                            const SnackBar(content: Text('No active child selected!')),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ParentCBTPage(
                              parentId: parentId,
                              childId: childId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bolt, size: 16),
                      label: const Text(
                        "Assign Power Boost",
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 3,
              margin: const EdgeInsets.only(left: 6),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 120,
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
                                radius: 30,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: done.toDouble(),
                                color: Colors.deepPurpleAccent,
                                radius: 30,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('$notDone Not Done', style: const TextStyle(fontSize: 12)),
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

    if (_loading) return const Center(child: CircularProgressIndicator());

    final activeChild = selectedChildProv.selectedChild ?? {
      "cid": "",
      "name": "No Child",
      "balance": 0,
      "streak": 0,
      "parentUid": widget.parentId,
    };

    final parentName = _parent?.name ?? "Parent";
    final parentEmail = _parent?.email ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: _loadParentData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Parent Info Card
              Card(
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle, size: 40, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Hello Parent, $parentName!",
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(parentEmail,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Child Charts
              Text('Dashboard for ${activeChild['name']}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              ..._buildChildCharts(journalProv, taskProv, activeChild, selectedChildProv),
            ],
          ),
        ),
      ),
    );
  }
}
