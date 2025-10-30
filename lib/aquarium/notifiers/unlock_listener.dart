// ignore_for_file: use_build_context_synchronously

import 'package:brightbuds_new/aquarium/notifiers/unlockDialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/aquarium/models/fish_definition.dart';
import 'unlockNotifier.dart'; // make sure this exists

class UnlockListener extends StatelessWidget {
  final Widget child;
  const UnlockListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<UnlockNotifier>(
      builder: (context, unlockNotifier, _) {
        if (unlockNotifier.justUnlocked != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showUnlockDialog(context, unlockNotifier.justUnlocked!);
          });
        }
        return child;
      },
    );
  }

  void _showUnlockDialog(BuildContext context, FishDefinition fish) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => UnlockDialog(fish: fish),
  ).then((_) {
    // Clear the notifier after dialog is dismissed
    context.read<UnlockNotifier>().clear();
  });
}


}
