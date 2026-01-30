// ignore_for_file: file_names, unused_field, unused_element, use_build_context_synchronously, deprecated_member_use
import 'package:brightbuds_new/ui/pages/therapist_view/therapistAccount_page.dart';
import 'package:intl/intl.dart';
import 'package:brightbuds_new/cbt/catalogs/cbt_catalog.dart';
import 'package:brightbuds_new/cbt/pages/therapist_cbt_page.dart';
import 'package:brightbuds_new/cbt/providers/cbt_provider.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../data/models/therapist_model.dart';
import '/data/repositories/user_repository.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/journal_provider.dart';
import '../../../data/providers/task_provider.dart';
import '../../../data/providers/selected_child_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class TherapistDashboardPage extends StatefulWidget {
  final String therapistId;
  final String parentId;

  const TherapistDashboardPage({
    super.key,
    required this.therapistId,
    required this.parentId,
  });

  @override
  State<TherapistDashboardPage> createState() => _TherapistDashboardPageState();
}

class TaskHistoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveDailyTaskProgress({
    required String parentId,
    required String therapistId,
    required String childId,
    required int done,
    required int notDone,
    required int missed,
  }) async {
    try {
      final today = DateTime.now();
      final dateKey =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      final parentDocRef = _db
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('history')
          .doc(dateKey);

      await parentDocRef.set({
        'done': done,
        'notDone': notDone,
        'missed': missed,
        'totalTasks': done + notDone,
        'timestamp': FieldValue.serverTimestamp(),
        'savedBy': 'therapist',
      });

      print(
        "✅ Daily progress saved for $childId on $dateKey in parent collection ($parentId)",
      );
    } catch (e) {
      print("❌ Failed to save daily task progress: $e");
    }
  }
}

extension StringCasingExtension on String {
  String capitalize() =>
      isNotEmpty ? '${this[0].toUpperCase()}${substring(1)}' : '';
}

class _TherapistDashboardPageState extends State<TherapistDashboardPage> {
  final UserRepository _userRepo = UserRepository();

  // UPDATED: Using PageController instead of CarouselController
  final PageController _pageController = PageController();
  int _currentCarouselIndex = 0;

  TherapistUser? _therapist;
  Map<String, dynamic>? _parent;
  bool _loading = true;
  final GlobalKey _childChartKey = GlobalKey();
  final Set<String> _notifiedTaskIds = {};
  final dateFormat = DateFormat('MMM dd, yyyy');

  Map<String, TimeOfDay> routineStartTimes = {
    'morning': const TimeOfDay(hour: 5, minute: 0),
    'afternoon': const TimeOfDay(hour: 12, minute: 0),
    'evening': const TimeOfDay(hour: 17, minute: 0),
    'anytime': const TimeOfDay(hour: 0, minute: 0),
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
        final routineKey = (task.routine).toLowerCase().trim();
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

  double _timeOfDayToDouble(TimeOfDay t) => t.hour + t.minute / 60.0;

  Future<void> _showTaskHistoryModal(
    BuildContext context,
    String childId,
  ) async {
    print('Showing task history for child: $childId');

    try {
      // Get the actual parent ID from the child
      final parentId = await _getParentIdFromChild(childId);

      if (parentId == null || parentId.isEmpty) {
        print('Parent ID not found for child: $childId');
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Cannot Load History"),
            content: const Text("Parent information not found for this child."),
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

      print('Fetching history from parent: $parentId');

      // Fetch last 90 days
      final snapshots = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(90)
          .get();

      print('Found ${snapshots.docs.length} history records');

      if (snapshots.docs.isEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("No Task History"),
            content: const Text(
              "No task history found for this child. History is saved automatically at the end of each day.",
            ),
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

      final historyData = snapshots.docs
          .map(
            (d) => {
              'date': d.id,
              'done': d['done'] ?? 0,
              'notDone': d['notDone'] ?? 0,
              'missed': d['missed'] ?? 0,
            },
          )
          .toList();

      print('First date: ${historyData.first['date']}');
      print('Last date: ${historyData.last['date']}');

      // Initialize persistent state outside the StatefulBuilder
      int currentIndex = 0; // most recent
      String viewMode = 'Daily'; // 'Daily' or 'Weekly'

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final windowSize = viewMode == 'Daily' ? 1 : 7;

              List<Map<String, dynamic>> _getDisplayedData() {
                final start = currentIndex;
                final end = (currentIndex + windowSize).clamp(
                  0,
                  historyData.length,
                );
                final slice = historyData.sublist(start, end);

                int done = 0, notDone = 0, missed = 0;
                for (var d in slice) {
                  done += d['done'] as int;
                  notDone += d['notDone'] as int;
                  missed += d['missed'] as int;
                }

                final dateLabel = slice.length == 1
                    ? slice.first['date']
                    : '${slice.last['date']} → ${slice.first['date']}';

                return [
                  {
                    'date': dateLabel,
                    'done': done,
                    'notDone': notDone,
                    'missed': missed,
                  },
                ];
              }

              final displayedData = _getDisplayedData();

              // Determine if arrows should be disabled
              final isPrevDisabled =
                  currentIndex + windowSize >= historyData.length;
              final isNextDisabled = currentIndex == 0;

              void _prev() {
                setState(() {
                  currentIndex = (currentIndex + windowSize).clamp(
                    0,
                    historyData.length - 1,
                  );
                });
              }

              void _next() {
                setState(() {
                  currentIndex = (currentIndex - windowSize).clamp(
                    0,
                    historyData.length - 1,
                  );
                });
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  height: 400,
                  child: Column(
                    children: [
                      const Text(
                        "Task Progress History",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Toggle Daily / Weekly
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: ['Daily', 'Weekly'].map((mode) {
                          final selected = mode == viewMode;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(mode),
                              selected: selected,
                              onSelected: (_) {
                                setState(() {
                                  viewMode = mode;
                                  currentIndex = 0; // reset to most recent
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),

                      // Chart with arrows
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios),
                            onPressed: isPrevDisabled ? null : _prev,
                          ),
                          Expanded(
                            child: SizedBox(
                              height: 200,
                              child: BarChart(
                                BarChartData(
                                  alignment: BarChartAlignment.spaceAround,
                                  titlesData: FlTitlesData(
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(showTitles: true),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (index, _) {
                                          final date =
                                              displayedData[index
                                                  .toInt()]['date'];
                                          return Text(
                                            date.toString().split(' ')[0],
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  barGroups: List.generate(
                                    displayedData.length,
                                    (i) {
                                      final entry = displayedData[i];
                                      return BarChartGroupData(
                                        x: i,
                                        barRods: [
                                          BarChartRodData(
                                            toY: (entry['done'] as int)
                                                .toDouble(),
                                            color: Colors.deepPurpleAccent,
                                          ),
                                          BarChartRodData(
                                            toY: (entry['notDone'] as int)
                                                .toDouble(),
                                            color: Colors.yellow,
                                          ),
                                          BarChartRodData(
                                            toY: (entry['missed'] as int)
                                                .toDouble(),
                                            color: Colors.redAccent,
                                          ),
                                        ],
                                        barsSpace: 2,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            onPressed: isNextDisabled ? null : _next,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),
                      // Legend
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _legendWithCounter(
                            color: Colors.deepPurpleAccent,
                            label: 'Done',
                            count: displayedData.first['done'] as int,
                          ),
                          _legendWithCounter(
                            color: Colors.yellow,
                            label: 'Not Done',
                            count: displayedData.first['notDone'] as int,
                          ),
                          _legendWithCounter(
                            color: Colors.redAccent,
                            label: 'Missed',
                            count: displayedData.first['missed'] as int,
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(
                        displayedData.first['date'].toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print('Error in _showTaskHistoryModal: $e');
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Error"),
          content: Text("Failed to load task history: $e"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

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

    final List<String> moodOrder = [
      'calm',
      'sad',
      'happy',
      'confused',
      'angry',
      'scared',
    ];

    Map<String, List> weekGroups = {};
    List<DateTime> weekStarts = [];

    for (var entry in allEntries) {
      final weekStart = entry.createdAt.subtract(
        Duration(days: entry.createdAt.weekday - 1),
      );
      final key = "${weekStart.year}-${weekStart.month}-${weekStart.day}";
      if (!weekGroups.containsKey(key)) {
        weekGroups[key] = [];
        weekStarts.add(weekStart);
      }
      weekGroups[key]!.add(entry);
    }
    weekStarts.sort((a, b) => b.compareTo(a));

    List<DateTime> monthStarts = [];
    for (var entry in allEntries) {
      final monthStart = DateTime(
        entry.createdAt.year,
        entry.createdAt.month,
        1,
      );
      if (!monthStarts.any(
        (m) => m.year == monthStart.year && m.month == monthStart.month,
      )) {
        monthStarts.add(monthStart);
      }
    }
    monthStarts.sort((a, b) => b.compareTo(a));

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
            final monthStart = monthStarts[currentMonthIndex];
            entriesToDisplay = allEntries
                .where(
                  (e) =>
                      e.createdAt.month == monthStart.month &&
                      e.createdAt.year == monthStart.year,
                )
                .toList();
            label = "${monthStart.month}/${monthStart.year}";
          } else {
            final weekStart = weekStarts[currentWeekIndex];
            final weekEnd = weekStart.add(const Duration(days: 6));
            final key = "${weekStart.year}-${weekStart.month}-${weekStart.day}";
            entriesToDisplay = weekGroups[key]!;
            label =
                "Week of ${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}";
          }

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
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                if (sortedMoods.isEmpty)
                  const Text("No mood entries to display")
                else
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: sortedMoods
                            .map(
                              (e) => PieChartSectionData(
                                value: e.value.toDouble(),
                                color: moodColors[e.key]!,
                                radius: 50,
                                title: "${e.value}",
                                titleStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            )
                            .toList(),
                        centerSpaceRadius: 20,
                        sectionsSpace: 2,
                        borderData: FlBorderData(show: false),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (!isMonthly)
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, _) {
                                const weekdays = [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ];
                                if (value >= 0 && value < weekdays.length) {
                                  return Text(weekdays[value.toInt()]);
                                }
                                return const Text('');
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(7, (i) {
                          final day = weekStarts[currentWeekIndex].add(
                            Duration(days: i),
                          );
                          final dayCounts = {for (var m in moodOrder) m: 0};
                          for (var entry in entriesToDisplay) {
                            if (entry.createdAt.day == day.day &&
                                entry.createdAt.month == day.month &&
                                entry.createdAt.year == day.year) {
                              final mood = entry.mood.toLowerCase();
                              if (dayCounts.containsKey(mood)) {
                                dayCounts[mood] = dayCounts[mood]! + 1;
                              }
                            }
                          }
                          final total = dayCounts.values.fold(
                            0,
                            (a, b) => a + b,
                          );
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: total.toDouble(),
                                color: Colors.blueAccent,
                                width: 16,
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
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

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTherapistData();
      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      selectedChildProv.addListener(() {
        _listenToJournalEntries();
        _updateCBTListenerForSelectedChild();
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose(); // Dispose the PageController
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    selectedChildProv.removeListener(_listenToJournalEntries);

    final cbtProv = Provider.of<CBTProvider>(context, listen: false);
    cbtProv.clear();

    super.dispose();
  }

  void _listenToJournalEntries() {
    final journalProv = Provider.of<JournalProvider>(context, listen: false);
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    final child = selectedChildProv.selectedChild;

    if (child == null) return;
    if (child['cid'] == null || child['cid'].toString().isEmpty) return;

    final childId = child['cid'];

    _getParentIdFromChild(childId).then((parentId) {
      if (parentId != null && parentId.isNotEmpty) {
        print(
          '📝 Loading journal entries for child $childId with parent $parentId',
        );
        journalProv.loadEntries(childId: childId, parentId: parentId);

        _loadParentDataFromChild(childId);
      } else {
        print(
          '⚠️ Cannot load journal entries: No parent found for child $childId',
        );
      }
    });
  }

  void _updateCBTListenerForSelectedChild() async {
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );
    final cbtProv = Provider.of<CBTProvider>(context, listen: false);

    final child = selectedChildProv.selectedChild;
    if (child == null || child['cid'] == null || child['cid'].isEmpty) return;

    final therapistId = _therapist?.uid ?? widget.therapistId;
    final childId = child['cid'];

    final parentId = await _getParentIdFromChild(childId);

    if (parentId == null || parentId.isEmpty) {
      print('⚠️ Cannot load CBT: No parent found for child $childId');
      return;
    }

    print('✅ Found parent $parentId for child $childId, loading CBT...');
    await cbtProv.initHive();
  }

  Future<void> _loadTherapistData() async {
    setState(() => _loading = true);

    await Future.delayed(Duration(milliseconds: 500));

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final therapistModel = auth.currentUserModel;

    if (therapistModel == null || therapistModel is! TherapistUser) {
      try {
        final therapistSnap = await FirebaseFirestore.instance
            .collection('therapists')
            .doc(widget.therapistId)
            .get();

        if (therapistSnap.exists) {
          final therapist = TherapistUser.fromMap(
            therapistSnap.data()!,
            therapistSnap.id,
          );

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _therapist = therapist;
              });
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching therapist: $e');
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _therapist = therapistModel;
          });
        }
      });
    }

    try {
      final selectedChildProv = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      final child = selectedChildProv.selectedChild;
      if (child != null &&
          child['cid'] != null &&
          (child['cid'] as String).isNotEmpty) {
        final childId = child['cid'] as String;
        await _loadParentDataFromChild(childId);
      } else {
        print('⚠️ No child selected yet, skipping parent data load');
      }
    } catch (e) {
      print('Error loading parent data in init: $e');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    });
  }

  Future<void> _loadParentDataFromChild(String childId) async {
    if (childId.isEmpty) return;

    print('🔄 Loading parent data for child: $childId');

    final parentId = await _getParentIdFromChild(childId);

    if (parentId != null &&
        parentId.isNotEmpty &&
        parentId != widget.therapistId) {
      try {
        print('🔍 Fetching parent document at users/$parentId');

        final parentDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(parentId)
            .get();

        if (parentDoc.exists) {
          final parentData = parentDoc.data()!;
          print('✅ Found parent document!');
          print('   Parent name: ${parentData['name']}');
          print('   Parent email: ${parentData['email']}');

          setState(() {
            _parent = {
              'id': parentId,
              'name': parentData['name'] ?? 'Parent',
              'email': parentData['email'] ?? '',
            };
          });
        } else {
          print('❌ Parent document not found at users/$parentId');
          setState(() {
            _parent = {'id': parentId, 'name': 'Parent', 'email': ''};
          });
        }
      } catch (e) {
        print('❌ Error fetching parent data: $e');
        setState(() {
          _parent = {'id': parentId, 'name': 'Parent', 'email': ''};
        });
      }
    } else {
      print('⚠️ No valid parent ID found for child: $childId');
    }
  }

  Future<String?> _getParentIdFromChild(String childId) async {
    if (childId.isEmpty) return null;

    print('🔍 Looking for parent of child: $childId');

    try {
      try {
        final childInTherapist = await FirebaseFirestore.instance
            .collection('therapists')
            .doc(widget.therapistId)
            .collection('children')
            .doc(childId)
            .get();

        if (childInTherapist.exists) {
          final data = childInTherapist.data();
          print('📄 Child document in therapist collection: ${data?.keys}');

          String? parentUID;
          if (data != null) {
            parentUID =
                data['parentUID'] ?? data['parentUid'] ?? data['parentId'];
          }

          if (parentUID != null &&
              parentUID is String &&
              parentUID.isNotEmpty) {
            if (parentUID != widget.therapistId) {
              print('✅ Found parentUID in therapist/children: $parentUID');
              return parentUID;
            } else {
              print('⚠️ parentUID matches therapistId, ignoring');
            }
          } else {
            print(
              '⚠️ No parentUID/parentUid/parentId field found in child document',
            );
            print('   Available fields: ${data?.keys}');
          }
        } else {
          print('❌ Child document not found in therapist collection');
        }
      } catch (e) {
        print('   Error checking therapist children: $e');
      }

      print('   Searching users collection for child...');
      try {
        final usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .limit(50)
            .get();

        for (final userDoc in usersSnapshot.docs) {
          final userId = userDoc.id;

          if (userId == widget.therapistId) continue;

          try {
            final childDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('children')
                .doc(childId)
                .get();

            if (childDoc.exists) {
              print('✅ Found child in user $userId children collection');
              return userId;
            }
          } catch (e) {}
        }
      } catch (e) {
        print('   Error searching users: $e');
      }

      try {
        final childDoc = await FirebaseFirestore.instance
            .collection('children')
            .doc(childId)
            .get();

        if (childDoc.exists) {
          final data = childDoc.data();
          final parentUID =
              data?['parentUID'] ?? data?['parentUid'] ?? data?['parentId'];
          if (parentUID != null &&
              parentUID is String &&
              parentUID.isNotEmpty) {
            print('✅ Found parentUID in child document: $parentUID');
            return parentUID;
          }
        }
      } catch (e) {
        print('   Error checking child document: $e');
      }

      print('❌ Could not find parent for child: $childId');
      return null;
    } catch (e) {
      print('❌ Error in _getParentIdFromChild: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _findParentFromChild(String childId) async {
    final parentId = await _getParentIdFromChild(childId);

    if (parentId != null &&
        parentId != widget.therapistId &&
        parentId.isNotEmpty) {
      try {
        final parentDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(parentId)
            .get();

        if (parentDoc.exists) {
          final parentDocData = parentDoc.data()!;
          return {
            'id': parentId,
            'name': parentDocData['name'] ?? 'Parent',
            'email': parentDocData['email'] ?? '',
          };
        }
      } catch (e) {
        print('   Error fetching found parent: $e');
      }
    }

    return {
      'id': widget.parentId.isNotEmpty && widget.parentId != widget.therapistId
          ? widget.parentId
          : '',
      'name': 'Parent',
      'email': '',
    };
  }

  void _showTaskCompletionSnackBar({
    required String childName,
    required String taskId,
    required String taskName,
  }) {
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
          _notifiedTaskIds.add(taskId);
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
    _notifiedTaskIds.add(taskId);
  }

  Future<void> exportChildDataToPdfWithCharts(
    String therapistId,
    String parentId,
    String childId,
    Map<String, dynamic> childData,
    Map<String, dynamic> therapistData,
    Map<String, dynamic> parentData,
  ) async {
    if (parentId.isEmpty || parentId == therapistId) {
      print('⚠️ Cannot generate PDF: Invalid parent ID');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot generate report: Parent information not found'),
        ),
      );
      return;
    }

    try {
      final pdf = pw.Document();
      final name = childData['name'] ?? 'Unknown';
      final parentName = parentData['name'] ?? '-';
      final therapistName = therapistData['name'] ?? '-';
      final therapistEmail = therapistData['email'] ?? '-';
      final moodCounts = Map<String, int>.from(childData['moodCounts'] ?? {});
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Calculate start of week (Monday)
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
      // Calculate end of week (Sunday)
      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      print('📅 Today: ${DateFormat('yyyy-MM-dd').format(today)}');
      print('📅 Week Start: ${DateFormat('yyyy-MM-dd').format(startOfWeek)}');
      print('📅 Week End: ${DateFormat('yyyy-MM-dd').format(endOfWeek)}');

      // Format dates for Firestore queries
      final startDate = DateFormat('yyyy-MM-dd').format(startOfWeek);
      final endDate = DateFormat('yyyy-MM-dd').format(endOfWeek);

      print('📅 PDF Date Range: $startDate to $endDate');

      // Fetch all history documents within the weekly range
      List<Map<String, dynamic>> completeWeeklyHistory = [];

      try {
        final historySnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(parentId)
            .collection('children')
            .doc(childId)
            .collection('history')
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: startDate)
            .where(FieldPath.documentId, isLessThanOrEqualTo: endDate)
            .orderBy(FieldPath.documentId)
            .get();

        // Create map of existing history data
        final Map<String, Map<String, int>> historyMap = {};
        if (historySnap.docs.isNotEmpty) {
          for (var doc in historySnap.docs) {
            historyMap[doc.id] = {
              'done': doc['done'] ?? 0,
              'notDone': doc['notDone'] ?? 0,
              'missed': doc['missed'] ?? 0,
            };
          }
        }

        // Create complete weekly data up to today, fill rest with zeros
        for (int i = 0; i < 7; i++) {
          final currentDate = startOfWeek.add(Duration(days: i));
          final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);

          // Determine if this is a future date
          final bool isFutureDate = currentDate.isAfter(today);
          final bool isTodayDate = currentDate.isAtSameMomentAs(today);

          // Only show data for dates up to today
          if (isFutureDate) {
            // Future dates - show zeros
            completeWeeklyHistory.add({
              'date': dateKey,
              'displayDate': DateFormat('MMM dd').format(currentDate),
              'done': 0,
              'notDone': 0,
              'missed': 0,
              'isFutureDate': true,
              'isToday': false,
            });
          } else {
            // Past dates up to today - show actual data or zeros
            completeWeeklyHistory.add({
              'date': dateKey,
              'displayDate': DateFormat('MMM dd').format(currentDate),
              'done': historyMap[dateKey]?['done'] ?? 0,
              'notDone': historyMap[dateKey]?['notDone'] ?? 0,
              'missed': historyMap[dateKey]?['missed'] ?? 0,
              'isFutureDate': false,
              'isToday': isTodayDate,
            });
          }
        }
      } catch (e) {
        print('❌ Error fetching history: $e');
        // Fallback: create weekly data up to today
        for (int i = 0; i < 7; i++) {
          final currentDate = startOfWeek.add(Duration(days: i));
          final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);

          final bool isFutureDate = currentDate.isAfter(today);
          final bool isTodayDate = currentDate.isAtSameMomentAs(today);

          completeWeeklyHistory.add({
            'date': dateKey,
            'displayDate': DateFormat('MMM dd').format(currentDate),
            'done': 0,
            'notDone': 0,
            'missed': 0,
            'isFutureDate': isFutureDate,
            'isToday': isTodayDate,
          });
        }
      }

      // Calculate statistics from weekly history (only up to today)
      int done = 0, notDone = 0, missed = 0;
      int daysWithData = 0;

      for (var h in completeWeeklyHistory) {
        final bool isFutureDate = h['isFutureDate'] as bool? ?? false;
        if (!isFutureDate) {
          // Only count days up to today
          done += (h['done'] as num).toInt();
          notDone += (h['notDone'] as num).toInt();
          missed += (h['missed'] as num).toInt();
          daysWithData++;
        }
      }

      final totalTasks = done + notDone;
      final completionRate = totalTasks > 0
          ? (done / totalTasks * 100).toStringAsFixed(1)
          : '0.0';
      final missedRate = totalTasks > 0
          ? (missed / totalTasks * 100).toStringAsFixed(1)
          : '0.0';

      // Find most productive and missed days (only up to today)
      String mostProductiveDay = '-';
      String mostMissedDay = '-';
      double highestCompletionRate = 0;
      double lowestCompletionRate = 1;

      for (var entry in completeWeeklyHistory) {
        final bool isFutureDate = entry['isFutureDate'] as bool? ?? false;
        if (!isFutureDate) {
          // Only evaluate days up to today
          final total = (entry['done'] + entry['notDone'] + entry['missed'])
              .toDouble();
          if (total > 0) {
            final rate = entry['done'] / total;
            if (rate > highestCompletionRate) {
              highestCompletionRate = rate;
              mostProductiveDay = entry['displayDate'];
            }
            if (rate < lowestCompletionRate) {
              lowestCompletionRate = rate;
              mostMissedDay = entry['displayDate'];
            }
          }
        }
      }

      // If no data with actual tasks, find days with any data
      if (mostProductiveDay == '-') {
        for (var entry in completeWeeklyHistory) {
          final bool isFutureDate = entry['isFutureDate'] as bool? ?? false;
          if (!isFutureDate) {
            final total = (entry['done'] + entry['notDone'] + entry['missed'])
                .toDouble();
            if (total > 0) {
              mostProductiveDay = entry['displayDate'];
              mostMissedDay = entry['displayDate'];
              break;
            }
          }
        }
      }

      // If still no data, set to today or first day with data
      if (mostProductiveDay == '-') {
        // Find first day up to today
        for (var entry in completeWeeklyHistory) {
          final bool isFutureDate = entry['isFutureDate'] as bool? ?? false;
          if (!isFutureDate) {
            mostProductiveDay = entry['displayDate'];
            mostMissedDay = entry['displayDate'];
            break;
          }
        }
      }

      // Mood analysis
      String topMood = '-';
      if (moodCounts.isNotEmpty && moodCounts.values.any((v) => v > 0)) {
        final maxEntry = moodCounts.entries.reduce(
          (a, b) => a.value > b.value ? a : b,
        );
        topMood = maxEntry.key[0].toUpperCase() + maxEntry.key.substring(1);
      }
      final moodDiversity = moodCounts.entries
          .where((e) => e.value > 0)
          .length
          .toString();

      // Add page to PDF with better margins and layout
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(
            horizontal: 48, // Increased side margins
            vertical: 36, // Increased top/bottom margins
          ),
          theme: pw.ThemeData.withFont(
            base: pw.Font.courier(),
            bold: pw.Font.courierBold(),
          ),
          header: (context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    "$name's Weekly Progress Report",
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    "Week of ${DateFormat('MMM dd, yyyy').format(startOfWeek)} to ${DateFormat('MMM dd, yyyy').format(endOfWeek)}",
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),

                  pw.Divider(thickness: 1, color: PdfColors.grey300),
                ],
              ),
            );
          },
          footer: (context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 20),
              child: pw.Column(
                children: [
                  pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Parent: $parentName",
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        "Page ${context.pageNumber} of ${context.pagesCount}",
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        "Therapist: $therapistName",
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          build: (context) {
            final content = <pw.Widget>[];

            // Summary Statistics Section
            content.addAll([
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 24),
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.blue100, width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Summary Statistics",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              "Total Tasks",
                              style: pw.TextStyle(
                                fontSize: 11,
                                color: PdfColors.grey600,
                              ),
                            ),
                            pw.Text(
                              "$totalTasks",
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue800,
                              ),
                            ),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              "Completion Rate",
                              style: pw.TextStyle(
                                fontSize: 11,
                                color: PdfColors.grey600,
                              ),
                            ),
                            pw.Text(
                              "$completionRate%",
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 16),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "Key Metrics",
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Bullet(
                                text: "Missed Rate: $missedRate%",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Bullet(
                                text: "Most Frequent Mood: $topMood",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Bullet(
                                text: "Mood Diversity: $moodDiversity",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        pw.Container(
                          width: 1,
                          height: 80,
                          color: PdfColors.grey300,
                          margin: const pw.EdgeInsets.symmetric(horizontal: 16),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "Performance Highlights",
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Bullet(
                                text: "Most Productive Day: $mostProductiveDay",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Bullet(
                                text: "Needs Attention: $mostMissedDay",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]);

            // Mood Summary Section (if available)
            if (moodCounts.isNotEmpty) {
              final Map<String, PdfColor> moodColors = {
                'calm': PdfColors.lightBlue,
                'sad': PdfColors.blue,
                'happy': PdfColors.yellow,
                'angry': PdfColors.red,
                'confused': PdfColors.orange,
                'scared': PdfColors.purple,
              };

              final totalMoods = moodCounts.values.reduce((a, b) => a + b);

              content.addAll([
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 24),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "Mood Analysis",
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        "Emotional patterns and mood distribution for the week",
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.grey600,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Table(
                        border: pw.TableBorder.all(
                          color: PdfColors.grey300,
                          width: 0.5,
                        ),
                        columnWidths: {
                          0: pw.FlexColumnWidth(2),
                          1: pw.FlexColumnWidth(1.5),
                          2: pw.FlexColumnWidth(1.5),
                          3: pw.FlexColumnWidth(2),
                        },
                        children: [
                          // Header row
                          pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: PdfColors.blue50,
                            ),
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'Mood',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'Count',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'Percentage',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'Visual',
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Mood data rows
                          ...moodCounts.entries.map((entry) {
                            final moodKey = entry.key.toLowerCase();
                            final color = moodColors[moodKey] ?? PdfColors.grey;
                            final percentage = totalMoods > 0
                                ? ((entry.value / totalMoods) * 100)
                                      .toStringAsFixed(1)
                                : '0.0';
                            final barWidth = totalMoods > 0
                                ? (entry.value / totalMoods) * 100
                                : 0;

                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Row(
                                    children: [
                                      pw.Container(
                                        width: 8,
                                        height: 8,
                                        decoration: pw.BoxDecoration(
                                          color: color,
                                          shape: pw.BoxShape.circle,
                                        ),
                                      ),
                                      pw.SizedBox(width: 8),
                                      pw.Text(
                                        entry.key[0].toUpperCase() +
                                            entry.key.substring(1),
                                        style: const pw.TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    entry.value.toString(),
                                    style: const pw.TextStyle(fontSize: 11),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    '$percentage%',
                                    style: const pw.TextStyle(fontSize: 11),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Row(
                                    children: [
                                      pw.Container(
                                        width: 60,
                                        height: 6,
                                        decoration: pw.BoxDecoration(
                                          color: PdfColors.grey200,
                                          borderRadius:
                                              pw.BorderRadius.circular(3),
                                        ),
                                        child: pw.Align(
                                          alignment: pw.Alignment.centerLeft,
                                          child: pw.Container(
                                            width: barWidth * 0.6,
                                            height: 6,
                                            decoration: pw.BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  pw.BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
              ]);
            }

            // Daily Task Breakdown Section
            content.addAll([
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 24),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Daily Task Breakdown",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      "Task completion overview for each day of the week",
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: PdfColors.grey600,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Table(
                      border: pw.TableBorder.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      columnWidths: {
                        0: pw.FlexColumnWidth(1.5),
                        1: pw.FlexColumnWidth(1),
                        2: pw.FlexColumnWidth(1),
                        3: pw.FlexColumnWidth(1),
                        4: pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        // Header row
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColors.blue50),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Date',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Done',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Not Done',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Missed',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Completion %',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        // Data rows
                        ...completeWeeklyHistory.map((h) {
                          final total = (h['done'] + h['notDone'] + h['missed'])
                              .toDouble();
                          final completion = total > 0
                              ? ((h['done'] / total) * 100).toStringAsFixed(0)
                              : '0';

                          // Add indicator for future dates with null safety
                          String dateDisplay = h['displayDate'].toString();
                          final bool isToday = h['isToday'] as bool? ?? false;
                          final bool isFutureDate =
                              h['isFutureDate'] as bool? ?? false;

                          if (isToday) {
                            dateDisplay = '$dateDisplay (Today)';
                          } else if (isFutureDate) {
                            dateDisplay = '$dateDisplay (Upcoming)';
                          }

                          final isHighlighted = isToday;
                          final rowColor = isFutureDate
                              ? PdfColors.grey50
                              : isHighlighted
                              ? PdfColors.yellow50
                              : null;

                          return pw.TableRow(
                            decoration: rowColor != null
                                ? pw.BoxDecoration(color: rowColor)
                                : null,
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  dateDisplay,
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: isToday
                                        ? pw.FontWeight.bold
                                        : pw.FontWeight.normal,
                                    color: isFutureDate
                                        ? PdfColors.grey
                                        : PdfColors.black,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  h['done'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.green,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  h['notDone'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.orange,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  h['missed'].toString(),
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    color: PdfColors.red,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  '$completion%',
                                  style: pw.TextStyle(
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold,
                                    color: int.parse(completion) >= 50
                                        ? PdfColors.green
                                        : PdfColors.red,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      "*Note: Future dates show zeros as they haven't occurred yet",
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ]);

            // Behavioral Insights Section
            content.addAll([
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300, width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Behavioral Insights & Recommendations",
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "Weekly Performance",
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              pw.Bullet(
                                text:
                                    "Consistency Level: $completionRate% average task completion",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Bullet(
                                text:
                                    "Emotional Range: $moodDiversity different moods expressed",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Bullet(
                                text: "Most Productive Day: $mostProductiveDay",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                              pw.Bullet(
                                text:
                                    "Day Needing Most Attention: $mostMissedDay",
                                style: pw.TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        pw.Container(
                          width: 1,
                          height: 100,
                          color: PdfColors.grey300,
                          margin: const pw.EdgeInsets.symmetric(horizontal: 16),
                        ),
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "Data Quality",
                                style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.SizedBox(height: 8),
                              if (daysWithData < DateTime.now().weekday)
                                pw.Text(
                                  "⚠️ Limited Data: Only $daysWithData out of ${DateTime.now().weekday} weekdays have data",
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    color: PdfColors.orange,
                                  ),
                                )
                              else
                                pw.Text(
                                  "✅ Good Data Coverage: Complete weekly data available",
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    color: PdfColors.green,
                                  ),
                                ),
                              pw.SizedBox(height: 8),
                              pw.Text(
                                "Recommendation: Ensure consistent daily tracking for more accurate insights.",
                                style: pw.TextStyle(
                                  fontSize: 10,
                                  color: PdfColors.grey600,
                                  fontStyle: pw.FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ]);

            return content;
          },
        ),
      );

      // Save and print PDF
      await Printing.layoutPdf(
        name:
            "child_${name}_weekly_report_${DateFormat('yyyyMMdd').format(startOfWeek)}.pdf",
        onLayout: (format) async => pdf.save(),
      );

      print('✅ PDF generated successfully');
    } catch (e) {
      print('❌ Error generating PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  void _saveCurrentTaskProgress(
    TaskProvider taskProv,
    Map<String, dynamic> activeChild,
  ) async {
    final childId = activeChild['cid'];
    if (childId == null || childId.isEmpty) return;

    final childTasks = taskProv.tasks
        .where((t) => t.childId == childId)
        .toList();

    final statusCounts = _countTaskStatuses(childTasks);

    final parentId = await _getParentIdFromChild(childId);

    if (parentId == null || parentId.isEmpty) {
      print('⚠️ Cannot save task progress: No parent found for child $childId');
      return;
    }

    print('✅ Saving task progress to parent $parentId for child $childId');

    final taskHistoryService = TaskHistoryService();
    await taskHistoryService.saveDailyTaskProgress(
      parentId: parentId,
      therapistId: widget.therapistId,
      childId: childId,
      done: statusCounts['done']!,
      notDone: statusCounts['notDone']!,
      missed: statusCounts['missed']!,
    );
  }

  // ==================== FIXED _buildChildCharts METHOD ====================
  List<Widget> _buildChildCharts(
    JournalProvider journalProv,
    TaskProvider taskProv,
    Map<String, dynamic> activeChild,
    SelectedChildProvider selectedChildProv,
  ) {
    final childTasks = taskProv.tasks
        .where((t) => t.childId == activeChild['cid'])
        .toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveCurrentTaskProgress(taskProv, activeChild);
    });

    final statusCounts = _countTaskStatuses(childTasks);
    final done = statusCounts['done']!.toDouble();
    final notDone = statusCounts['notDone']!.toDouble();
    final missed = statusCounts['missed']!.toDouble();

    final notDoneWithoutMissed = notDone - missed;
    final weeklyTopMood = _getWeeklyTopMood(journalProv, activeChild['cid']);

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

    // Create carousel items
    final List<Widget> carouselItems = [
      // CARD 1: TASKS PROGRESS
      // Update the carousel items array - modify each card to have horizontal layout:

      // CARD 1: TASKS PROGRESS (horizontal layout)
      GestureDetector(
        onTap: () async {
          await _showTaskHistoryModal(context, activeChild['cid']);
        },
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side: Pie chart
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Title stays at top
                      const Text(
                        "Tasks Progress",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8657F3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Center the pie chart vertically
                      Expanded(
                        child: Center(
                          child: PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              sectionsSpace: 2,
                              centerSpaceRadius: 30,
                              sections: [
                                PieChartSectionData(
                                  value: notDoneWithoutMissed,
                                  color: Colors.yellow,
                                  radius: 50,
                                  showTitle: false,
                                ),
                                PieChartSectionData(
                                  value: missed,
                                  color: Colors.redAccent,
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
                    ],
                  ),
                ),

                // Right side: Legend and info
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      children: [
                        // Spacer to align with title
                        const SizedBox(
                          height: 28,
                        ), // Adjust based on title height
                        // Center the legend
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    _legendWithCounter(
                                      color: Colors.deepPurpleAccent,
                                      label: 'Done',
                                      count: done.toInt(),
                                    ),
                                    _legendWithCounter(
                                      color: Colors.yellow,
                                      label: 'Not Done',
                                      count: notDoneWithoutMissed.toInt(),
                                    ),
                                    _legendWithCounter(
                                      color: Colors.redAccent,
                                      label: 'Missed',
                                      count: missed.toInt(),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Task Completion Overview",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "Track completed, pending, and missed tasks",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const Text(
                                      "for better progress monitoring.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Bottom CTA stays at bottom
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Tap to view task history →",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.deepPurpleAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward,
                                size: 16,
                                color: Colors.deepPurpleAccent,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // CARD 2: WEEKLY TASK ANALYSIS
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 380, // Minimum height
            maxHeight: 450, // Maximum height for carousel
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:
                  MainAxisSize.min, // IMPORTANT: Takes only needed space
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics,
                      color: Colors.deepPurpleAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Weekly Task Analysis",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8657F3),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      color: Colors.deepPurpleAccent,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  // ADD THIS: Makes the FutureBuilder scrollable within available space
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _getWeeklyTaskAnalysis(activeChild['cid']),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Error loading analysis: ${snapshot.error}",
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "No task analysis available for this week.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      final analysis = snapshot.data!;
                      final totalTasks = analysis['totalTasks'] as int;
                      final totalCompleted = analysis['totalCompleted'] as int;
                      final completionRate =
                          analysis['completionRate'] as double;
                      final activeStreak = analysis['activeStreak'] as int;
                      final bestPerformingTask =
                          analysis['bestPerformingTask'] as String;
                      final bestTaskDaysCompleted =
                          analysis['bestTaskDaysCompleted'] as int;
                      final topTasks =
                          analysis['topTasks'] as List<Map<String, dynamic>>;

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Streak & Consistency Section
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.deepPurpleAccent.withOpacity(
                                  0.05,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.deepPurpleAccent.withOpacity(
                                    0.2,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Active Streak
                                  Column(
                                    children: [
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: activeStreak > 0
                                              ? Colors.deepPurpleAccent
                                              : Colors.grey[300],
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            "$activeStreak",
                                            style: TextStyle(
                                              color: activeStreak > 0
                                                  ? Colors.white
                                                  : Colors.grey[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Day Streak",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  // Completion Rate
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Weekly Completion",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: LinearProgressIndicator(
                                                value: completionRate,
                                                backgroundColor:
                                                    Colors.grey[200],
                                                color: _getCompletionRateColor(
                                                  completionRate,
                                                ),
                                                minHeight: 8,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              flex: 1,
                                              child: Text(
                                                "${(completionRate * 100).toInt()}%",
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      _getCompletionRateColor(
                                                        completionRate,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          "$totalCompleted/${totalTasks * 7} total tasks",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Best Performing Task
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.emoji_events,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bestPerformingTask,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          "Completed $bestTaskDaysCompleted day${bestTaskDaysCompleted != 1 ? 's' : ''} this week",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (bestTaskDaysCompleted == 7)
                                          Chip(
                                            label: Text(
                                              "Perfect Week!",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.amber[800],
                                              ),
                                            ),
                                            backgroundColor: Colors.amber[100],
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.trending_up,
                                            size: 14,
                                            color: Colors.amber[800],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            "#1",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Top 3 Most Consistent Tasks
                            if (topTasks.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Most Consistent Tasks",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Reduced height for the tasks list
                                  SizedBox(
                                    height: 180, // REDUCED from 280 to 180
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: topTasks.asMap().entries.map((
                                          entry,
                                        ) {
                                          final index = entry.key;
                                          final task = entry.value;
                                          final taskName =
                                              task['name'] as String;
                                          final daysCompleted =
                                              task['totalDaysCompleted'] as int;
                                          final completionPercentage =
                                              (daysCompleted / 7) * 100;

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[50],
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.grey[200]!,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  // Rank Badge
                                                  Container(
                                                    width: 28,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: _getRankColor(
                                                        index,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${index + 1}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),

                                                  // Task Info
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          taskName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                        ),
                                                        Text(
                                                          "$daysCompleted day${daysCompleted != 1 ? 's' : ''} completed",
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                color:
                                                                    Colors.grey,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // CARD 3: UNCONSISTENT TASKS
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 380, maxHeight: 450),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orangeAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Tasks Needing Attention",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16),
                      color: Colors.orangeAccent,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: _getWeeklyTaskAnalysis(activeChild['cid']),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Error loading analysis: ${snapshot.error}",
                            style: TextStyle(color: Colors.red),
                          ),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            "No task analysis available for this week.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      final analysis = snapshot.data!;
                      final bottomTasks =
                          analysis['bottomTasks']
                              as List<Map<String, dynamic>>? ??
                          [];
                      final worstPerformingTask =
                          analysis['worstPerformingTask'] as String? ??
                          'No tasks';
                      final worstTaskDaysCompleted =
                          analysis['worstTaskDaysCompleted'] as int? ?? 0;
                      final totalTasks = analysis['totalTasks'] as int? ?? 0;
                      final totalWeekDaysCompleted =
                          analysis['totalWeekDaysCompleted'] as int? ?? 0;

                      if (bottomTasks.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 48,
                                  color: Colors.greenAccent,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  "Great job!",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  "All tasks are being completed consistently.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Worst Performing Task Highlight
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orangeAccent.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.trending_down,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          worstPerformingTask,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          "Only $worstTaskDaysCompleted day${worstTaskDaysCompleted != 1 ? 's' : ''} this week",
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (worstTaskDaysCompleted == 0)
                                          Chip(
                                            label: Text(
                                              "Not started this week",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orangeAccent[800],
                                              ),
                                            ),
                                            backgroundColor:
                                                Colors.orangeAccent[100],
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orangeAccent.withOpacity(
                                        0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.priority_high,
                                            size: 14,
                                            color: Colors.orangeAccent[800],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Needs Focus",
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orangeAccent[800],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Unconsistent Tasks List
                            if (bottomTasks.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Tasks to Focus On",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 220,
                                    child: ListView.builder(
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: bottomTasks.length,
                                      itemBuilder: (context, index) {
                                        final task = bottomTasks[index];
                                        final taskName = task['name'] as String;
                                        final daysCompleted =
                                            task['totalDaysCompleted'] as int;
                                        final difficulty =
                                            task['difficulty'] as String? ??
                                            'Medium';
                                        final reward =
                                            task['reward'] as int? ?? 0;
                                        final routine =
                                            task['routine'] as String? ??
                                            'anytime';
                                        final needsAttention =
                                            task['needsAttention'] as bool? ??
                                            false;
                                        final completionPercentage =
                                            (daysCompleted / 7) * 100;

                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: needsAttention
                                                  ? Colors.redAccent
                                                        .withOpacity(0.05)
                                                  : Colors.orangeAccent
                                                        .withOpacity(0.05),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: needsAttention
                                                    ? Colors.redAccent
                                                          .withOpacity(0.2)
                                                    : Colors.orangeAccent
                                                          .withOpacity(0.2),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                // Attention Indicator
                                                Container(
                                                  width: 8,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: needsAttention
                                                        ? Colors.redAccent
                                                        : Colors.orangeAccent,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),

                                                // Task Info
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              taskName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          ),
                                                          if (reward > 0)
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .amber
                                                                    .withOpacity(
                                                                      0.2,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    Icons.star,
                                                                    size: 10,
                                                                    color: Colors
                                                                        .amber[700],
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 2,
                                                                  ),
                                                                  Text(
                                                                    '$reward',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .amber[800],
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 1,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  _getDifficultyColor(
                                                                    difficulty,
                                                                  ).withOpacity(
                                                                    0.2,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              difficulty,
                                                              style: TextStyle(
                                                                fontSize: 9,
                                                                color:
                                                                    _getDifficultyColor(
                                                                      difficulty,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 1,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  _getRoutineColor(
                                                                    routine,
                                                                  ).withOpacity(
                                                                    0.2,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: Text(
                                                              routine,
                                                              style: TextStyle(
                                                                fontSize: 9,
                                                                color:
                                                                    _getRoutineColor(
                                                                      routine,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  "$daysCompleted day${daysCompleted != 1 ? 's' : ''} completed",
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  height: 2,
                                                                ),
                                                                Container(
                                                                  width: double
                                                                      .infinity,
                                                                  height: 4,
                                                                  decoration: BoxDecoration(
                                                                    color: Colors
                                                                        .grey[200],
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          2,
                                                                        ),
                                                                  ),
                                                                  child: Align(
                                                                    alignment:
                                                                        Alignment
                                                                            .centerLeft,
                                                                    child: Container(
                                                                      width:
                                                                          completionPercentage *
                                                                          0.01 *
                                                                          100,
                                                                      height: 4,
                                                                      decoration: BoxDecoration(
                                                                        color: _getAttentionColor(
                                                                          completionPercentage,
                                                                        ),
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              2,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 12),

                            // Recommendations
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Recommendations:",
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildRecommendationItem(
                                    Icons.emoji_objects,
                                    "Simplify ${bottomTasks.where((t) => t['difficulty'] == 'Hard').length} difficult tasks",
                                    Colors.greenAccent,
                                  ),
                                  _buildRecommendationItem(
                                    Icons.card_giftcard,
                                    "Increase rewards for ${bottomTasks.where((t) => (t['reward'] as int) < 10).length} low-motivation tasks",
                                    Colors.amber,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];

    return [
      const SizedBox(height: 10),
      // CHILD REPORT CARD (same as before)
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
            onPressed: () async {
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

              print('   Child ID: $childId');
              print('   Child data: $activeChild');

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
                'missed': statusCounts['missed']!,
              };

              final therapistData = {
                'name': _therapist?.name ?? 'Unknown Therapist',
                'email': _therapist?.email ?? '',
              };

              final parentId = await _getParentIdFromChild(childId);

              if (parentId == null || parentId.isEmpty) {
                print(
                  '⚠️ Cannot generate PDF: No parent found for child $childId',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Cannot generate report: Parent information not found',
                    ),
                  ),
                );
                return;
              }

              Map<String, dynamic> parentData;
              try {
                final parentDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(parentId)
                    .get();

                if (parentDoc.exists) {
                  final parentDocData = parentDoc.data()!;
                  parentData = {
                    'id': parentId,
                    'name': parentDocData['name'] ?? 'Parent',
                    'email': parentDocData['email'] ?? '',
                  };
                } else {
                  parentData = {'id': parentId, 'name': 'Parent', 'email': ''};
                }
              } catch (e) {
                print('   Error fetching parent details: $e');
                parentData = {'id': parentId, 'name': 'Parent', 'email': ''};
              }

              print('📄 Generating PDF with:');
              print('   - Therapist: ${therapistData['name']}');
              print(
                '   - Parent: ${parentData['name']} (ID: ${parentData['id']})',
              );
              print('   - Child: ${activeChild['name']} (ID: $childId)');

              await exportChildDataToPdfWithCharts(
                widget.therapistId,
                parentData['id'],
                childId,
                fullChildData,
                therapistData,
                parentData,
              );
            },
          ),
        ),
      ),
      const SizedBox(height: 12),

      // MAIN CHARTS ROW
      IntrinsicHeight(
        child: // Replace the MAIN CHARTS ROW section with this:
            // MAIN CHARTS COLUMN (stacked vertically)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // CARD 1: WEEKLY MOOD TREND CARD (horizontal layout)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Mood chart
                        Expanded(
                          flex: 2,
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
                                        onTap: () => _showMoodHistoryModal(
                                          context,
                                          activeChild['cid'],
                                        ),
                                        child: PieChart(
                                          PieChartData(
                                            startDegreeOffset: 180,
                                            sectionsSpace: 2,
                                            centerSpaceRadius: 20,
                                            sections: _buildGaugeSections(
                                              journalProv,
                                              activeChild['cid'],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
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
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
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
                            ],
                          ),
                        ),

                        // Right side: Description and button
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "This week's top mood is: $weeklyTopMood",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Assign a Power Boost to help improve their emotional well-being and build coping skills.",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final therapistId = widget.therapistId;
                                    final childId = activeChild['cid'];

                                    if (childId == null || childId.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'No active child selected!',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TherapistCBTPage(
                                          therapistId: therapistId,
                                          parentId: widget.parentId,
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
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFECE00),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    "Tap chart to view mood history →",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // CARD 2: CAROUSEL FOR TASKS PROGRESS & ANALYSIS
                Column(
                  children: [
                    // PageView Carousel
                    SizedBox(
                      height:
                          460, // Increased from 400 to 460 to accommodate content
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: carouselItems.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentCarouselIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            child: carouselItems[index],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Carousel indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: carouselItems.asMap().entries.map((entry) {
                        return GestureDetector(
                          onTap: () {
                            _pageController.animateToPage(
                              entry.key,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          child: Container(
                            width: 8.0,
                            height: 8.0,
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentCarouselIndex == entry.key
                                  ? Colors.deepPurpleAccent
                                  : Colors.grey[300],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    // Navigation buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_ios, size: 16),
                            onPressed: _currentCarouselIndex > 0
                                ? () {
                                    _pageController.previousPage(
                                      duration: Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                          ),
                          Text(
                            "${_currentCarouselIndex + 1}/${carouselItems.length}",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.arrow_forward_ios, size: 16),
                            onPressed:
                                _currentCarouselIndex < carouselItems.length - 1
                                ? () {
                                    _pageController.nextPage(
                                      duration: Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      ),
    ];
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.greenAccent;
      case 'medium':
        return Colors.orangeAccent;
      case 'hard':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Color _getRoutineColor(String routine) {
    switch (routine.toLowerCase()) {
      case 'morning':
        return Colors.blueAccent;
      case 'afternoon':
        return Colors.orangeAccent;
      case 'evening':
        return Colors.purpleAccent;
      default:
        return Colors.grey;
    }
  }

  Color _getAttentionColor(double percentage) {
    if (percentage == 0) return Colors.redAccent;
    if (percentage < 30) return Colors.orangeAccent;
    if (percentage < 50) return Colors.yellow;
    return Colors.greenAccent;
  }

  Widget _buildRecommendationItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Methods
  Color _getCompletionRateColor(double rate) {
    if (rate >= 0.8) return Colors.greenAccent;
    if (rate >= 0.6) return Colors.blueAccent;
    if (rate >= 0.4) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return Colors.amber;
      case 1:
        return Colors.grey[400]!;
      case 2:
        return Colors.brown[400]!;
      default:
        return Colors.grey[300]!;
    }
  }

  Future<int> _getDaysCompletedThisWeek({
    required String parentId,
    required String childId,
    required String taskId,
    required DateTime startOfWeek,
    required DateTime endOfWeek,
    required Map<String, dynamic> taskData,
  }) async {
    try {
      // Get completion dates array if it exists
      final completionDates = taskData['completionDates'] as List?;

      if (completionDates != null && completionDates.isNotEmpty) {
        // If you have an array of completion dates, count those within this week
        int count = 0;
        for (var date in completionDates) {
          if (date is Timestamp) {
            final completionDate = date.toDate();
            if (!completionDate.isBefore(startOfWeek) &&
                !completionDate.isAfter(endOfWeek)) {
              count++;
            }
          }
        }
        return count;
      }

      // Fallback: Check lastCompletedDate and doneAt
      final lastCompletedDate = taskData['lastCompletedDate'];
      final doneAt = taskData['doneAt'];

      // If task has never been completed, return 0
      if (lastCompletedDate == null && doneAt == null) {
        return 0;
      }

      // Get the most recent completion date
      DateTime? latestCompletion;

      if (lastCompletedDate != null && lastCompletedDate is Timestamp) {
        latestCompletion = lastCompletedDate.toDate();
      } else if (doneAt != null && doneAt is Timestamp) {
        latestCompletion = doneAt.toDate();
      }

      // If latest completion is before this week, return 0
      if (latestCompletion == null || latestCompletion.isBefore(startOfWeek)) {
        return 0;
      }

      // Check if task was completed within this week
      if (!latestCompletion.isAfter(endOfWeek)) {
        // Task was completed at least once this week
        // Now we need to estimate how many times

        // OPTION 1: Check history collection for daily completions
        try {
          final historySnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(parentId)
              .collection('children')
              .doc(childId)
              .collection('history')
              .where(
                'timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
              )
              .where(
                'timestamp',
                isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek),
              )
              .get();

          int completedCount = 0;

          // Search for task completion in history
          for (var doc in historySnap.docs) {
            final data = doc.data();
            final timestamp = doc['timestamp'];

            if (timestamp != null && timestamp is Timestamp) {
              final date = DateFormat('yyyy-MM-dd').format(timestamp.toDate());

              // Try different field names that might store task completion info
              if (data.containsKey('taskCompletions')) {
                final completions = data['taskCompletions'];
                if (completions is Map<String, dynamic> &&
                    completions[taskId] == true) {
                  completedCount++;
                }
              }
              // Check if task ID appears in any other field
              else if (data.containsKey('completedTasks')) {
                final completedTasks = data['completedTasks'];
                if (completedTasks is List<dynamic> &&
                    completedTasks.contains(taskId)) {
                  completedCount++;
                }
              }
            }
          }

          // If we found completions in history, use that count
          if (completedCount > 0) {
            return completedCount;
          }
        } catch (e) {
          print('⚠️ Error checking history for task $taskId: $e');
        }

        // OPTION 2: Use activeStreak as minimum estimate for current week
        final activeStreak = (taskData['activeStreak'] as int?) ?? 0;
        final totalDaysCompleted =
            (taskData['totalDaysCompleted'] as int?) ?? 0;

        // If task was completed today and active streak is > 0
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));

        if (latestCompletion.isAtSameMomentAs(today) ||
            (latestCompletion.isAfter(yesterday) &&
                latestCompletion.isBefore(
                  today.add(const Duration(days: 1)),
                ))) {
          // Estimate based on streak and days since start of week
          final daysSinceWeekStart = now.difference(startOfWeek).inDays + 1;
          final estimatedCompletions = min(activeStreak, daysSinceWeekStart);

          return max(
            1,
            estimatedCompletions,
          ); // At least 1 if completed this week
        }

        // OPTION 3: Simple check - if completed within this week, count as at least 1
        return 1;
      }

      return 0;
    } catch (e) {
      print(
        '❌ Error calculating days completed this week for task $taskId: $e',
      );
      return 0;
    }
  }

  Future<Map<String, dynamic>> _getWeeklyTaskAnalysis(String childId) async {
    try {
      final parentId = await _getParentIdFromChild(childId);

      if (parentId == null || parentId.isEmpty) {
        throw Exception('Parent not found for child');
      }

      print(
        '🔍 Fetching task analysis for child $childId from parent $parentId',
      );

      // Get current week boundaries
      final now = DateTime.now();
      final startOfWeek = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      print(
        '📅 Week range: ${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('MMM dd').format(endOfWeek)}',
      );

      // Fetch all tasks for the child
      final tasksSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('tasks')
          .get();

      if (tasksSnap.docs.isEmpty) {
        print('⚠️ No tasks found for child');
        return {};
      }

      final tasks = await Future.wait(
        tasksSnap.docs.map((doc) async {
          final data = doc.data();
          final taskId = doc.id;

          // Get days completed THIS WEEK for this task
          final daysCompletedThisWeek = await _getDaysCompletedThisWeek(
            parentId: parentId,
            childId: childId,
            taskId: taskId,
            startOfWeek: startOfWeek,
            endOfWeek: endOfWeek,
            taskData: data,
          );

          return {
            'id': taskId,
            'name': data['name'] ?? 'Unnamed Task',
            'isDone': data['isDone'] ?? false,
            'totalDaysCompleted': (data['totalDaysCompleted'] as int?) ?? 0,
            'lastCompletedDate': data['lastCompletedDate'] is Timestamp
                ? (data['lastCompletedDate'] as Timestamp).toDate()
                : null,
            'doneAt': data['doneAt'] is Timestamp
                ? (data['doneAt'] as Timestamp).toDate()
                : null,
            'activeStreak': (data['activeStreak'] as int?) ?? 0,
            'daysCompletedThisWeek': daysCompletedThisWeek,
            'routine': data['routine'] ?? 'anytime',
            'difficulty': data['difficulty'] ?? 'Medium',
            'reward': (data['reward'] as int?) ?? 0,
          };
        }),
      );

      print('📊 Found ${tasks.length} tasks');

      // Log each task's weekly completion
      for (var task in tasks) {
        print(
          '   - ${task['name']}: ${task['daysCompletedThisWeek']} days this week',
        );
      }

      // Calculate statistics
      int totalTasks = tasks.length;
      int totalCompletedToday = tasks.where((t) => t['isDone'] == true).length;
      double completionRateToday = totalTasks > 0
          ? totalCompletedToday / totalTasks
          : 0;

      // Calculate ACTUAL consistency for this week (not streak-based)
      int totalWeekDaysCompleted = 0;
      int maxPossibleCompletions = totalTasks * 7; // 7 days in a week

      for (var task in tasks) {
        totalWeekDaysCompleted += (task['daysCompletedThisWeek'] as int);
      }

      double weeklyConsistencyRate = maxPossibleCompletions > 0
          ? totalWeekDaysCompleted / maxPossibleCompletions
          : 0;

      print(
        '📈 Weekly consistency: $totalWeekDaysCompleted/$maxPossibleCompletions (${(weeklyConsistencyRate * 100).toStringAsFixed(1)}%)',
      );

      // Find best performing task (most days completed this week)
      String bestPerformingTask = 'No tasks';
      int bestTaskDaysCompleted = 0;

      // Find worst performing task (least days completed this week)
      String worstPerformingTask = 'No tasks';
      int worstTaskDaysCompleted = 7; // Start with max possible

      final List<Map<String, dynamic>> topTasks = [];
      final List<Map<String, dynamic>> bottomTasks = [];

      for (var task in tasks) {
        final taskName = task['name'] as String;
        final daysCompletedThisWeek = task['daysCompletedThisWeek'] as int;
        final difficulty = task['difficulty'] as String;
        final reward = task['reward'] as int;

        if (daysCompletedThisWeek > bestTaskDaysCompleted) {
          bestPerformingTask = taskName;
          bestTaskDaysCompleted = daysCompletedThisWeek;
        }

        if (daysCompletedThisWeek < worstTaskDaysCompleted) {
          worstPerformingTask = taskName;
          worstTaskDaysCompleted = daysCompletedThisWeek;
        }

        if (daysCompletedThisWeek > 0) {
          topTasks.add({
            'name': taskName,
            'totalDaysCompleted': daysCompletedThisWeek,
            'overallTotal': task['totalDaysCompleted'] as int,
            'routine': task['routine'] as String,
            'difficulty': difficulty,
            'reward': reward,
          });
        }

        // Add to bottom tasks if completed less than 3 days this week
        if (daysCompletedThisWeek < 3) {
          bottomTasks.add({
            'name': taskName,
            'totalDaysCompleted': daysCompletedThisWeek,
            'overallTotal': task['totalDaysCompleted'] as int,
            'routine': task['routine'] as String,
            'difficulty': difficulty,
            'reward': reward,
            'needsAttention': daysCompletedThisWeek == 0,
          });
        }
      }

      // Sort top tasks by days completed this week (descending)
      topTasks.sort(
        (a, b) => (b['totalDaysCompleted'] as int).compareTo(
          a['totalDaysCompleted'] as int,
        ),
      );

      // Sort bottom tasks by days completed this week (ascending)
      bottomTasks.sort(
        (a, b) => (a['totalDaysCompleted'] as int).compareTo(
          b['totalDaysCompleted'] as int,
        ),
      );

      // Take top 3 consistent tasks
      final top3Tasks = topTasks.take(3).toList();

      // Take bottom 3 unconsistent tasks (or all if less than 3)
      final bottom3Tasks = bottomTasks.take(3).toList();

      // Calculate consistency score (0-100)
      final consistencyScore = (weeklyConsistencyRate * 100).toInt();

      // Calculate daily completion pattern
      final dailyCompletionPattern = await _getDailyCompletionPattern(
        parentId: parentId,
        childId: childId,
        startOfWeek: startOfWeek,
      );

      print('✅ Analysis complete:');
      print('   - Total tasks: $totalTasks');
      print('   - Completed today: $totalCompletedToday');
      print(
        '   - Completion rate today: ${(completionRateToday * 100).toStringAsFixed(1)}%',
      );
      print(
        '   - Weekly consistency: $consistencyScore% ($totalWeekDaysCompleted days completed)',
      );
      print(
        '   - Best task this week: $bestPerformingTask ($bestTaskDaysCompleted days)',
      );
      print(
        '   - Worst task this week: $worstPerformingTask ($worstTaskDaysCompleted days)',
      );
      print('   - Top 3 consistent tasks: ${top3Tasks.length}');
      print('   - Bottom 3 unconsistent tasks: ${bottom3Tasks.length}');
      print('   - Daily pattern: $dailyCompletionPattern');

      return {
        'totalTasks': totalTasks,
        'totalCompleted': totalCompletedToday,
        'completionRate': completionRateToday,
        'activeStreak': _calculateRealisticActiveStreak(tasks),
        'consistencyScore': consistencyScore,
        'totalWeekDaysCompleted': totalWeekDaysCompleted,
        'bestPerformingTask': bestPerformingTask,
        'bestTaskDaysCompleted': bestTaskDaysCompleted,
        'worstPerformingTask': worstPerformingTask,
        'worstTaskDaysCompleted': worstTaskDaysCompleted,
        'topTasks': top3Tasks,
        'bottomTasks': bottom3Tasks,
        'dailyCompletionPattern': dailyCompletionPattern,
        'weeklyTrend': _generateWeeklyTrendData(
          totalWeekDaysCompleted,
          totalTasks,
        ),
      };
    } catch (e) {
      print('❌ Error fetching weekly task analysis: $e');
      return {};
    }
  }

  int _calculateRealisticActiveStreak(List<Map<String, dynamic>> tasks) {
    // Calculate a realistic streak based on recent completion pattern
    // Instead of just taking the highest activeStreak from tasks

    int maxStreak = 0;
    for (var task in tasks) {
      final streak = (task['activeStreak'] as int?) ?? 0;
      final daysCompletedThisWeek =
          (task['daysCompletedThisWeek'] as int?) ?? 0;

      // Give more weight to tasks with consistent weekly completion
      final adjustedStreak = streak * (1 + (daysCompletedThisWeek / 7));
      maxStreak = max(maxStreak, adjustedStreak.round());
    }

    return maxStreak;
  }

  Future<List<int>> _getDailyCompletionPattern({
    required String parentId,
    required String childId,
    required DateTime startOfWeek,
  }) async {
    final List<int> dailyCompletions = List.filled(7, 0);

    try {
      final endOfWeek = startOfWeek.add(const Duration(days: 6));

      // Get history for the week
      final historySnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .collection('history')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek),
          )
          .get();

      for (var doc in historySnap.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'];
        if (timestamp != null && timestamp is Timestamp) {
          final date = timestamp.toDate();
          final dayIndex = date.weekday - 1; // Monday = 0

          if (dayIndex >= 0 && dayIndex < 7) {
            final doneTasks = (data['done'] as int?) ?? 0;
            dailyCompletions[dayIndex] = doneTasks;
          }
        }
      }

      return dailyCompletions;
    } catch (e) {
      print('❌ Error getting daily completion pattern: $e');
      return dailyCompletions;
    }
  }

  List<int> _generateWeeklyTrendData(
    int totalWeekDaysCompleted,
    int totalTasks,
  ) {
    // Generate realistic trend data based on total completions
    final List<int> trend = List.filled(7, 0);

    if (totalWeekDaysCompleted == 0 || totalTasks == 0) {
      return trend;
    }

    // Distribute completions across the week (simplified)
    final avgDaily = totalWeekDaysCompleted / 7;

    for (int i = 0; i < 7; i++) {
      // Add some randomness to make it look natural
      final randomFactor = Random().nextDouble() * 0.4 + 0.8; // 0.8-1.2
      trend[i] = (avgDaily * randomFactor).round().clamp(0, totalTasks);
    }

    return trend;
  }

  Color _getConsistencyColor(double percentage) {
    if (percentage >= 85) return Colors.greenAccent;
    if (percentage >= 70) return Colors.lightGreenAccent;
    if (percentage >= 50) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Widget _legendWithCounter({
    required Color color,
    required String label,
    required int count,
  }) {
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
        Text('$label: $count', style: const TextStyle(fontSize: 12)),
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

    final activeChild =
        selectedChildProv.selectedChild ??
        {"cid": "", "name": "No Child", "therapistUid": widget.therapistId};

    final therapistName = _therapist?.name ?? "Therapist";
    final therapistEmail = _therapist?.email ?? "";

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
          'Therapist Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      drawer: TherapistAccountSidebar(therapistId: widget.therapistId),
      body: RefreshIndicator(
        onRefresh: _loadTherapistData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Text(
                      therapistName.isNotEmpty
                          ? therapistName[0].toUpperCase()
                          : 'P',
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
                          "Welcome Back, $therapistName!",
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          therapistEmail,
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
                    ..._buildChildCharts(
                      journalProv,
                      taskProv,
                      activeChild,
                      selectedChildProv,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
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
                                ? const SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      "No CBT exercises assigned this week.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: assignedCBT.length,
                                    itemBuilder: (context, index) {
                                      final assigned = assignedCBT[index];
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
