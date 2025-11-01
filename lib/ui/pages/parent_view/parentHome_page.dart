// ignore_for_file: file_names, unused_field, unused_element, use_build_context_synchronously, deprecated_member_use
import 'package:intl/intl.dart';
import 'package:brightbuds_new/cbt/catalogs/cbt_catalog.dart';
import 'package:brightbuds_new/cbt/pages/parent_cbt_page.dart';
import 'package:brightbuds_new/cbt/providers/cbt_provider.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentAccount_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
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

extension StringCasingExtension on String {
  String capitalize() => isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  final UserRepository _userRepo = UserRepository();
  ParentUser? _parent;
  bool _loading = true;
  final GlobalKey _childChartKey = GlobalKey();
  final GlobalKey _taskChartKey = GlobalKey();
  final Set<String> _notifiedTaskIds = {};
  final dateFormat = DateFormat('MMM dd, yyyy');

  Map<String, TimeOfDay> routineStartTimes = {
  'morning': const TimeOfDay(hour: 5, minute: 0),
  'afternoon': const TimeOfDay(hour: 12, minute: 0),
  'evening': const TimeOfDay(hour: 17, minute: 0),
  'anytime': const TimeOfDay(hour: 0, minute: 0), // always valid
};

Map<String, TimeOfDay> routineEndTimes = {
  'morning': const TimeOfDay(hour: 11, minute: 59),
  'afternoon': const TimeOfDay(hour: 16, minute: 59),
  'evening': const TimeOfDay(hour: 20, minute: 59),
  'anytime': const TimeOfDay(hour: 23, minute: 59),
};

Map<String, int> _countTaskStatuses(List<TaskModel> tasks) {
  int done = 0;
  int notDone = 0;
  int missed = 0;

  final now = TimeOfDay.fromDateTime(DateTime.now());

  for (var task in tasks) {
  if (task.isDone) {
    done++;
  } else {
    notDone++;
    // Check if task is missed
    final routineKey = (task.routine).toLowerCase().trim(); // normalize
    final end = routineEndTimes[routineKey];
    if (end != null && routineKey != 'anytime') {
      if (_timeOfDayToDouble(now) > _timeOfDayToDouble(end)) {
        missed++;
      }
    }
  }
}


  return {'done': done, 'notDone': notDone, 'missed': missed};
}

// Helper: convert TimeOfDay to double for easy comparison
double _timeOfDayToDouble(TimeOfDay t) => t.hour + t.minute / 60.0;

void _showMoodHistoryModal(BuildContext context, String childId) {
  final journalProv = Provider.of<JournalProvider>(context, listen: false);
  final allEntries = journalProv.getEntries(childId);

  if (allEntries.isEmpty) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("No mood entries found"),
        content: const Text("Your child hasn't logged any moods yet."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return;
  }

  // Mood configuration
  final Map<String, Color> moodColors = {
    'calm': const Color(0xFFA6C26F),
    'sad': const Color(0xFF57A0F3),
    'happy': const Color(0xFFFECE00),
    'confused': const Color(0xFFFC8B34),
    'angry': const Color(0xFFFD5C68),
    'scared': const Color(0xFF8657F3),
  };

  final Map<String, String> moodIcons = {
    'calm': 'assets/moods/calm_icon.png',
    'sad': 'assets/moods/sad_icon.png',
    'happy': 'assets/moods/happy_icon.png',
    'confused': 'assets/moods/confused_icon.png',
    'angry': 'assets/moods/angry_icon.png',
    'scared': 'assets/moods/scared_icon.png',
  };

  final List<String> moodOrder = ['calm', 'sad', 'happy', 'confused', 'angry', 'scared'];

  // --- WEEKLY DATA ---
  Map<String, List> weekGroups = {};
  List<DateTime> weekStarts = [];

  for (var entry in allEntries) {
    final weekStart = entry.createdAt.subtract(Duration(days: entry.createdAt.weekday - 1));
    final key = "${weekStart.year}-${weekStart.month}-${weekStart.day}";
    if (!weekGroups.containsKey(key)) {
      weekGroups[key] = [];
      weekStarts.add(weekStart);
    }
    weekGroups[key]!.add(entry);
  }
  weekStarts.sort((a, b) => b.compareTo(a)); // latest first

  // --- MONTHLY DATA ---
  List<DateTime> monthStarts = [];
  for (var entry in allEntries) {
    final monthStart = DateTime(entry.createdAt.year, entry.createdAt.month, 1);
    if (!monthStarts.any((m) => m.year == monthStart.year && m.month == monthStart.month)) {
      monthStarts.add(monthStart);
    }
  }
  monthStarts.sort((a, b) => b.compareTo(a)); // latest first

  int currentWeekIndex = 0;
  int currentMonthIndex = 0;
  bool isMonthly = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        List entriesToDisplay;
        String label;

        if (isMonthly) {
          // --- MONTHLY VIEW ---
          final monthStart = monthStarts[currentMonthIndex];
          entriesToDisplay = allEntries
              .where((e) => e.createdAt.month == monthStart.month && e.createdAt.year == monthStart.year)
              .toList();
          label = "${monthStart.month}/${monthStart.year}";
        } else {
          // --- WEEKLY VIEW ---
          final weekStart = weekStarts[currentWeekIndex];
          final weekEnd = weekStart.add(const Duration(days: 6));
          final key = "${weekStart.year}-${weekStart.month}-${weekStart.day}";
          entriesToDisplay = weekGroups[key]!;
          label = "Week of ${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}";
        }

        // Count moods
        final counts = {for (var m in moodOrder) m: 0};
        for (var entry in entriesToDisplay) {
          final mood = entry.mood.toLowerCase();
          if (counts.containsKey(mood)) counts[mood] = counts[mood]! + 1;
        }

        final sortedMoods = counts.entries.where((e) => e.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header + navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: isMonthly
                        ? (currentMonthIndex < monthStarts.length - 1
                            ? () => setState(() => currentMonthIndex++)
                            : null)
                        : (currentWeekIndex < weekStarts.length - 1
                            ? () => setState(() => currentWeekIndex++)
                            : null),
                    icon: const Icon(Icons.arrow_back_ios),
                  ),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: isMonthly
                        ? (currentMonthIndex > 0
                            ? () => setState(() => currentMonthIndex--)
                            : null)
                        : (currentWeekIndex > 0
                            ? () => setState(() => currentWeekIndex--)
                            : null),
                    icon: const Icon(Icons.arrow_forward_ios),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Pie chart
              if (sortedMoods.isEmpty)
                const Text("No mood entries to display")
              else
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sections: sortedMoods
                          .map((e) => PieChartSectionData(
                                value: e.value.toDouble(),
                                color: moodColors[e.key]!,
                                radius: 50,
                                title: "${e.value}",
                                titleStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ))
                          .toList(),
                      centerSpaceRadius: 20,
                      sectionsSpace: 2,
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Weekly Bar chart
              if (!isMonthly)
                Expanded(
                  child: BarChart(
                    BarChartData(
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, _) {
                              const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                              if (value >= 0 && value < weekdays.length) {
                                return Text(weekdays[value.toInt()]);
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(7, (i) {
                        final day = weekStarts[currentWeekIndex].add(Duration(days: i));
                        final dayCounts = {for (var m in moodOrder) m: 0};
                        for (var entry in entriesToDisplay) {
                          if (entry.createdAt.day == day.day &&
                              entry.createdAt.month == day.month &&
                              entry.createdAt.year == day.year) {
                            final mood = entry.mood.toLowerCase();
                            if (dayCounts.containsKey(mood)) dayCounts[mood] = dayCounts[mood]! + 1;
                          }
                        }
                        final total = dayCounts.values.fold(0, (a, b) => a + b);
                        return BarChartGroupData(
                          x: i,
                          barRods: [BarChartRodData(toY: total.toDouble(), color: Colors.blueAccent, width: 16)],
                        );
                      }),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              // Mood legend with icons
              Wrap(
                spacing: 12,
                children: moodOrder.map((m) {
                  final count = counts[m] ?? 0;
                  return Chip(
                    avatar: Image.asset(moodIcons[m]!, width: 20, height: 20),
                    label: Text('$m ($count)'),
                    backgroundColor: moodColors[m]?.withOpacity(0.3),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              // Weekly/Monthly switch
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Switch(
                    value: isMonthly,
                    onChanged: (val) => setState(() => isMonthly = val),
                  ),
                  Text(isMonthly ? "Monthly View" : "Weekly View"),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

Map<String, int> _getMonthlyCounts(List entries, DateTime month) {
  final counts = {for (var m in _moodOrder) m: 0};
  for (var entry in entries) {
    if (entry.createdAt.month == month.month &&
        entry.createdAt.year == month.year) {
      final mood = entry.mood.toLowerCase();
      counts[mood] = counts[mood]! + 1;
    }
  }
  return counts;
}



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
    cbtProv.clear();

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

  Future<void> exportChildDataToPdfWithCharts(Map<String, dynamic> childData) async {
  final pdf = pw.Document();

  final name = childData['name'] ?? 'Unknown';
  final parentName = childData['parentName'] ?? '-';
  final parentEmail = childData['parentEmail'] ?? '-';
  final moodCounts = Map<String, int>.from(childData['moodCounts'] ?? {});
  final done = childData['done'] ?? 0;
  final notDone = childData['notDone'] ?? 0;
  final missed = childData['missed'] ?? 0;
  final cbtTasks = List<Map<String, dynamic>>.from(childData['cbtTasks'] ?? []);

  final totalTasks = done + notDone + missed;
  final completionRate = totalTasks > 0 ? (done / totalTasks * 100).toStringAsFixed(1) : '0';
  final missedRate = totalTasks > 0 ? (missed / totalTasks * 100).toStringAsFixed(1) : '0';
  final topMood = moodCounts.entries.isNotEmpty
      ? moodCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key.capitalize()
      : '-';
  final moodDiversity = moodCounts.entries.where((e) => e.value > 0).length;

  final now = DateTime.now();
  final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
  final endOfWeek = startOfWeek.add(Duration(days: 6));

  // Prepare daily breakdowns
  final dailyMoodCounts = <DateTime, Map<String, int>>{};
  final dailyTaskCounts = <DateTime, Map<String, int>>{};
  for (int i = 0; i < 7; i++) {
    final day = startOfWeek.add(Duration(days: i));
    dailyMoodCounts[day] = {};
    dailyTaskCounts[day] = {'done': 0, 'notDone': 0, 'missed': 0};
  }

  // Fill daily data from entries and tasks
  final entries = childData['entries'] ?? [];
  for (final e in entries) {
    final created = e['createdAt'] as DateTime;
    if (!created.isBefore(startOfWeek) && !created.isAfter(endOfWeek)) {
      final day = DateTime(created.year, created.month, created.day);
      dailyMoodCounts[day]?[e['mood'].toLowerCase()] =
          (dailyMoodCounts[day]?[e['mood'].toLowerCase()] ?? 0) + 1;
    }
  }

  final tasks = childData['tasks'] ?? [];
  for (final t in tasks) {
    final taskDate = t['date'] as DateTime;
    if (!taskDate.isBefore(startOfWeek) && !taskDate.isAfter(endOfWeek)) {
      final day = DateTime(taskDate.year, taskDate.month, taskDate.day);
      final status = t['status'];
      dailyTaskCounts[day]?[status] = (dailyTaskCounts[day]?[status] ?? 0) + 1;
    }
  }

  // Behavioral highlights
  final mostProductiveDay = dailyTaskCounts.entries
      .reduce((a, b) => a.value['done']! > b.value['done']! ? a : b)
      .key;
  final happiestDay = dailyMoodCounts.entries
      .map((e) => MapEntry(e.key, e.value['happy'] ?? 0))
      .reduce((a, b) => a.value > b.value ? a : b)
      .key;
  final missedTasksNames = tasks.where((t) => t['status'] == 'missed').map((t) => t['name']).toList();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        return [
          // Header
          pw.Text("$name's Weekly Report",
              style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text("Date Range: ${dateFormat.format(startOfWeek)} - ${dateFormat.format(endOfWeek)}"),
          pw.Divider(),

          // Basic Info
          pw.Text("Child Name: $name", style: pw.TextStyle(fontSize: 14)),
          pw.Text("Parent: $parentName ($parentEmail)", style: pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 16),

          // Summary Statistics
          pw.Text("Summary Statistics", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: "Total Tasks: $totalTasks"),
          pw.Bullet(text: "Completion Rate: $completionRate%"),
          pw.Bullet(text: "Missed Rate: $missedRate%"),
          pw.Bullet(text: "Most Frequent Mood: $topMood"),
          pw.Bullet(text: "Mood Diversity: $moodDiversity"),
          pw.SizedBox(height: 16),

          // Mood Pie Chart
          pw.Text("Mood Summary", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 180,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: moodCounts.entries.map((entry) {
                final color = PdfColors.primaries[moodCounts.keys.toList().indexOf(entry.key) % PdfColors.primaries.length];
                return pw.Row(
                  children: [
                    pw.Container(width: 12, height: 12, color: color),
                    pw.SizedBox(width: 8),
                    pw.Text('${entry.key.capitalize()}: ${entry.value}'),
                  ],
                );
              }).toList(),
            ),
          ),
          pw.SizedBox(height: 16),

          // Task Completion Chart
          pw.Text("Task Completion (Bar Chart)", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 180,
            child: pw.Chart(
              grid: pw.CartesianGrid(
                xAxis: pw.FixedAxis.fromStrings(["Done", "Not Done", "Missed"], marginStart: 8, marginEnd: 8),
                yAxis: pw.FixedAxis([0, 5, 10, 15, 20]),
              ),
              datasets: [
                pw.BarDataSet(
                  data: [
                    pw.PointChartValue(0, done.toDouble()),
                    pw.PointChartValue(1, notDone.toDouble()),
                    pw.PointChartValue(2, missed.toDouble()),
                  ],
                  color: PdfColors.deepPurple,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Daily Breakdown Table
          pw.Text("Daily Breakdown", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Table.fromTextArray(
            headers: ['Day', 'Done', 'Not Done', 'Missed', 'Top Mood'],
            data: List.generate(7, (i) {
              final day = startOfWeek.add(Duration(days: i));
              final taskData = dailyTaskCounts[day]!;
              final moodData = dailyMoodCounts[day]!;
              final topMoodDay = moodData.entries.isEmpty
                  ? '-'
                  : moodData.entries.reduce((a, b) => a.value > b.value ? a : b).key.capitalize();
              return [
                dateFormat.format(day),
                taskData['done'],
                taskData['notDone'],
                taskData['missed'],
                topMoodDay,
              ];
            }),
          ),
          pw.SizedBox(height: 16),

          // CBT Assignments
          pw.Text("CBT Assignments", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          ...cbtTasks.map((cbt) {
            final progress = cbt['completed'] / cbt['total'];
            return pw.Column(children: [
              pw.Text("${cbt['name']} (${cbt['completed']}/${cbt['total']})"),
              pw.LinearProgressIndicator(value: progress),
              pw.SizedBox(height: 8),
            ]);
          }).toList(),
          pw.SizedBox(height: 16),

          // Behavioral Highlights
          pw.Text("Behavioral Highlights", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Bullet(text: "Most productive day: ${dateFormat.format(mostProductiveDay)}"),
          pw.Bullet(text: "Day with highest positive mood: ${dateFormat.format(happiestDay)}"),
          pw.Bullet(text: "Most often missed tasks: ${missedTasksNames.join(', ')}"),

          pw.SizedBox(height: 24),
          // Footer
          pw.Center(
            child: pw.Text("Generated by BrightBuds Parent Dashboard",
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
          ),
        ];
      },
    ),
  );

  await Printing.layoutPdf(onLayout: (format) async => pdf.save(), name: "child_${name}_report.pdf");
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

  // ✅ Count done, not done, and missed using helper
  final statusCounts = _countTaskStatuses(childTasks);
  final done = statusCounts['done']!.toDouble();
  final notDone = statusCounts['notDone']!.toDouble();
  final missed = statusCounts['missed']!.toDouble();

  final notDoneWithoutMissed = notDone - missed;
  final weeklyTopMood = _getWeeklyTopMood(journalProv, activeChild['cid']);

  // ✅ Show SnackBar once per completed task
  for (var task in childTasks) {
    if (task.isDone && !task.verified == true) {
      Future.microtask(() {
        _showTaskCompletionSnackBar(
          childName: activeChild['name'] ?? 'Child',
          taskId: task.id,
          taskName: task.name,
        );
      });
    }
  }

  return [
    const SizedBox(height: 10),
    // ---------------- CHILD REPORT CARD ----------------
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

              final statusCounts = _countTaskStatuses(childTasks);

              final fullChildData = {
                ...activeChild,
                'moodCounts': moodCounts,
                'done': statusCounts['done']!,
                'notDone': statusCounts['notDone']!,
                'missed': statusCounts['missed']!, // <-- include missed here
              };

              exportChildDataToPdfWithCharts(fullChildData);
          },
        ),
      ),
    ),
    const SizedBox(height: 12),
    IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---------------- WEEKLY MOOD TREND ----------------
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
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Text(
                      "Weekly Mood Trend",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8657F3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 100,
                      child: OverflowBox(
                        maxHeight: 200,
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          key: _childChartKey,
                          child: SizedBox(
                            height: 200,
                            child: GestureDetector(
                              onTap: () => _showMoodHistoryModal(context, activeChild['cid']),
                              child: PieChart(
                                PieChartData(
                                  startDegreeOffset: 180,
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 20,
                                  sections: _buildGaugeSections(journalProv, activeChild['cid']),
                                ),
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

          // ---------------- TASKS PROGRESS ----------------
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
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const Text(
                      "Tasks Progress",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF8657F3),
                      ),
                    ),
                    const SizedBox(height: 6),
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
                                value: notDoneWithoutMissed,
                                color: Colors.yellow,
                                radius: 50,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: missed,
                                color: Colors.redAccent, // visually highlights missed
                                radius: 50,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: done,
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
                    // Task Progress Legend + Counter Column
                    Column(
                      children: [
                        _legendWithCounter(color: Colors.deepPurpleAccent, label: 'Done', count: done.toInt()),
                        const SizedBox(height: 8),
                        _legendWithCounter(color: Colors.yellow, label: 'Not Done', count: notDone.toInt()),
                        const SizedBox(height: 8),
                        _legendWithCounter(color: Colors.redAccent, label: 'Missed', count: missed.toInt()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ];
}

Widget _legendWithCounter({required Color color, required String label, required int count}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '$label: $count',
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );
}


  // Helper function for legend items
  Widget _legendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
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
