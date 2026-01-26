// ignore_for_file: use_build_context_synchronously
import 'package:brightbuds_new/aquarium/models/fish_definition.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockDialog.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UnlockListener extends StatelessWidget {
  final Widget child;

  const UnlockListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<UnlockNotifier>(
      builder: (context, unlockNotifier, _) {
        final unlockedItem = unlockNotifier.current;
        debugPrint('UnlockListener sees: $unlockedItem'); // 🔍
        if (unlockedItem != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showUnlockDialog(context, unlockedItem);
          });
        }
        return child;
      },
    );
  }

  void _showUnlockDialog(BuildContext context, dynamic unlockedItem) {
  final unlockNotifier = context.read<UnlockNotifier>();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => UnlockDialog(unlockedItem: unlockedItem),
  ).then((_) {
    // Clear after showing dialog
    unlockNotifier.clearCurrent();
  });
}

}
