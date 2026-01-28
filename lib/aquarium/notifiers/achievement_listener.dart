import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../notifiers/achievement_notifier.dart';
import 'achievement_dialog.dart';
import '../models/achievement_definition.dart';

class AchievementListener extends StatelessWidget {
  final Widget child;
  const AchievementListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AchievementNotifier>(
      builder: (context, achievementNotifier, _) {
        if (achievementNotifier.justUnlocked != null &&
          ModalRoute.of(context)?.isCurrent == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showAchievementDialog(context, achievementNotifier.justUnlocked!);
          });
        }
        return child;
      },
    );
  }

  void _showAchievementDialog(BuildContext context, AchievementDefinition achievement) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AchievementDialog(achievement: achievement),
    ).then((_) {
      context.read<AchievementNotifier>().clear();
    });
  }
}
