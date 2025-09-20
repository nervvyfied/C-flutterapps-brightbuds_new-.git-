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
      _loading = false;
    });

    final journalProv = Provider.of<JournalProvider>(context, listen: false);
    final taskProv = Provider.of<TaskProvider>(context, listen: false);
    for (final c in children) {
      await journalProv.fetchEntries(model.uid, c.cid);
      await taskProv.loadTasks(parentId: model.uid, childId: c.cid);
    }
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

  /// Build semi-circle gauge chart sections with dynamic filler
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
    final weeklyTopMood =
        selectedChild == null ? '—' : _getWeeklyTopMood(journalProv, selectedChild.cid);

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
                                  subtitle: Text(
                                      'Balance: ${child.balance} • Streak: ${child.streak}\nAccess Code: $code'),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Copied $code to clipboard')),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: 12),

                    // SIDE-BY-SIDE CARDS
                    if (selectedChild != null)
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
                                    // FIXED: Semi-circle cropped to top half
                                 SizedBox(
                                  height: 100, // only reserve space for half
                                  child: OverflowBox(
                                    maxHeight: 200, // full circle size
                                    alignment: Alignment.topCenter,
                                    child: SizedBox(
                                      height: 200,
                                      width: 200,
                                      child: PieChart(
                                        PieChartData(
                                          sections: _buildGaugeSections(journalProv, selectedChild.cid),
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
                                        final count = _moodCountsThisWeek(journalProv, selectedChild.cid)[mood] ?? 0;
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
                                    Text("Top mood: $weeklyTopMood", style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 6),
                                    ElevatedButton(
                                      onPressed: () {},
                                      child: const Text('Assign Power Boost', style: TextStyle(fontSize: 12)),
                                    ),
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
                  ],
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
