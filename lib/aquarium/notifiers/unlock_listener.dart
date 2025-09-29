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
        if (unlockNotifier.lastUnlocked != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showUnlockDialog(context, unlockNotifier.lastUnlocked!);
          });
        }
        return child;
      },
    );
  }

  void _showUnlockDialog(BuildContext context, FishDefinition fish) {
    final unlockNotifier = context.read<UnlockNotifier>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('New Unlock! 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(fish.storeIconAsset, width: 80, height: 80),
            const SizedBox(height: 12),
            Text('You unlocked ${fish.name}!', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(fish.description, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              unlockNotifier.clear();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              unlockNotifier.clear();
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/unlockables');
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }
}
