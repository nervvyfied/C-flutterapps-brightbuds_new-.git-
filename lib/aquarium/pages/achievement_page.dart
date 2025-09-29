import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../catalogs/fish_catalog.dart';
import '../models/fish_definition.dart';
import '/data/models/child_model.dart';
import '/data/models/task_model.dart';
import '../models/placedDecor_model.dart';
import '../providers/fish_provider.dart';
import '../manager/unlockManager.dart';

class AchievementPage extends StatefulWidget {
  const AchievementPage({super.key});

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  late UnlockManager unlockManager;
  late ChildUser child;

  List<TaskModel> tasks = [];
  List<PlacedDecor> decors = [];

  Stream<List<TaskModel>>? tasksStream;
  Stream<List<PlacedDecor>>? decorsStream;

  @override
  void initState() {
    super.initState();
    final fishProvider = context.read<FishProvider>();
    child = fishProvider.currentChild;
    unlockManager = UnlockManager(context.read<UnlockNotifier>(), fishProvider: fishProvider);

    _setupStreams();
  }

  void _setupStreams() {
    // Tasks snapshot listener
    tasksStream = FirebaseFirestore.instance
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('tasks')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => TaskModel.fromFirestore(d.data(), d.id)).toList());

    // Decors snapshot listener
    decorsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('aquarium')
        .doc('decor')
        .collection('placedDecors')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((d) => PlacedDecor.fromMap(d.data())).toList());
  }

  @override
  Widget build(BuildContext context) {
    final fishProvider = context.watch<FishProvider>();

    List<FishDefinition> unlockables = FishCatalog.all
        .where((fish) => fish.type == FishType.unlockable)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Milestones & Unlockables')),
      body: StreamBuilder<List<TaskModel>>(
          stream: tasksStream,
          builder: (context, taskSnapshot) {
            if (taskSnapshot.hasData) tasks = taskSnapshot.data!;
            return StreamBuilder<List<PlacedDecor>>(
              stream: decorsStream,
              builder: (context, decorSnapshot) {
                if (decorSnapshot.hasData) decors = decorSnapshot.data!;

                // Run unlock check on every update
                unlockManager.checkUnlocks();

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: unlockables.length,
                  itemBuilder: (context, index) {
                    final fish = unlockables[index];
                    final isOwned = fishProvider.isOwned(fish.id);

                    double progressPercent = _calculateProgressPercent(fish);
                    String progressText = _getProgressText(fish, progressPercent);

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            // Fish icon
                            Image.asset(
                              fish.storeIconAsset,
                              width: 60,
                              height: 60,
                              color: isOwned ? null : Colors.grey,
                            ),
                            const SizedBox(width: 12),

                            // Name + Description + Progress
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fish.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isOwned ? Colors.black : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    fish.description,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isOwned ? Colors.black : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progressPercent,
                                      minHeight: 10,
                                      backgroundColor: Colors.grey.shade300,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          isOwned ? Colors.green : Colors.blue),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    progressText,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isOwned ? Colors.green : Colors.grey),
                                  ),
                                ],
                              ),
                            ),

                            // Lock / check icon
                            Icon(
                              isOwned ? Icons.check_circle : Icons.lock,
                              color: isOwned ? Colors.green : Colors.grey,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          }),
    );
  }

  double _calculateProgressPercent(FishDefinition fish) {
    switch (fish.unlockConditionId) {
      case 'first_aquarium_visit':
        return child.ownedFish.isNotEmpty || child.placedDecors.isNotEmpty ? 1.0 : 0.0;

      case 'task_milestone_50':
        int totalCompleted = tasks.fold(0, (sum, t) => sum + t.totalDaysCompleted);
        bool streak50 = tasks.any((t) => t.activeStreak >= 50);
        return ((totalCompleted >= 50 || streak50) ? 1.0 : totalCompleted / 50).clamp(0.0, 1.0);

      case 'place_5_decor':
        int placed = decors.where((d) => d.isPlaced).length;
        return (placed / 5.0).clamp(0.0, 1.0);

      case 'complete_10_hard_tasks':
        int hardDone = tasks.where((t) => t.difficulty.toLowerCase() == 'hard' && t.isDone).length;
        return (hardDone / 10.0).clamp(0.0, 1.0);

      default:
        return 0.0;
    }
  }

  String _getProgressText(FishDefinition fish, double progress) {
    switch (fish.unlockConditionId) {
      case 'first_aquarium_visit':
        return progress == 1.0 ? 'Visited aquarium' : 'Visit aquarium';

      case 'task_milestone_50':
        int totalCompleted = tasks.fold(0, (sum, t) => sum + t.totalDaysCompleted);
        return '$totalCompleted / 50 tasks completed';

      case 'place_5_decor':
        int placed = decors.where((d) => d.isPlaced).length;
        return '$placed / 5 decors placed';

      case 'complete_10_hard_tasks':
        int hardDone = tasks.where((t) => t.difficulty.toLowerCase() == 'hard' && t.isDone).length;
        return '$hardDone / 10 hard tasks completed';

      default:
        return '';
    }
  }
}
