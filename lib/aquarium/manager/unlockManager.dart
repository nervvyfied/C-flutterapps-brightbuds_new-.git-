import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/fish_provider.dart';
import '../catalogs/fish_catalog.dart';
import '../models/fish_definition.dart';
import '/data/models/task_model.dart';
import '/data/models/child_model.dart';
import '../models/placedDecor_model.dart';
import '/providers/selected_child_provider.dart';

class UnlockManager {
  final FishProvider fishProvider;
  final UnlockNotifier unlockNotifier;
  final SelectedChildProvider selectedChildProvider;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  UnlockManager({
    required this.unlockNotifier,
    required this.fishProvider,
    required this.selectedChildProvider,
  });

  /// Call after relevant actions (task completed, decor placed, aquarium visited)
  Future<void> checkUnlocks() async {
    final child = fishProvider.currentChild;

    // Fetch tasks
    final tasksSnap = await firestore
        .collection('users')
        .doc(child.parentUid)
        .collection('children')
        .doc(child.cid)
        .collection('tasks')
        .get();

    List<TaskModel> tasks = tasksSnap.docs
        .map((d) => TaskModel.fromFirestore(d.data(), d.id))
        .toList();

    // Fetch decors from correct Firestore path
    final decorDoc = await firestore
      .collection('users')
      .doc(child.parentUid)
      .collection('children')
      .doc(child.cid)
      .collection('aquarium')
      .doc('decor')
      .get();

  List<PlacedDecor> decors = [];
  if (decorDoc.exists && decorDoc.data()?['placedDecors'] != null) {
    decors = (decorDoc.data()!['placedDecors'] as List)
        .map((d) => PlacedDecor.fromMap(d))
        .toList();
  }


    for (var fishDef in FishCatalog.all) {
      // Skip non-unlockable or already owned
      if (fishDef.type != FishType.unlockable || fishProvider.isOwned(fishDef.id)) {
        continue;
      }

      bool shouldUnlock = false;

      if (fishDef.unlockConditionId == 'first_aquarium_visit') {
        final childDoc =
            await firestore.collection("children").doc(child.cid).get();
        bool firstVisit = childDoc.data()?['firstVisitUnlocked'] ?? false;

        if (!firstVisit) {
          // Mark first visit as unlocked
          await childDoc.reference.update({'firstVisitUnlocked': true});
          child.firstVisitUnlocked = true; // update local object
          selectedChildProvider.updateSelectedChild({'firstVisitUnlocked': true});
          shouldUnlock = true;
        }
      } else {
        shouldUnlock = _isConditionMet(fishDef.unlockConditionId, child, tasks, decors);
      }

      if (shouldUnlock) {
        await fishProvider.unlockFish(fishDef.id);
        unlockNotifier.setUnlocked(fishDef);
      }
    }
  }

  bool _isConditionMet(String conditionId, ChildUser child, List<TaskModel> tasks, List<PlacedDecor> decors) {
    switch (conditionId) {
      case 'task_milestone_50':
        int totalCompleted = tasks.fold(0, (sum, t) => sum + t.totalDaysCompleted);
        bool streak50 = tasks.any((t) => t.activeStreak >= 50);
        return totalCompleted >= 50 || streak50;

      case 'place_5_decor':
        int placedCount = decors.where((d) => d.isPlaced).length;
        return placedCount >= 5;

      case 'complete_10_hard_tasks':
        int hardDone = tasks
            .where((t) => t.difficulty.toLowerCase() == 'Hard' && t.isDone)
            .length;
        return hardDone >= 10;

      default:
        return false;
    }
  }
}
