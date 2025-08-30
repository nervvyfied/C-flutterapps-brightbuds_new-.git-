import '../repositories/task_repository.dart';
import '../repositories/user_repository.dart';

class SyncService {
  final UserRepository _userRepo = UserRepository();

  // Call on login: fetch user, pull tasks, push local
  Future<void> syncOnLogin(String uid, {required bool isParent}) async {
    await _userRepo.fetchUserAndCache(uid);
    if (isParent) {
      // parent: pull tasks they created
      //await _taskRepo.pullTasksForUser(uid, asParent: true);
    } else {
      // child: pull tasks assigned to them
      //await _taskRepo.pullTasksForUser(uid, asParent: false);
    }
    // push any local changes to Firestore
    //await _taskRepo.pushAllLocalToFirestore();
  }
}
