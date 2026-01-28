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

      // Save under parent's path (for parent app)
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
        'savedBy': 'parent',
      });

      print(
        "✅ Daily progress saved for $childId on $dateKey (both parent & therapist)",
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
  TherapistUser? _therapist;
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

  Future<void> _showTaskHistoryModal(
    BuildContext context,
    String childId,
  ) async {
    print('Fetching task history for child: $childId');

    try {
      List<Map<String, dynamic>> historyData = [];

      // Try to fetch from therapist's collection first
      try {
        final therapistSnap = await FirebaseFirestore.instance
            .collection('therapists')
            .doc(widget.therapistId)
            .collection('children')
            .doc(childId)
            .collection('history')
            .orderBy('timestamp', descending: true)
            .limit(90)
            .get();

        if (therapistSnap.docs.isNotEmpty) {
          print('Found ${therapistSnap.docs.length} records in therapist path');
          historyData = therapistSnap.docs
              .map(
                (d) => {
                  'date': d.id,
                  'done': d['done'] ?? 0,
                  'notDone': d['notDone'] ?? 0,
                  'missed': d['missed'] ?? 0,
                  'source': 'therapist',
                },
              )
              .toList();
        }
      } catch (e) {
        print('Error fetching from therapist path: $e');
      }

      // If no data in therapist path, try parent path
      if (historyData.isEmpty && widget.parentId.isNotEmpty) {
        try {
          final parentSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.parentId)
              .collection('children')
              .doc(childId)
              .collection('history')
              .orderBy('timestamp', descending: true)
              .limit(90)
              .get();

          if (parentSnap.docs.isNotEmpty) {
            print('Found ${parentSnap.docs.length} records in parent path');
            historyData = parentSnap.docs
                .map(
                  (d) => {
                    'date': d.id,
                    'done': d['done'] ?? 0,
                    'notDone': d['notDone'] ?? 0,
                    'missed': d['missed'] ?? 0,
                    'source': 'parent',
                  },
                )
                .toList();
          }
        } catch (e) {
          print('Error fetching from parent path: $e');
        }
      }

      if (historyData.isEmpty) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("No task history"),
            content: const Text(
              "Task history hasn't been saved yet. History is saved automatically at the end of each day.",
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

      print('Total history records: ${historyData.length}');

      // Show the modal with the fetched data
      _showTaskHistoryModalWithData(context, historyData);
    } catch (e) {
      print('Error fetching task history: $e');
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

  void _showTaskHistoryModalWithData(
    BuildContext context,
    List<Map<String, dynamic>> historyData,
  ) {
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
            // Initialize state variables
            int currentIndex = 0;
            String viewMode = 'Daily';

            // Helper function to get displayed data
            List<Map<String, dynamic>> getDisplayedData() {
              if (historyData.isEmpty) return [];

              final windowSize = viewMode == 'Daily' ? 1 : 7;
              final start = currentIndex;
              final end = (currentIndex + windowSize).clamp(
                0,
                historyData.length,
              );

              if (start >= end) return [];

              final slice = historyData.sublist(start, end);

              if (viewMode == 'Weekly') {
                // Aggregate weekly data
                int done = 0, notDone = 0, missed = 0;
                for (var d in slice) {
                  done += d['done'] as int;
                  notDone += d['notDone'] as int;
                  missed += d['missed'] as int;
                }

                final dateLabel = slice.isNotEmpty
                    ? "${slice.first['date']} - ${slice.last['date']}"
                    : "";

                return [
                  {
                    'date': dateLabel,
                    'done': done,
                    'notDone': notDone,
                    'missed': missed,
                  },
                ];
              } else {
                // Daily view - show individual days
                return slice
                    .map(
                      (d) => ({
                        'date': d['date'],
                        'done': d['done'] as int,
                        'notDone': d['notDone'] as int,
                        'missed': d['missed'] as int,
                      }),
                    )
                    .toList();
              }
            }

            final displayedData = getDisplayedData();

            // Determine if arrows should be disabled
            final windowSize = viewMode == 'Daily' ? 1 : 7;
            final isPrevDisabled =
                currentIndex + windowSize >= historyData.length;
            final isNextDisabled = currentIndex <= 0;

            void prev() {
              if (!isPrevDisabled) {
                setState(() {
                  currentIndex = (currentIndex + windowSize).clamp(
                    0,
                    historyData.length - windowSize,
                  );
                });
              }
            }

            void next() {
              if (!isNextDisabled) {
                setState(() {
                  currentIndex = (currentIndex - windowSize).clamp(
                    0,
                    historyData.length,
                  );
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                height: 500,
                child: Column(
                  children: [
                    const Text(
                      "Task Progress History",
                      style: TextStyle(
                        fontSize: 18,
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
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FilterChip(
                            label: Text(mode),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                viewMode = mode;
                                currentIndex = 0;
                              });
                            },
                            selectedColor: Colors.deepPurpleAccent,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    // Chart with arrows
                    Expanded(
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios),
                            onPressed: isPrevDisabled ? null : prev,
                            color: isPrevDisabled
                                ? Colors.grey
                                : Colors.deepPurpleAccent,
                          ),
                          Expanded(
                            child: displayedData.isEmpty
                                ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.history,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 8),
                                        Text("No history data"),
                                      ],
                                    ),
                                  )
                                : SizedBox(
                                    height: 250,
                                    child: BarChart(
                                      BarChartData(
                                        alignment:
                                            BarChartAlignment.spaceAround,
                                        titlesData: FlTitlesData(
                                          leftTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 40,
                                              getTitlesWidget: (value, meta) {
                                                return Text(
                                                  value.toInt().toString(),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          bottomTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 30,
                                              getTitlesWidget: (value, meta) {
                                                if (value >= 0 &&
                                                    value <
                                                        displayedData.length) {
                                                  final date =
                                                      displayedData[value
                                                              .toInt()]['date']
                                                          .toString();
                                                  // Format date for display
                                                  String displayDate;
                                                  if (viewMode == 'Weekly') {
                                                    displayDate = 'Week';
                                                  } else {
                                                    // Try to parse date for better formatting
                                                    try {
                                                      final parts = date.split(
                                                        '-',
                                                      );
                                                      if (parts.length >= 3) {
                                                        displayDate =
                                                            '${parts[1]}/${parts[2]}';
                                                      } else {
                                                        displayDate =
                                                            date.length > 10
                                                            ? '${date.substring(5, 10)}'
                                                            : date;
                                                      }
                                                    } catch (e) {
                                                      displayDate =
                                                          date.length > 10
                                                          ? '${date.substring(5, 10)}'
                                                          : date;
                                                    }
                                                  }
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 8.0,
                                                        ),
                                                    child: Text(
                                                      displayDate,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  );
                                                }
                                                return const Text('');
                                              },
                                            ),
                                          ),
                                          topTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                          rightTitles: AxisTitles(
                                            sideTitles: SideTitles(
                                              showTitles: false,
                                            ),
                                          ),
                                        ),
                                        borderData: FlBorderData(show: false),
                                        gridData: FlGridData(show: true),
                                        barGroups: List.generate(
                                          displayedData.length,
                                          (i) {
                                            final entry = displayedData[i];
                                            return BarChartGroupData(
                                              x: i,
                                              barsSpace: 4,
                                              barRods: [
                                                BarChartRodData(
                                                  toY: (entry['done'] as int)
                                                      .toDouble(),
                                                  color:
                                                      Colors.deepPurpleAccent,
                                                  width: viewMode == 'Daily'
                                                      ? 8
                                                      : 16,
                                                ),
                                                BarChartRodData(
                                                  toY: (entry['notDone'] as int)
                                                      .toDouble(),
                                                  color: Colors.yellow,
                                                  width: viewMode == 'Daily'
                                                      ? 8
                                                      : 16,
                                                ),
                                                BarChartRodData(
                                                  toY: (entry['missed'] as int)
                                                      .toDouble(),
                                                  color: Colors.redAccent,
                                                  width: viewMode == 'Daily'
                                                      ? 8
                                                      : 16,
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios),
                            onPressed: isNextDisabled ? null : next,
                            color: isNextDisabled
                                ? Colors.grey
                                : Colors.deepPurpleAccent,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Legend with aggregated data
                    if (displayedData.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _legendWithCounter(
                            color: Colors.deepPurpleAccent,
                            label: 'Done',
                            count: displayedData.fold<int>(
                              0,
                              (sum, item) => sum + (item['done'] as int),
                            ),
                          ),
                          _legendWithCounter(
                            color: Colors.yellow,
                            label: 'Not Done',
                            count: displayedData.fold<int>(
                              0,
                              (sum, item) => sum + (item['notDone'] as int),
                            ),
                          ),
                          _legendWithCounter(
                            color: Colors.redAccent,
                            label: 'Missed',
                            count: displayedData.fold<int>(
                              0,
                              (sum, item) => sum + (item['missed'] as int),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(
                        displayedData.length == 1
                            ? displayedData.first['date'].toString()
                            : "${displayedData.length} ${viewMode == 'Daily' ? 'days' : 'weeks'} shown",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
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

    final List<String> moodOrder = [
      'calm',
      'sad',
      'happy',
      'confused',
      'angry',
      'scared',
    ];

    // --- WEEKLY DATA ---
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
    weekStarts.sort((a, b) => b.compareTo(a)); // latest first

    // --- MONTHLY DATA ---
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
                .where(
                  (e) =>
                      e.createdAt.month == monthStart.month &&
                      e.createdAt.year == monthStart.year,
                )
                .toList();
            label = "${monthStart.month}/${monthStart.year}";
          } else {
            // --- WEEKLY VIEW ---
            final weekStart = weekStarts[currentWeekIndex];
            final weekEnd = weekStart.add(const Duration(days: 6));
            final key = "${weekStart.year}-${weekStart.month}-${weekStart.day}";
            entriesToDisplay = weekGroups[key]!;
            label =
                "Week of ${weekStart.month}/${weekStart.day}-${weekEnd.month}/${weekEnd.day}";
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
                // Pie chart
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
                // Weekly Bar chart
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
                              if (dayCounts.containsKey(mood))
                                dayCounts[mood] = dayCounts[mood]! + 1;
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
      _loadTherapistData();

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

  void _listenToJournalEntries() {
    final journalProv = Provider.of<JournalProvider>(context, listen: false);
    final selectedChildProv = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    final child = selectedChildProv.selectedChild;

    if (child == null) return;
    if (child['cid'] == null || child['cid'].toString().isEmpty) return;

    final therapistId = _therapist?.uid;
    if (therapistId == null || therapistId.isEmpty) return;

    final childId = child['cid'];

    journalProv.loadEntries(
      childId: childId,
      parentId: '', // therapist context
    );
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

    final therapistId = _therapist?.uid ?? widget.therapistId;
    final childId = child['cid'];

    // Initialize Hive if not yet
    await cbtProv.initHive();

    // Load and sync CBTs
    await cbtProv.loadLocalCBT(childId);
    await cbtProv.loadRemoteCBT(therapistId, childId);

    // Start listening for real-time Firestore updates
    cbtProv.updateRealtimeListenerForChild(therapistId, childId);
  }

  Future<void> _loadTherapistData() async {
    setState(() => _loading = true);

    await Future.delayed(
      Duration(milliseconds: 500),
    ); // Small delay to ensure auth is ready

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final therapistModel = auth.currentUserModel;

    if (therapistModel == null || therapistModel is! TherapistUser) {
      // Try to get therapist from Firestore directly
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

          // Force a rebuild with the new data
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _therapist = therapist;
                _loading = false;
              });
            }
          });
          return;
        }
      } catch (e) {
        debugPrint('Error fetching therapist: $e');
      }

      setState(() => _loading = false);
      return;
    }

    // Force UI update with animation frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _therapist = therapistModel;
          _loading = false;
        });
      }
    });
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

  Future<void> exportChildDataToPdfWithCharts(
    String therapistId,
    String parentId,
    String childId,
    Map<String, dynamic> childData,
  ) async {
    final pdf = pw.Document();
    final name = childData['name'] ?? 'Unknown';
    final parentName = childData['parentName'] ?? '-';
    final therapistName = childData['therapistName'] ?? '-';
    final therapistEmail = childData['therapistEmail'] ?? '-';
    final moodCounts = Map<String, int>.from(childData['moodCounts'] ?? {});
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    // ---------------- Fetch weekly task progress history ----------------
    final historySnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .limit(7)
        .get();

    final weeklyHistory = historySnap.docs
        .map(
          (d) => {
            'date': d.id,
            'done': d['done'] ?? 0,
            'notDone': d['notDone'] ?? 0,
            'missed': d['missed'] ?? 0,
          },
        )
        .toList();

    // ---------------- Fetch weekly CBT assignments ----------------
    final cbtSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(parentId)
        .collection('children')
        .doc(childId)
        .collection('CBT')
        .get();

    // Filter assignments for this week and map them
    final cbtTasks = cbtSnap.docs
        .map((d) {
          final data = d.data();

          // Use exerciseId instead of title/docId
          final exerciseId = data['exerciseId'] ?? d.id;

          // Get the assigned date or createdAt (must exist in your DB)
          final assignedAt = data['assignedAt'];
          DateTime assignedDate;
          if (assignedAt is Timestamp) {
            assignedDate = assignedAt.toDate();
          } else if (assignedAt is DateTime) {
            assignedDate = assignedAt;
          } else {
            assignedDate = DateTime.now(); // fallback if no date
          }

          // Only include if assigned within this week
          if (assignedDate.isBefore(startOfWeek) ||
              assignedDate.isAfter(endOfWeek)) {
            return null;
          }

          final completed = data['completed'] ?? false;
          final status = completed ? 'Completed' : 'Pending';

          return {'exerciseId': exerciseId, 'status': status};
        })
        .where((e) => e != null)
        .toList();

    // ---------------- Compute Summary Statistics ----------------
    int done = 0, notDone = 0, missed = 0;
    for (var h in weeklyHistory) {
      done += (h['done'] as num).toInt();
      notDone += (h['notDone'] as num).toInt();
      missed += (h['missed'] as num).toInt();
    }
    final totalTasks = done + notDone + missed;
    final completionRate = totalTasks > 0
        ? (done / totalTasks * 100).toStringAsFixed(1)
        : '0';
    final missedRate = totalTasks > 0
        ? (missed / totalTasks * 100).toStringAsFixed(1)
        : '0';

    // Compute top mood safely
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

    // ---------------- Behavioral Insights ----------------
    String mostProductiveDay = '-';
    String mostMissedDay = '-';
    double highestCompletionRate = 0;
    double lowestCompletionRate = 1;

    for (var entry in weeklyHistory) {
      final total = (entry['done'] + entry['notDone'] + entry['missed'])
          .toDouble();
      if (total > 0) {
        final rate = entry['done'] / total;
        if (rate > highestCompletionRate) {
          highestCompletionRate = rate;
          mostProductiveDay = entry['date'];
        }
        if (rate < lowestCompletionRate) {
          lowestCompletionRate = rate;
          mostMissedDay = entry['date'];
        }
      }
    }

    // ---------------- PDF BUILD ----------------
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // HEADER
            pw.Text(
              "$name's Weekly Progress Report",
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              "Date Range: ${dateFormat.format(startOfWeek)} - ${dateFormat.format(endOfWeek)}",
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              "Therapist: $therapistName ($therapistEmail)",
              style: const pw.TextStyle(fontSize: 12),
            ),
            pw.Divider(),

            // SUMMARY STATISTICS
            pw.Text(
              "Summary Statistics",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Bullet(text: "Total Tasks: $totalTasks"),
            pw.Bullet(text: "Completion Rate: $completionRate%"),
            pw.Bullet(text: "Missed Rate: $missedRate%"),
            pw.Bullet(text: "Most Frequent Mood: $topMood"),
            pw.Bullet(text: "Mood Diversity: $moodDiversity"),
            pw.SizedBox(height: 16),

            // MOOD SUMMARY
            pw.Text(
              "Mood Summary",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              height: 150,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: moodCounts.entries.map((entry) {
                  final color =
                      PdfColors.primaries[moodCounts.keys.toList().indexOf(
                            entry.key,
                          ) %
                          PdfColors.primaries.length];
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      children: [
                        pw.Container(width: 10, height: 10, color: color),
                        pw.SizedBox(width: 8),
                        pw.Text(
                          '${entry.key[0].toUpperCase() + entry.key.substring(1)}: ${entry.value}',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            pw.SizedBox(height: 16),

            // DAILY BREAKDOWN TABLE
            pw.Text(
              "Daily Task Breakdown",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Table.fromTextArray(
              headers: ['Date', 'Done', 'Not Done', 'Missed', 'Completion %'],
              data: weeklyHistory.map((h) {
                final total = (h['done'] + h['notDone'] + h['missed'])
                    .toDouble();
                final completion = total > 0
                    ? ((h['done'] / total) * 100).toStringAsFixed(0)
                    : '0';
                return [
                  h['date'],
                  h['done'].toString(),
                  h['notDone'].toString(),
                  h['missed'].toString(),
                  '$completion%',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),

            // CBT ASSIGNMENTS
            pw.Text(
              "CBT Assignments",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            ...cbtTasks.isEmpty
                ? [pw.Text("No CBT assignments for this week.")]
                : cbtTasks.map(
                    (cbt) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("${cbt?['exerciseId']} - ${cbt?['status']}"),
                        ],
                      ),
                    ),
                  ),
            pw.SizedBox(height: 16),

            // BEHAVIORAL INSIGHTS
            pw.Text(
              "Behavioral Insights",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.Bullet(
              text:
                  "Most Focused Day: ${mostProductiveDay != '-' ? mostProductiveDay : 'No data'}",
            ),
            pw.Bullet(
              text:
                  "Most Missed Day: ${mostMissedDay != '-' ? mostMissedDay : 'No data'}",
            ),
            pw.Bullet(
              text:
                  "Consistency Level: ${completionRate}% average task completion",
            ),
            pw.Bullet(
              text:
                  "Emotional Stability: ${moodDiversity} moods expressed this week (${topMood != '-' ? 'mainly $topMood' : 'no mood data'})",
            ),

            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                "Generated by BrightBuds Therapist Dashboard",
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey),
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      name: "child_${name}_weekly_report.pdf",
      onLayout: (format) async => pdf.save(),
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

    final taskHistoryService = TaskHistoryService();
    await taskHistoryService.saveDailyTaskProgress(
      parentId: widget.parentId,
      therapistId: widget.therapistId,
      childId: childId,
      done: statusCounts['done']!,
      notDone: statusCounts['notDone']!,
      missed: statusCounts['missed']!,
    );
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
    // At the end of _buildChildCharts method, add:
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveCurrentTaskProgress(taskProv, activeChild);
    });
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

              await exportChildDataToPdfWithCharts(
                widget.therapistId,
                childId,
                activeChild['name'],
                fullChildData,
              );
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
                          final therapistId = widget.therapistId;
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
                              builder: (context) => TherapistCBTPage(
                                therapistId: therapistId,
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
              child: GestureDetector(
                onTap: () async {
                  await _showTaskHistoryModal(context, activeChild['cid']);
                },
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
                                    color: Colors
                                        .redAccent, // visually highlights missed
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
                            _legendWithCounter(
                              color: Colors.deepPurpleAccent,
                              label: 'Done',
                              count: done.toInt(),
                            ),
                            const SizedBox(height: 8),
                            _legendWithCounter(
                              color: Colors.yellow,
                              label: 'Not Done',
                              count: notDone.toInt(),
                            ),
                            const SizedBox(height: 8),
                            _legendWithCounter(
                              color: Colors.redAccent,
                              label: 'Missed',
                              count: missed.toInt(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildAnalyticsPage<T>({
    required String title,
    required IconData icon,
    required Color color,
    required List<T> items,
    required Widget Function(T) builder,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        "No data available",
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: builder(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
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
        {"cid": "", "name": "No Child", "therapistUid": widget.therapistId};

    final therapistName = _therapist?.name ?? "Therapist";
    final therapistEmail = _therapist?.email ?? "";

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
              // ---------------- Greeting Area ----------------
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
