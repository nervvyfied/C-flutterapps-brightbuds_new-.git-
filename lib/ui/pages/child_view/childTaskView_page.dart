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
  Stream<DocumentSnapshot>? _balanceStream;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _initPage();
  }

  Future<void> _initPage() async {
  _settingsBox = await Hive.openBox('settings');
  
  await _checkConnectivity();
  
  // Make sure auto-reset runs *before* loading tasks
  final taskProvider = Provider.of<TaskProvider>(context, listen: false);
  await taskProvider.initHive();
  await taskProvider.autoResetIfNeeded();  // ✅ run reset early

  await _loadTasksOnce();
  _listenToBalance();      
  await _checkNewTokens();                 // now check AFTER reset
}


/// ✅ REAL-TIME BALANCE LISTENER
  void _listenToBalance() {
    _balanceStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.parentId)
        .collection('children')
        .doc(widget.childId)
        .snapshots();

    _balanceStream!.listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      final newBalance = data['balance'] ?? 0;
      if (mounted) {
        setState(() => _balance = newBalance);
      }
    });
  }


  Future<void> _checkNewTokens() async {
  final taskProvider = Provider.of<TaskProvider>(context, listen: false);

  // Get all tasks for this child
  final childTasks = taskProvider.tasks
      .where((task) => task.childId == widget.childId)
      .toList();

  if (childTasks.isEmpty) return;

  // Get last seen verified task timestamp
  final lastSeen = _settingsBox.get(
    'lastSeenVerifiedTaskTimestamp_${widget.childId}',
    defaultValue: 0,
  );

  // Filter tasks that are verified and updated after last seen
  final newTasks = childTasks.where((task) {
    final updatedTime = task.lastUpdated?.millisecondsSinceEpoch ?? 0;
    return (task.verified ?? false) && updatedTime > lastSeen;
  }).toList();

  if (newTasks.isEmpty) return;

  // Play confetti!
  _confettiController.play();

  // Show the token dialog
  _showTokenDialog(newTasks);

  // Update last seen timestamp
  final latestTimestamp = newTasks
      .map((t) => t.lastUpdated?.millisecondsSinceEpoch ?? 0)
      .reduce((a, b) => a > b ? a : b);

  _settingsBox.put(
      'lastSeenVerifiedTaskTimestamp_${widget.childId}', latestTimestamp);
}




  Future<void> _fetchBalance() async {
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(widget.parentId)
      .collection('children')
      .doc(widget.childId)
      .get();

  if (doc.exists && doc.data()!.containsKey('balance')) {
    setState(() => _balance = doc['balance'] ?? 0);
  }
}


  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  Future<void> _loadTasksOnce() async {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    await taskProvider.initHive();
    await taskProvider.autoResetIfNeeded();
    await taskProvider.loadTasks(
      parentId: widget.parentId,
      childId: widget.childId,
    );
    await taskProvider.autoResetIfNeeded();

    // Schedule alarms after tasks loaded
    final childTasks = taskProvider.tasks
        .where((task) => task.childId == widget.childId && task.alarm != null)
        .toList();

    for (var task in childTasks) {
      await taskProvider.scheduleTaskAlarm(task);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  /// Group tasks by time of day
  Map<String, List<TaskModel>> _groupTasksByTime(List<TaskModel> tasks) {
    final Map<String, List<TaskModel>> grouped = {
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
      'Anytime': [],
    };

    for (var task in tasks) {
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

    return grouped;
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

  Color _getCheckboxColor(bool isChecked) =>
      isChecked ? const Color(0xFFA6C26F) : const Color(0xFF8657F3);

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
        // Title Container (floating label style)
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
              )
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

        // Task Cards
        Column(
          children: tasks.map((task) {
            final isDone = task.isDone;
            final isVerified = task.verified ?? false;

            // Card background cue
            Color cardColor = Colors.white;
            if (isVerified) {
              cardColor = const Color.fromARGB(255, 109, 178, 235);
            } else if (isDone) {
              cardColor = Color.fromARGB(255, 202, 228, 150);
            }

            return Card(
              color: cardColor,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                title: Text(task.name),
                subtitle: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
                    )
                  ],
                ),
                trailing: isVerified
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                        final taskProvider =
                            Provider.of<TaskProvider>(context, listen: false);
                        final optimisticTask =
                            task.copyWith(isDone: value ?? false);
                        setState(() {
                          final index = tasks.indexOf(task);
                          tasks[index] = optimisticTask;
                        });

                        if (value == true) {
                          await taskProvider.markTaskAsDone(
                              task.id, task.childId);
                        } else {
                          await taskProvider.markTaskAsUndone(
                              task.id, task.childId);
                        }

                        unlockManager.checkUnlocks();

                        if (!isOffline) {
                          await taskProvider.pushPendingChanges();
                        }

                        await _fetchBalance();
                      },
                      checkColor: Colors.white,
                      activeColor: _getCheckboxColor(task.isDone),
                      side: BorderSide(
                        color: _getCheckboxColor(task.isDone),
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
                    '${task.reward ?? 0} token(s) for "${task.name}"'),
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
        // Confetti widget
        Positioned.fill(
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              Colors.yellow,
              Colors.blue,
              Colors.pink,
              Colors.green,
              Colors.orange
            ],
            numberOfParticles: 30,
            gravity: 0.3,
          ),
        ),
      ],
    ),
  );
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_getGreeting()}, ${widget.childName}!',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ready to start your day?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 0, 0, 0),
                            ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Color.fromARGB(255, 0, 0, 0)),
                      onPressed: () async {
                        final auth = Provider.of<AuthProvider>(context,
                            listen: false);
                        final fishProvider =
                            Provider.of<FishProvider>(context, listen: false);
                        final decorProvider =
                            Provider.of<DecorProvider>(context, listen: false);

                        await auth.logoutChild();
                        fishProvider.clearData();
                        decorProvider.clearData();

                        if (!mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ChooseRolePage()),
                          (route) => false,
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
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Consumer<TaskProvider>(
                    builder: (context, taskProvider, _) {
                      final childTasks = taskProvider.tasks
                          .where((task) =>
                              task.childId == widget.childId &&
                              task.name.isNotEmpty)
                          .toList();

                      if (childTasks.isEmpty) {
                        return const Center(child: Text("No tasks to display"));
                      }

                      final grouped = _groupTasksByTime(childTasks);
                      final total = childTasks.length;
                      final done = childTasks.where((t) => t.isDone).length;
                      final progress =
                          total == 0 ? 0.0 : done / total;

                      return RefreshIndicator(
                        onRefresh: _initPage,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            const Text(
                              "Complete your daily tasks to earn tokens!",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          "Daily Progress",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold, color: Colors.black87),
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 10,
                                            backgroundColor: Colors.grey[300],
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8657F3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Image.asset('assets/coin.png', width: 20, height: 20),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$_balance',
                                          style: const TextStyle(
                                              color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTaskGroup('Morning', grouped['Morning']!,
                                unlockManager, _isOffline),
                            _buildTaskGroup('Afternoon', grouped['Afternoon']!,
                                unlockManager, _isOffline),
                            _buildTaskGroup('Evening', grouped['Evening']!,
                                unlockManager, _isOffline),
                            _buildTaskGroup('Anytime', grouped['Anytime']!,
                                unlockManager, _isOffline),
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

  @override
void dispose() {
  _confettiController.dispose();
  super.dispose();
}
}
