import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/models/task_model.dart';
import '/data/models/journal_model.dart'; // ✅ This is JournalEntry
import '/data/repositories/user_repository.dart';
import '/providers/auth_provider.dart';

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

  // Stats
  Map<String, int> taskStats = {"done": 0, "not_done": 0};

  Map<String, int> moodStats = {};

  Future<void> _loadData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final model = auth.currentUserModel;
    if (model == null || model is! ParentUser) return;

    setState(() => _loading = true);

    final parent = await _userRepo.fetchParentAndCache(model.uid);
    _accessCode = parent?.accessCode;

    final children = await _userRepo.fetchChildrenAndCache(model.uid);
    _children = children;

    if (_children.isNotEmpty) {
      await _fetchTaskStats();
      await _fetchJournalStats();
    } else {
      setState(() {
        taskStats = {"done": 0, "not_done": 0};
        moodStats = {};
      });
    }

    setState(() => _loading = false);
  }

  Future<void> _fetchTaskStats() async {
    final snapshot = await FirebaseFirestore.instance.collection('tasks').get();

    final data = {"done": 0, "not_done": 0};
    for (var doc in snapshot.docs) {
      try {
        final task = TaskModel.fromFirestore(doc.data(), doc.id);
        if (_children.any((c) => c.cid == task.childId)) {
          if (task.isDone) {
            data["done"] = data["done"]! + 1;
          } else {
            data["not_done"] = data["not_done"]! + 1;
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Task parse error ${doc.id}: $e');
      }
    }
    setState(() => taskStats = data);
  }

  Future<void> _fetchJournalStats() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('journals')
        .get();

    final data = <String, int>{};
    for (var doc in snapshot.docs) {
      try {
        final journal = JournalEntry.fromMap(doc.data()); // ✅ Use JournalEntry
        if (_children.any((c) => c.cid == journal.cid)) {
          final mood = (journal.mood).toLowerCase();
          data[mood] = (data[mood] ?? 0) + 1;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Journal parse error ${doc.id}: $e');
      }
    }
    setState(() => moodStats = data);
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
      return const Scaffold(
        body: Center(child: Text('Not logged in as parent.')),
      );
    }

    final parent = current;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 👋 Welcome Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      "Welcome Back, ${parent.name}!",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 👦 Children List
                  const Text(
                    'Children & Access Codes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _children.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No children yet. Tap + to add one.'),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _children.length,
                          itemBuilder: (ctx, i) {
                            final child = _children[i];
                            final code =
                                parent.childrenAccessCodes?[child.cid] ?? "—";

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                title: Text(child.name),
                                subtitle: Text(
                                  'Balance: ${child.balance} • Streak: ${child.streak}\nAccess Code: $code',
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Copied $code to clipboard',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                  const SizedBox(height: 16),

                  // 📊 Graphs Row (Tasks + Journals)
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              height: 160,
                              child: PieChart(
                                PieChartData(
                                  sections: taskStats.entries
                                      .map(
                                        (e) => PieChartSectionData(
                                          value: e.value.toDouble(),
                                          title: "${e.key}\n${e.value}",
                                          color: _taskColor(e.key),
                                        ),
                                      )
                                      .toList(),
                                  centerSpaceRadius: 30,
                                  sectionsSpace: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              height: 160,
                              child: BarChart(
                                BarChartData(
                                  titlesData: FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  barGroups: moodStats.entries
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                        final idx = entry.key;
                                        final kv = entry.value;
                                        return BarChartGroupData(
                                          x: idx,
                                          barRods: [
                                            BarChartRodData(
                                              toY: kv.value.toDouble(),
                                              color: Colors.deepPurple,
                                            ),
                                          ],
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 😀 Mood Suggestion
                  if (moodStats.isNotEmpty)
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Text(
                              "Most common mood: ${_topMood()}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () {},
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text("Assign Power Boost"),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Color _taskColor(String status) {
    switch (status) {
      case "done":
        return Colors.green;
      case "not_done":
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _topMood() {
    if (moodStats.isEmpty) return "None";
    return moodStats.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}
