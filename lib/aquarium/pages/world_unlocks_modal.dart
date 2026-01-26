import 'package:brightbuds_new/aquarium/providers/progression_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/fish_catalog.dart';
import '../catalogs/decor_catalog.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';

class WorldUnlocksModal extends StatelessWidget {
  const WorldUnlocksModal({super.key});

  @override
  Widget build(BuildContext context) {
    final progression = context.watch<ProgressionProvider>();
    final state = progression.state;

    final currentWorld = state.world.worldId;
    final level = state.level;

    // Combine fish and decor into one list
    final combinedUnlocks = [
      ...FishCatalog.byWorld(currentWorld)
          .map((f) => _UnlockableItem(
                name: f.name,
                asset: f.normalAsset,
                unlocked: f.unlockLevel <= level,
                unlockLevel: f.unlockLevel,
                description: f.description,
              )),
      ...DecorCatalog.byWorld(currentWorld)
          .map((d) => _UnlockableItem(
                name: d.name,
                asset: d.assetPath,
                unlocked: d.unlockLevel <= level,
                unlockLevel: d.unlockLevel,
                description: d.description,
              )),
    ]..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

    final bool worldComplete =
        combinedUnlocks.every((u) => u.unlocked);

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${state.world.name} World',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Level $level',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...combinedUnlocks.map(
              (u) => _UnlockCard(
                name: u.name,
                asset: u.asset,
                unlocked: u.unlocked,
                unlockLevel: u.unlockLevel,
                description: u.description,
              ),
            ),

            const SizedBox(height: 32),

            _WorldCompletionFooter(
              unlockedCount:
                  combinedUnlocks.where((u) => u.unlocked).length,
              totalCount: combinedUnlocks.length,
              enabled: worldComplete,
              onNextWorld: () {
                // 🚧 Hook later when you add world switching
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Small helper class to combine unlockables
class _UnlockableItem {
  final String name;
  final String asset;
  final bool unlocked;
  final int unlockLevel;
  final String description;

  _UnlockableItem({
    required this.name,
    required this.asset,
    required this.unlocked,
    required this.unlockLevel,
    required this.description,
  });
}

class _UnlockCard extends StatelessWidget {
  final String name;
  final String asset;
  final bool unlocked;
  final int unlockLevel;
  final String description;

  const _UnlockCard({
    required this.name,
    required this.asset,
    required this.unlocked,
    required this.unlockLevel,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Opacity(
                  opacity: unlocked ? 1 : 0.3,
                  child: Image.asset(
                    asset,
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        unlocked
                            ? 'Unlocked at Level $unlockLevel'
                            : 'Unlocks at Level $unlockLevel',
                        style: TextStyle(
                          fontSize: 12,
                          color: unlocked
                              ? Colors.green
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 🔒 LOCK OVERLAY
          if (!unlocked)
            Positioned(
              top: 12,
              right: 12,
              child: Icon(
                Icons.lock,
                color: Colors.grey.shade500,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorldCompletionFooter extends StatelessWidget {
  final int unlockedCount;
  final int totalCount;
  final bool enabled;
  final VoidCallback onNextWorld;

  const _WorldCompletionFooter({
    required this.unlockedCount,
    required this.totalCount,
    required this.enabled,
    required this.onNextWorld,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'World Completion: $unlockedCount / $totalCount',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: enabled ? onNextWorld : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  enabled ? Colors.blue : Colors.grey.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text(
              enabled
                  ? 'Go to Next World'
                  : 'Unlock everything to proceed',
            ),
          ),
        ),
      ],
    );
  }
}
