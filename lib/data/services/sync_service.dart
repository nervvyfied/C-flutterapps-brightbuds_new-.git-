import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/repositories/user_repository.dart';
import '/data/repositories/task_repository.dart';
import '/data/repositories/streak_repository.dart';
import '/data/repositories/journal_repository.dart';

class SyncService {
  final UserRepository _userRepo;
  final TaskRepository _taskRepo;
  // ignore: unused_field
  final StreakRepository _streakRepo;
  final JournalRepository _journalRepo; // internal instance

  SyncService(
    this._userRepo,
    this._taskRepo,
    this._streakRepo,
  ) : _journalRepo = JournalRepository();

  /// Called on user login
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
    final ParentUser? parent = await _userRepo.fetchParentAndCache(parentUid);
    if (parent == null) return;

    final List<ChildUser> children =
        await _userRepo.fetchChildrenAndCache(parentUid);

    for (var child in children) {
      // 🔹 Tasks only
      await _taskRepo.pullChildTasks(parentUid, child.cid);
      await _taskRepo.pushPendingLocalChanges();
    }
  }

  // ---------------- CHILD ----------------
  Future<void> _syncChild(String accessCode) async {
    final Map<String, dynamic>? result =
        await _userRepo.fetchParentAndChildByAccessCode(accessCode);
    if (result == null) return;

    final parent = result['parent'] as ParentUser?;
    final child = result['child'] as ChildUser?;
    if (parent == null || child == null) return;

    // 🔹 Tasks
    await _taskRepo.pullChildTasks(parent.uid, child.cid);
    await _taskRepo.pushPendingLocalChanges();

    // 🔹 Journals
    await _journalRepo.getMergedEntries(parent.uid, child.cid);
    await _journalRepo.pushPendingLocalChanges(parent.uid, child.cid);
  }

  // ---------------- GLOBAL SYNC ----------------
  Future<void> syncAllPendingChanges({String? parentId, String? childId}) async {
    await _taskRepo.pushPendingLocalChanges();

    // Only push journal changes if childId is provided
    if (parentId != null && childId != null) {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    }

    // Streaks optional
    // await _streakRepo.pushPendingLocalChanges();
  }
}
