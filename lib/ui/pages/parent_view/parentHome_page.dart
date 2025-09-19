import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/repositories/user_repository.dart';
import '/providers/auth_provider.dart';
import '/providers/journal_provider.dart';
import '/providers/task_provider.dart';

class ParentDashboardPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const ParentDashboardPage({
    required this.parentId,
    required this.childId,
    super.key,
  });

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  final UserRepository _userRepo = UserRepository();
  List<ChildUser> _children = [];
  String? _accessCode;
  bool _loading = false;

  // Fixed mood order + color + emoji mapping
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

  Future<void> _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final model = auth.currentUserModel;
    if (model == null || model is! ParentUser) return;

    setState(() => _loading = true);

    final parent = await _userRepo.fetchParentAndCache(model.uid);
    _accessCode = parent?.accessCode;

    final children = await _userRepo.fetchChildrenAndCache(model.uid);
    setState(() {
      _children = children;
      _loading = false;
    });

    // fetch journal entries & tasks for children into providers
    final journalProv = Provider.of<JournalProvider>(context, listen: false);
    final taskProv = Provider.of<TaskProvider>(context, listen: false);
    for (final c in children) {
      await journalProv.fetchEntries(model.uid, c.cid);
      await taskProv.loadTasks(parentId: model.uid, childId: c.cid);
    }
  }

  Future<void> _showAddChildDialog() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final parent = auth.currentUserModel as ParentUser?;
    if (parent == null) return;

    final controller = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Child'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Child name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(ctx);
              setState(() => _loading = true);

              final created = await auth.addChild(name);

              final refreshedParent = await _userRepo.fetchParentAndCache(parent.uid);
              final children = await _userRepo.fetchChildrenAndCache(parent.uid);

              setState(() {
                _children = children;
                _accessCode = refreshedParent?.accessCode;
                _loading = false;
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    created != null
                        ? "Child '${created.name}' added! Access code: ${refreshedParent?.childrenAccessCodes?[created.cid] ?? '—'}"
                        : "Child created, refresh to see it.",
                  ),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Returns mood counts for the current week (Mon - Sun inclusive) using createdAt
  Map<String, int> _moodCountsThisWeek(JournalProvider journalProv, String childId) {
    final entries = journalProv.getEntries(childId);

    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    final counts = <String, int>{
      for (var m in _moodOrder) m: 0,
    };

    for (final e in entries) {
      final d = e.createdAt;
      if (!d.isBefore(startOfWeek) && !d.isAfter(endOfWeek)) {
        final moodKey = e.mood.toLowerCase();
        if (counts.containsKey(moodKey)) {
          counts[moodKey] = counts[moodKey]! + 1;
        }
      }
    }

    return counts;
  }

  /// Build the new semi-circle mood trend chart
  Widget _buildMoodTrendChart(JournalProvider journalProv, String childId) {
    final counts = _moodCountsThisWeek(journalProv, childId);
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    if (total == 0) {
      return Column(
        children: const [
          SizedBox(height: 120),
          Text('No mood entries this week', style: TextStyle(color: Colors.black54)),
        ],
      );
    }

    final sections = <PieChartSectionData>[];
    for (final mood in _moodOrder) {
      final count = counts[mood] ?? 0;
      if (count <= 0) continue;
      sections.add(PieChartSectionData(
        value: count.toDouble(),
        color: _moodColors[mood],
        showTitle: false,
        radius: 60,
      ));
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SizedBox(
              height: 120,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 60,
                  startDegreeOffset: 180,
                  sectionsSpace: 2,
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _moodOrder.map((mood) {
                final count = counts[mood] ?? 0;
                return Column(
                  children: [
                    Text(
                      _moodEmojis[mood] ?? '•',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 20,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _moodColors[mood],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('$count', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                );
              }).toList(),
            )
          ],
        ),
      ),
    );
  }

  /// weekly top mood string
  String _getWeeklyTopMood(JournalProvider journalProv, String childId) {
    final counts = _moodCountsThisWeek(journalProv, childId);
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return '—';
    final sorted = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final current = auth.currentUserModel;
    if (current == null || current is! ParentUser) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final parent = current;
    final journalProv = Provider.of<JournalProvider>(context);
    final taskProv = Provider.of<TaskProvider>(context);

    final selectedChild = _children.isNotEmpty ? _children.first : null;

    final childTasks = selectedChild == null
        ? <dynamic>[]
        : taskProv.tasks.where((t) => t.childId == selectedChild.cid).toList();

    final done = childTasks.where((t) => t.isDone).length;
    final notDone = childTasks.where((t) => !t.isDone).length;

    final weeklyTopMood = selectedChild == null ? '—' : _getWeeklyTopMood(journalProv, selectedChild.cid);

    return Scaffold(
      appBar: AppBar(title: const Text('Parent Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Parent info
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(parent.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    subtitle: Text(parent.email),
                  ),
                  const SizedBox(height: 12),

                  // Children list
                  Text('Children', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _children.isEmpty
                      ? const Center(child: Text('No children yet. Tap + to add one.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _children.length,
                          itemBuilder: (ctx, i) {
                            final child = _children[i];
                            final parentModel = auth.currentUserModel as ParentUser;
                            final code = parentModel.childrenAccessCodes?[child.cid] ?? '—';
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                title: Text(child.name),
                                subtitle: Text('Balance: ${child.balance} • Streak: ${child.streak}\nAccess Code: $code'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Copied $code to clipboard')));
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                  const SizedBox(height: 12),

                  // Graphs for selected child
                  if (selectedChild != null) ...[
                    // Task line chart
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        height: 160,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: LineChart(
                            LineChartData(
                              gridData: FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: FlTitlesData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  isCurved: true,
                                  gradient: LinearGradient(colors: [Colors.deepPurple, Colors.deepPurpleAccent]),
                                  barWidth: 3,
                                  spots: childTasks.asMap().entries.map((entry) {
                                    return FlSpot(entry.key.toDouble(), entry.value.isDone ? 5 : 2);
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Task pie chart
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        height: 160,
                        child: Row(children: [
                          Expanded(
                            child: PieChart(
                              PieChartData(
                                sections: [
                                  PieChartSectionData(value: notDone.toDouble(), color: Colors.yellow, title: ''),
                                  PieChartSectionData(value: done.toDouble(), color: Colors.deepPurpleAccent, title: ''),
                                ],
                                centerSpaceRadius: 36,
                                sectionsSpace: 2,
                                startDegreeOffset: -90,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$notDone Not Done'),
                                  Text('$done Done'),
                                ]),
                          )
                        ]),
                      ),
                    ),

                    // Semi-circle mood trend chart
                    _buildMoodTrendChart(journalProv, selectedChild.cid),

                    // Weekly summary
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Text("This week’s most common mood is $weeklyTopMood."),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: () {}, child: const Text('Assign Power Boost')),
                        ]),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                ]),
              ),
            ),
      floatingActionButton: FloatingActionButton(
          onPressed: _showAddChildDialog, child: const Icon(Icons.add)),
    );
  }
}
