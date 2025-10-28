import 'package:brightbuds_new/aquarium/manager/token_manager.dart';
import 'package:flutter/material.dart';
import 'package:brightbuds_new/data/models/task_model.dart';

class TokenNotifier extends ChangeNotifier {
  final TokenManager manager;
  List<TaskModel> newTasks = [];

  TokenNotifier(this.manager);

  void checkAndNotify() {
    final tokens = manager.checkNewTokens();
    if (tokens.isNotEmpty) {
      newTasks = tokens;
      notifyListeners();
    }
  }
}
