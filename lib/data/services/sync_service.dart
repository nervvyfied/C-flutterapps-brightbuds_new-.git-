import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/repositories/user_repository.dart';
import '/data/repositories/task_repository.dart';
import '/data/repositories/streak_repository.dart';

class SyncService {
  final UserRepository _userRepo;
  final TaskRepository _taskRepo;
  final StreakRepository _streakRepo;

  SyncService(
      this._userRepo, this._taskRepo, this._streakRepo);

  /// Called on user login
  /// isParent: true for parent login, false for child login
  Future<void> syncOnLogin({
    String? uid,
    String? accessCode,
    required bool isParent,
  }) async {
    if (isParent) {
      if (uid == null) return;
      await _syncParent(uid);
    } else {
      if (accessCode == null) return;
      await _syncChild(accessCode);
    }
  }

  // ---------------- PARENT ----------------
  Future<void> _syncParent(String parentUid) async {
    // 1️⃣ Fetch parent profile
    final ParentUser? parent = await _userRepo.fetchParentAndCache(parentUid);
    if (parent == null) return;

    // 2️⃣ Fetch all children under this parent
    final List<ChildUser> children = await _userRepo.fetchChildrenAndCache(parentUid);

    // 3️⃣ Sync tasks per child
    for (var child in children) {
      await _taskRepo.pullChildTasks(parentUid, child.cid);       // Pull remote → merge into Hive
      await _taskRepo.pushPendingLocalChanges();       // Push any local changes
    }

    // 4️⃣ Optional: sync streaks/rewards if offline changes exist
    //await _streakRepo.pushPendingLocalChanges();
  }

  // ---------------- CHILD ----------------
  Future<void> _syncChild(String accessCode) async {
  final Map<String, dynamic>? result =
      await _userRepo.fetchParentAndChildByAccessCode(accessCode);
  if (result == null) return;

  final parent = result['parent'] as ParentUser?;
  final child = result['child'] as ChildUser?;

  if (parent == null || child == null) return;

  // Pull tasks using parent.uid + child.cid
  await _taskRepo.pullChildTasks(parent.uid, child.cid);
  await _taskRepo.pushPendingLocalChanges();
}


  // ---------------- GLOBAL SYNC ----------------
  /// Call this periodically or on connectivity regained
  Future<void> syncAllPendingChanges() async {
    await _taskRepo.pushPendingLocalChanges();
    //await _streakRepo.pushPendingLocalChanges();
  }
}
