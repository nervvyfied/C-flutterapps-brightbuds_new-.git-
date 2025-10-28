import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/aquarium/providers/fish_provider.dart';
import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/notifications/notification_service.dart';
import 'package:brightbuds_new/ui/pages/role_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'dart:async';

class ChildQuestsPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final String childName;

  const ChildQuestsPage({
    required this.parentId,
    required this.childId,
    required this.childName,
    super.key,
  });

  @override
  State<ChildQuestsPage> createState() => _ChildQuestsPageState();
}

class _ChildQuestsPageState extends State<ChildQuestsPage> {
  bool _isOffline = false;
  bool _isSyncing = false;
  int _balance = 0;
  late Box _settingsBox;
  late ConfettiController _confettiController;
  StreamSubscription<DocumentSnapshot>? _balanceSubscription;
  StreamSubscription<QuerySnapshot>? _taskSubscription;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    _initPage();
  }

  Future<void> _initPage() async {
    _settingsBox = await Hive.openBox('settings');

    // 1️⃣ Show cached balance immediately
    final cachedKey = 'cached_balance_${widget.childId}';
    final cached = _settingsBox.get(cachedKey, defaultValue: 0);
    if (mounted) setState(() => _balance = cached ?? 0);

    await _checkConnectivity();

    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    await taskProvider.initHive();
    await taskProvider.resetDailyTasks();
    await taskProvider.loadTasks(
      parentId: widget.parentId,
      childId: widget.childId,
    );

    // 2️⃣ Start real-time listeners after cached balance is displayed
    _listenToBalance();
    _listenToTasks();

    // 3️⃣ Fetch latest balance from Firestore (async update)
    _fetchBalance();
  }

  /// Listen to real-time balance updates
  void _listenToBalance() {
    _balanceSubscription?.cancel();
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentId)
        .collection('children')
        .doc(widget.childId)
        .snapshots();

    _balanceSubscription = stream.listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      final newBalance = (data['balance'] is int)
          ? data['balance']
          : (data['balance'] is double)
          ? (data['balance'] as double).toInt()
          : int.tryParse('${data['balance']}') ?? 0;

      // Update UI and cache instantly
      if (mounted) {
        setState(() => _balance = newBalance);
        _settingsBox.put('cached_balance_${widget.childId}', newBalance);
      }
    }, onError: (e) => debugPrint('❌ Balance stream error: $e'));
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

      // reload tasks from provider so UI updates
      final taskProvider = Provider.of<TaskProvider>(context, listen: false);
      await taskProvider.loadTasks(
        parentId: widget.parentId,
        childId: widget.childId,
      );

      // check for newly verified tasks and show tokens/popups
      await _checkNewTokens();
    }, onError: (e) => debugPrint('❌ Task stream error: $e'));
  }

  Future<void> _checkNewTokens() async {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    if (taskProvider.tasks.isEmpty) return;

    final lastSeenKey = 'lastSeenVerifiedTaskTimestamp_${widget.childId}';
    final lastSeen = _settingsBox.get(lastSeenKey, defaultValue: 0);

    final newTasks = taskProvider.tasks.where((task) {
      final updated = task.lastUpdated?.millisecondsSinceEpoch ?? 0;
      return (task.verified ?? false) && updated > lastSeen;
    }).toList();

    if (newTasks.isEmpty) return;

    // small delay to ensure UI is stable before showing dialog
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Use microtask to ensure it's scheduled *after* any pending setState
    Future.microtask(() {
      _confettiController.play();
      _showTokenDialog(newTasks);
    });

    final latest = newTasks
        .map((t) => t.lastUpdated?.millisecondsSinceEpoch ?? 0)
        .reduce((a, b) => a > b ? a : b);
    _settingsBox.put(lastSeenKey, latest);
  }

  Future<void> _fetchBalance() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.parentId)
          .collection('children')
          .doc(widget.childId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final val = doc['balance'];
      final fetched = (val is int)
          ? val
          : (val is double)
          ? val.toInt()
          : int.tryParse('$val') ?? 0;

      // Only update if different from current cached value
      final cachedKey = 'cached_balance_${widget.childId}';
      final cached = _settingsBox.get(cachedKey, defaultValue: 0);

      if (fetched != cached) {
        if (mounted) setState(() => _balance = fetched);
        _settingsBox.put(cachedKey, fetched);
        debugPrint('💰 Balance updated from Firestore: $fetched');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching balance: $e');
    }
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (mounted) setState(() => _isOffline = !online);
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
              final isVerified = task.verified ?? false;

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
                          color: _getDifficultyColor(task.difficulty ?? 'easy'),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          task.difficulty ?? 'Easy',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Image.asset('assets/coin.png', width: 16, height: 16),
                          const SizedBox(width: 4),
                          Text('${task.reward ?? 0}'),
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
                      : Checkbox(
                          value: task.isDone,
                          onChanged: (value) async {
                            final taskProvider = Provider.of<TaskProvider>(
                              context,
                              listen: false,
                            );

                            // optimistic UI update in-place
                            setState(() {
                              final idx = tasks.indexWhere(
                                (t) => t.id == task.id,
                              );
                              if (idx != -1) {
                                tasks[idx] = tasks[idx].copyWith(
                                  isDone: value ?? false,
                                );
                              }
                            });

                            // call correct provider methods
                            if (value == true) {
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

                            unlockManager.checkUnlocks();

                            // if online, push pending changes immediately
                            if (!isOffline) {
                              try {
                                await taskProvider.pushPendingChanges();
                              } catch (e) {
                                debugPrint('⚠️ pushPendingChanges failed: $e');
                              }
                            }

                            // refresh balance after change
                            await _fetchBalance();
                          },
                          checkColor: Colors.white,
                          activeColor: _getDifficultyColor(
                            task.difficulty ?? 'easy',
                          ),
                          side: BorderSide(
                            color: _getDifficultyColor(
                              task.difficulty ?? 'easy',
                            ),
                            width: 2,
                          ),
                        ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showTokenDialog(List<TaskModel> newTasks) {
    showDialog(
      context: context,
      builder: (context) => Stack(
        alignment: Alignment.center,
        children: [
          AlertDialog(
            title: const Text('You received tokens!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: newTasks.map((task) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '+${task.reward ?? 0} token(s) for "${task.name}"',
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
          Positioned.fill(
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 40,
              gravity: 0.3,
              colors: const [
                Colors.yellow,
                Colors.blue,
                Colors.pink,
                Colors.green,
                Colors.orange,
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _balanceSubscription?.cancel();
    _taskSubscription?.cancel();
    _confettiController.dispose();
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
                        final fish = Provider.of<FishProvider>(
                          context,
                          listen: false,
                        );
                        final decor = Provider.of<DecorProvider>(
                          context,
                          listen: false,
                        );
                        await auth.logoutChild();
                        fish.clearData();
                        decor.clearData();
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
                        return const Center(child: Text("No tasks to display"));
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
                        onRefresh: _initPage,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            const Text(
                              "Complete your daily tasks to earn tokens!",
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
                                    offset: Offset(0, 2),
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
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.green,
                                                ),
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
                                        Image.asset(
                                          'assets/coin.png',
                                          width: 20,
                                          height: 20,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$_balance',
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
