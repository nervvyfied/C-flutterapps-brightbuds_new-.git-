import '/data/models/parent_model.dart';
import '/data/models/child_model.dart';
import '/data/models/therapist_model.dart';
import '/data/repositories/user_repository.dart';
import '/data/repositories/task_repository.dart';
import '/data/repositories/streak_repository.dart';
import '/data/repositories/journal_repository.dart';

class SyncService {
  final UserRepository _userRepo;
  final TaskRepository _taskRepo;
  // ignore: unused_field
  final StreakRepository _streakRepo;
  final JournalRepository _journalRepo;

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
    bool isTherapist = false,
  }) async {
    if (isTherapist) {
      if (uid == null) return;
      await _syncTherapist(uid);
      return;
    }

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

    for (final child in children) {
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

    await _taskRepo.pullChildTasks(parent.uid, child.cid);
    await _taskRepo.pushPendingLocalChanges();

    await _journalRepo.getMergedEntries(parent.uid, child.cid);
    await _journalRepo.pushPendingLocalChanges(parent.uid, child.cid);
  }

  // ---------------- THERAPIST ----------------
  Future<void> _syncTherapist(String therapistUid) async {
    // 1️⃣ Fetch therapist (optional cache)
    final TherapistUser? therapist =
        await _userRepo.fetchTherapistAndCache(therapistUid);
    if (therapist == null) return;

    // 2️⃣ Fetch all parents linked to this therapist
    final List<ParentUser> parents =
        await _userRepo.fetchParentsByTherapist(therapistUid);

    for (final parent in parents) {
      // 3️⃣ Fetch children under parent
      final children = await _userRepo.fetchChildren(parent.uid);

      for (final child in children) {
        // 🔒 Only sync children assigned to this therapist
        if (child.therapistUid != therapistUid) continue;

        // 🔹 Tasks
        await _taskRepo.pullChildTasks(parent.uid, child.cid);
        await _taskRepo.pushPendingLocalChanges();

        // 🔹 Journals (therapist reads + writes)
        await _journalRepo.getMergedEntries(parent.uid, child.cid);
        await _journalRepo.pushPendingLocalChanges(parent.uid, child.cid);
      }
    }
  }

  // ---------------- GLOBAL SYNC ----------------
  Future<void> syncAllPendingChanges({
    String? parentId,
    String? childId,
  }) async {
    await _taskRepo.pushPendingLocalChanges();

    if (parentId != null && childId != null) {
      await _journalRepo.pushPendingLocalChanges(parentId, childId);
    }

    // await _streakRepo.pushPendingLocalChanges();
  }
}
