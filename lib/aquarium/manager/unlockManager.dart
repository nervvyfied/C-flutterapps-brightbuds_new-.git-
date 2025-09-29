import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../providers/fish_provider.dart';
import '../catalogs/fish_catalog.dart';
import '../models/fish_definition.dart';
import '/data/models/task_model.dart';
import '/data/models/child_model.dart';
import '../models/placedDecor_model.dart';

class UnlockManager {
  final FishProvider fishProvider;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final UnlockNotifier unlockNotifier;

  UnlockManager(this.unlockNotifier, {required this.fishProvider});

  /// Call after relevant actions (task completed, decor placed, aquarium visited)
  Future<void> checkUnlocks() async {
    final child = fishProvider.currentChild;

    // Fetch latest tasks & decors from Firestore
    final tasksSnap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('tasks')
        .get();

    final decorsSnap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('aquarium')
        .doc('decor')
        .collection('placedDecors')
        .get();

    List<TaskModel> tasks = tasksSnap.docs
        .map((d) => TaskModel.fromFirestore(d.data(), d.id))
        .toList();

    List<PlacedDecor> decors = decorsSnap.docs
        .map((d) => PlacedDecor.fromMap(d.data()))
        .toList();

    for (var fishDef in FishCatalog.all) {
      if (fishDef.type == FishType.unlockable && !fishProvider.isOwned(fishDef.id)) {
        if (_isConditionMet(fishDef.unlockConditionId, child, tasks, decors)) {
          await fishProvider.unlockFish(fishDef.id);
          debugPrint('${fishDef.name} unlocked!');

          unlockNotifier.notifyUnlock(fishDef);
        }
      }
    }
  }

  bool _isConditionMet(String conditionId, ChildUser child, List<TaskModel> tasks, List<PlacedDecor> decors) {
    switch (conditionId) {
      case 'first_aquarium_visit':
        // Track first visit via a local flag or a field in Firestore
        return child.ownedFish.isNotEmpty || child.placedDecors.isNotEmpty;

      case 'task_milestone_50':
        int totalCompleted = tasks.fold(0, (sum, t) => sum + t.totalDaysCompleted);
        bool streak50 = tasks.any((t) => t.activeStreak >= 50);
        return totalCompleted >= 50 || streak50;

      case 'place_5_decor':
        int placedCount = decors.where((d) => d.isPlaced).length;
        return placedCount >= 5;

      case 'complete_10_hard_tasks':
        int hardDone = tasks.where((t) => t.difficulty.toLowerCase() == 'hard' && t.isDone).length;
        return hardDone >= 10;

      default:
        return false;
    }
  }
}
