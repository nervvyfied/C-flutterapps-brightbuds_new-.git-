import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '/data/models/child_model.dart';
import '/data/models/parent_model.dart';
import '/data/repositories/user_repository.dart';
import '/providers/auth_provider.dart';
import '/providers/journal_provider.dart';
import '/providers/task_provider.dart';

class ParentDashboardPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const ParentDashboardPage({
    super.key,
    required this.parentId,
    required this.childId,
  });

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  final UserRepository _userRepo = UserRepository();
  List<ChildUser> _children = [];
  String? _accessCode;
  String? _selectedChildId;
  bool _loading = false;

  static const List<String> _moodOrder = [
    'calm', 'sad', 'happy', 'angry', 'confused', 'scared'
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

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
      if (_children.isNotEmpty) _selectedChildId = _children.first.cid;
      _loading = false;
    });

    // Fetch data for the selected child only
    if (_selectedChildId != null) {
      final journalProv = Provider.of<JournalProvider>(context, listen: false);
      final taskProv = Provider.of<TaskProvider>(context, listen: false);
      await journalProv.fetchEntries(model.uid, _selectedChildId!);
      await taskProv.loadTasks(parentId: model.uid, childId: _selectedChildId!);
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
                if (_children.isNotEmpty) _selectedChildId = _children.first.cid;
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

  Map<String, int> _moodCountsThisWeek(JournalProvider journalProv, String childId) {
    final entries = journalProv.getEntries(childId);
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
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

    // Filler ensures only the top half is visible
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

  Widget _buildChildSelector() {
    if (_children.isEmpty) {
      return const Center(child: Text('No children yet. Tap + to add one.'));
    }

    return DropdownButton<String>(
      value: _selectedChildId,
      items: _children.map((c) {
        return DropdownMenuItem(
          value: c.cid,
          child: Text(c.name),
        );
      }).toList(),
      onChanged: (value) async {
        if (value == null) return;
        setState(() {
          _selectedChildId = value;
          _loading = true;
        });

        final auth = Provider.of<AuthProvider>(context, listen: false);
        final journalProv = Provider.of<JournalProvider>(context, listen: false);
        final taskProv = Provider.of<TaskProvider>(context, listen: false);

        await journalProv.fetchEntries(auth.currentUserModel!.uid, value);
        await taskProv.loadTasks(parentId: auth.currentUserModel!.uid, childId: value);

        setState(() => _loading = false);
      },
    );
  }

  List<Widget> _buildChildCharts(String childId, JournalProvider journalProv, TaskProvider taskProv) {
    final selectedChild = _children.firstWhere((c) => c.cid == childId);
    final childTasks = taskProv.tasks.where((t) => t.childId == childId).toList();
    final done = childTasks.where((t) => t.isDone).length;
    final notDone = childTasks.where((t) => !t.isDone).length;
    final weeklyTopMood = _getWeeklyTopMood(journalProv, childId);

    return [
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MOOD CHART
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
                        child: SizedBox(
                          height: 200,
                          width: 200,
                          child: PieChart(
                            PieChartData(
                              sections: _buildGaugeSections(journalProv, childId),
                              centerSpaceRadius: 60,
                              startDegreeOffset: 180,
                              sectionsSpace: 2,
                              borderData: FlBorderData(show: false),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _moodOrder.map((mood) {
                        final count = _moodCountsThisWeek(journalProv, childId)[mood] ?? 0;
                        return Column(
                          children: [
                            Text(_moodEmojis[mood] ?? '•', style: const TextStyle(fontSize: 14)),
                            const SizedBox(),
                            Container(
                              width: 12,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _moodColors[mood],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text('$count', style: const TextStyle(fontSize: 10, color: Colors.black54)),
                          ],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    Text("This week's top mood is: $weeklyTopMood", style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

          // TASKS CHART
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
                            centerSpaceRadius: 30,
                            sections: [
                              PieChartSectionData(
                                value: notDone.toDouble(),
                                color: Colors.yellow,
                                radius: 40,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: done.toDouble(),
                                color: Colors.deepPurpleAccent,
                                radius: 40,
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
    final auth = Provider.of<AuthProvider>(context);
    final current = auth.currentUserModel;
    if (current == null || current is! ParentUser) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final parent = current;
    final journalProv = Provider.of<JournalProvider>(context);
    final taskProv = Provider.of<TaskProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Parent Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(parent.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      subtitle: Text(parent.email),
                    ),
                    const SizedBox(height: 12),
                    Text('Select Child', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    _buildChildSelector(),
                    if (_selectedChildId != null)
                      ..._buildChildCharts(_selectedChildId!, journalProv, taskProv),
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddChildDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
