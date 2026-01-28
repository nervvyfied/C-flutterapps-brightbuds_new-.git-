// ignore_for_file: file_names, use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/data/notifiers/tokenNotifier.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';

class ChildQuestsPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;
  final String therapistId;
  const ChildQuestsPage({
    required this.parentId,
    required this.childId,
    required this.childName,
    required this.therapistId,
    super.key,
  });

  @override
  State<ChildQuestsPage> createState() => _ChildQuestsPageState();
}

class _ChildQuestsPageState extends State<ChildQuestsPage> {
  bool _isOffline = false;
  int _xp = 0;
  late Box _settingsBox;

  StreamSubscription<DocumentSnapshot>? _balanceSubscription;
  StreamSubscription<QuerySnapshot>? _taskSubscription;
  // Cached future to avoid racing openBox calls

  int _getXPForDifficulty(String difficulty) {
      switch (difficulty.toLowerCase()) {
        case 'easy':
          return 5;
        case 'medium':
          return 10;
        case 'hard':
          return 20;
        default:
          return 0;
      }
    }


  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Initialize page: load cached data immediately, then fetch online data
  Future<void> _initialize() async {
  _settingsBox = await Hive.openBox('settings');

 // 1️⃣ Load cached XP safely
  final cachedXP = _settingsBox.get(
    'cached_xp_${widget.childId}',
    defaultValue: 0,
  );
  setState(() => _xp = cachedXP);

  // 2️⃣ Load cached tasks safely
  final rawCachedTasks = _settingsBox.get(
    'cached_tasks_${widget.childId}',
    defaultValue: [],
  ) as List<dynamic>; // Always dynamic on Web

  final cachedTasks = rawCachedTasks.map((e) {
    if (e is TaskModel) return e;           // Mobile: already TaskModel
    if (e is Map<String, dynamic>) return TaskModel.fromMap(e); // Web: stored as Map
    return null;
  }).whereType<TaskModel>().toList();

  final taskProvider = Provider.of<TaskProvider>(context, listen: false);
  if (cachedTasks.isNotEmpty) {
    taskProvider.loadCachedTasks(cachedTasks);
  }

  // 3️⃣ Check connectivity
  final online = await NetworkHelper.isOnline();
  if (mounted) setState(() => _isOffline = !online);

  // 4️⃣ Initialize provider Hive & fetch tasks async
  taskProvider.initHive();
  await taskProvider.loadTasks(parentId: widget.parentId, childId: widget.childId);
  taskProvider.startDailyResetScheduler();

  // 5️⃣ Start listeners
  _listenToXP();
  _listenToTasks();

  // 6️⃣ Fetch XP from Firestore in background
  _fetchXP();
}

  /// Real-time task listener — reloads provider tasks and checks for new tokens
  void _listenToTasks() {
    _taskSubscription?.cancel();

  final stream = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.parentId)
      .collection('children')
      .doc(widget.childId)
      .collection('tasks')
      .snapshots();

  _taskSubscription = stream.listen((snapshot) async {
    if (!mounted) return;
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final tokenNotifier = Provider.of<TokenNotifier>(context, listen: false);

    // Reload tasks from Firestore
    await taskProvider.loadTasks(
      parentId: widget.parentId,
      childId: widget.childId,
    );

    // ✅ Save tasks to Hive safely (always convert to Map for Web)
    final tasksToCache = taskProvider.tasks.map((t) => t.toMapForHive()).toList();
    await _settingsBox.put('cached_tasks_${widget.childId}', tasksToCache);

    // Find newly verified tasks
    final newlyVerifiedTasks = taskProvider.tasks.where((t) {
      if (t.verified != true) return false;

      final rawSeen = _settingsBox.get(
        'seen_verified_tasks_${widget.childId}',
        defaultValue: [],
      ) as List<dynamic>; // Always dynamic
      final seenIds = rawSeen.whereType<String>().toList();

      return !seenIds.contains(t.id);
    }).toList();

    if (newlyVerifiedTasks.isNotEmpty) {
      final rawSeen = _settingsBox.get(
        'seen_verified_tasks_${widget.childId}',
        defaultValue: [],
      ) as List<dynamic>;
      final seenIds = rawSeen.whereType<String>().toList();
      seenIds.addAll(newlyVerifiedTasks.map((t) => t.id));
      await _settingsBox.put('seen_verified_tasks_${widget.childId}', seenIds);

      tokenNotifier.addNewlyVerifiedTasks(newlyVerifiedTasks);
    }
  }, onError: (e) => debugPrint('❌ Task stream error: $e'));
}
  /// Listen to real-time XP updates and sync to Hive safely
void _listenToXP() {
  _balanceSubscription?.cancel(); // reuse subscription variable

  final docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.parentId)
      .collection('children')
      .doc(widget.childId);

  _balanceSubscription = docRef.snapshots().listen((snapshot) async {
    if (!snapshot.exists) return;
    final data = snapshot.data();
    if (data == null) return;

    final newXP = (data['xp'] is int)
        ? data['xp']
        : (data['xp'] is double)
            ? (data['xp'] as double).toInt()
            : int.tryParse('${data['xp']}') ?? 0;

    final cachedKey = 'cached_xp_${widget.childId}';

    // ✅ Update UI immediately
    if (mounted) setState(() => _xp = newXP);

    // ✅ Save to settings Hive box
    await _settingsBox.put(cachedKey, newXP);

    // ✅ Persist to Hive childBox if open and type-safe
    if (Hive.isBoxOpen('childBox')) {
      try {
        final childBox = Hive.box<ChildUser>('childBox');
        final child = childBox.get(widget.childId);
        if (child != null) {
          final updatedChild = child.copyWith(xp: newXP);
          await childBox.put(widget.childId, updatedChild);
          debugPrint('💾 Hive childBox XP updated: $newXP');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to persist XP to childBox: $e');
      }
    } else {
      debugPrint('⚠️ childBox not open yet, skipping XP update.');
    }

    debugPrint('🟢 XP synced Firestore → Hive: $newXP');
  }, onError: (e) => debugPrint('❌ XP stream error: $e'));
}



  /// Fetch balance from Firestore (offline-first) and sync to Hive safely
  /// Fetch XP from Firestore (offline-first) and sync to Hive safely
Future<void> _fetchXP() async {
  final cachedKey = 'cached_xp_${widget.childId}';

  // ✅ Load cached Hive value immediately
  final cached = _settingsBox.get(cachedKey, defaultValue: 0);
  if (mounted) setState(() => _xp = cached);
  debugPrint('📦 Loaded cached XP: $cached');

  // ✅ Fetch latest from Firestore if online
  if (await NetworkHelper.isOnline()) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .collection('children')
          .doc(widget.childId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final val = doc['xp'];
      final fetched = (val is int)
          ? val
          : (val is double)
              ? val.toInt()
              : int.tryParse('$val') ?? 0;

      if (fetched != cached) {
        if (mounted) setState(() => _xp = fetched);
        await _settingsBox.put(cachedKey, fetched);

        // ✅ Persist to Hive childBox safely
        if (Hive.isBoxOpen('childBox')) {
          try {
            final childBox = Hive.box<ChildUser>('childBox');
            final child = childBox.get(widget.childId);
            if (child != null) {
              final updatedChild = child.copyWith(xp: fetched);
              await childBox.put(widget.childId, updatedChild);
              debugPrint('💾 Hive childBox XP refreshed: $fetched');
            }
          } catch (e) {
            debugPrint('⚠️ Failed to update Hive child XP: $e');
          }
        } else {
          debugPrint('⚠️ childBox not open yet, skipping Hive update.');
        }

        debugPrint('🟢 XP refreshed Firestore → Hive: $fetched');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching XP from Firestore: $e');
    }
  } else {
    debugPrint('📴 Offline mode — using cached Hive XP.');
  }
}

  String _getGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return const Color(0xFFA6C26F);
      case 'medium':
        return const Color(0xFFFECE00);
      case 'hard':
        return const Color(0xFFFD5C68);
      default:
        return Colors.grey;
    }
  }

  Widget _buildTaskGroup(
    String title,
    List<TaskModel> tasks,
    UnlockManager unlockManager,
    bool isOffline,
  ) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8657F3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Column(
            children: tasks.map((task) {
              final isDone = task.isDone;
              final isVerified = task.verified;

              Color cardColor = Colors.white;
              if (isVerified) {
                cardColor = const Color.fromARGB(255, 109, 178, 235);
              } else if (isDone) {
                cardColor = const Color.fromARGB(255, 202, 228, 150);
              }

              return Card(
                color: cardColor,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  title: Text(task.name),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getDifficultyColor(task.difficulty),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.difficulty,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          const Icon(Icons.flash_on, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            '+${_getXPForDifficulty(task.difficulty)} XP',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: isVerified
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Verified',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Consumer<TaskProvider>(
                          builder: (context, taskProvider, _) {
                            final taskStatus =
                                taskProvider.getTaskById(task.id)?.isDone ??
                                false;

                            return Checkbox(
                              value: taskStatus,
                              onChanged: (value) async {
                                if (value == null) return;

                                try {
                                  if (value) {
                                    await taskProvider.markTaskAsDone(
                                      task.id,
                                      task.childId,
                                    );
                                  } else {
                                    await taskProvider.markTaskAsUndone(
                                      task.id,
                                      task.childId,
                                    );
                                  }

                                  // Update progress immediately
                                  taskProvider.updateTask(
                                    task.copyWith(isDone: value),
                                  );

                                  final childMap = unlockManager.childProvider.selectedChild;
                                  final currentLevel = childMap?['level'] ?? 1; // fallback to 1 if null
                                  unlockManager.checkLevelUnlocks(currentLevel);

                                  if (!_isOffline) {
                                    await taskProvider.pushPendingChanges();
                                  }

                                  await _fetchXP();
                                } catch (e) {
                                  debugPrint('⚠️ Error updating task: $e');
                                }
                              },
                              checkColor: Colors.white,
                              activeColor: _getDifficultyColor(task.difficulty),
                              side: BorderSide(
                                color: _getDifficultyColor(task.difficulty),
                                width: 2,
                              ),
                            );
                          },
                        ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    _taskSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unlockManager = Provider.of<UnlockManager>(context, listen: false);

    return Scaffold(
      body: Stack(
        children: [
          Image.asset(
            'assets/general_bg.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          Column(
            children: [
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_getGreeting()}, ${widget.childName}!',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.black),
                      onPressed: () async {
                        final auth = Provider.of<AuthProvider>(
                          context,
                          listen: false,
                        );
                        await auth.signOut();
                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ChooseRolePage(),
                          ),
                          (r) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(235, 255, 255, 255),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Consumer<TaskProvider>(
                    builder: (context, taskProvider, _) {
                      final childTasks = taskProvider.tasks
                          .where(
                            (t) =>
                                t.childId == widget.childId &&
                                t.name.isNotEmpty,
                          )
                          .toList();

                      if (childTasks.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final grouped = {
                        'Morning': <TaskModel>[],
                        'Afternoon': <TaskModel>[],
                        'Evening': <TaskModel>[],
                        'Anytime': <TaskModel>[],
                      };

                      for (var task in childTasks) {
                        switch (task.routine.toLowerCase()) {
                          case 'morning':
                            grouped['Morning']!.add(task);
                            break;
                          case 'afternoon':
                            grouped['Afternoon']!.add(task);
                            break;
                          case 'evening':
                            grouped['Evening']!.add(task);
                            break;
                          default:
                            grouped['Anytime']!.add(task);
                        }
                      }

                      final total = childTasks.length;
                      final done = childTasks.where((t) => t.isDone).length;
                      final progress = total == 0 ? 0.0 : done / total;

                      return RefreshIndicator(
                        onRefresh: _initialize,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            const Text(
                              "Complete your daily tasks to earn XP!",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Daily Progress",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 10,
                                            backgroundColor: Colors.grey[300],
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                  Color
                                                >(Colors.green),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8657F3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.flash_on,
                                          color: Colors.orange,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$_xp XP',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTaskGroup(
                              'Morning',
                              grouped['Morning']!,
                              unlockManager,
                              _isOffline,
                            ),
                            _buildTaskGroup(
                              'Afternoon',
                              grouped['Afternoon']!,
                              unlockManager,
                              _isOffline,
                            ),
                            _buildTaskGroup(
                              'Evening',
                              grouped['Evening']!,
                              unlockManager,
                              _isOffline,
                            ),
                            _buildTaskGroup(
                              'Anytime',
                              grouped['Anytime']!,
                              unlockManager,
                              _isOffline,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_isOffline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.redAccent,
                padding: const EdgeInsets.all(8),
                child: const Text(
                  "You're offline. Changes will sync automatically when online.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
