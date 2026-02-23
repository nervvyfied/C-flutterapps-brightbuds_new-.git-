import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../catalogs/fish_catalog.dart';
import '../catalogs/decor_catalog.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';
import '../progression/world_progression.dart';
import '../providers/progression_provider.dart';

/// ===============================================================
/// 🎮 WORLD UNLOCKS MODAL (FINAL GAME-STYLE VERSION)
/// ===============================================================
///
/// 🔥 Improvements:
/// 1. Levels now grow BOTTOM → TOP (like Candy Crush)
/// 2. Auto-scroll starts at bottom
/// 3. "YOU ARE HERE" marker added
/// 4. World navigation separated:
///      ⬆ Visit Next World (top)
///      ⬇ Visit Previous World (bottom)
/// 5. Cleaner progression psychology
///

class WorldUnlocksModal extends StatefulWidget {
  final void Function(List<FishDefinition>, List<DecorDefinition>)
      onWorldChange;

  const WorldUnlocksModal({
    super.key,
    required this.onWorldChange,
  });

  @override
  State<WorldUnlocksModal> createState() =>
      _WorldUnlocksModalState();
}

class _WorldUnlocksModalState
    extends State<WorldUnlocksModal> {
  final ScrollController _scrollController =
      ScrollController();

  @override
  void initState() {
    super.initState();

    /// Auto-scroll to bottom after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progression =
        context.watch<ProgressionProvider>();
    final state = progression.state;

    final level = state.level;
    final currentWorld = state.world.worldId;

    // Determine the start levels for the current world
    // This assumes Worlds.all contains a startLevel property for each world
    final worldStartLevel = state.world.startLevel; // e.g., 1 for Aquarium, 13 for next world

    // Build the unlockable list
    final combinedUnlocks = [

      /// 1️⃣ Add World Start Node for current world
      _UnlockableItem(
        name: "New World",
        asset: "", // no asset for start node
        unlocked: true,
        unlockLevel: worldStartLevel,
        isWorldStart: true,
      ),

      /// 2️⃣ Add all fish in the world
      ...FishCatalog.byWorld(currentWorld).map(
        (f) => _UnlockableItem(
          name: f.name,
          asset: f.normalAsset,
          unlocked: f.unlockLevel <= level,
          unlockLevel: f.unlockLevel,
        ),
      ),

      /// 3️⃣ Add all decor in the world
      ...DecorCatalog.byWorld(currentWorld).map(
        (d) => _UnlockableItem(
          name: d.name,
          asset: d.assetPath,
          unlocked: d.unlockLevel <= level,
          unlockLevel: d.unlockLevel,
        ),
      ),
    ]
        // 4️⃣ Sort by unlockLevel ascending
        ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));


    /// 🔥 Reverse order (bottom → top climb)
    final reversedUnlocks =
        combinedUnlocks.reversed.toList();

    /// Determine highest unlocked level
    final currentLevel = state.level;

    final currentIndex = reversedUnlocks.indexWhere(
      (item) => item.unlockLevel == currentLevel,
    );


    final worldComplete =
        combinedUnlocks.every((u) => u.unlocked);

    return Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: Scaffold(
        backgroundColor: const Color(0xFFEAF6FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                '${state.world.name} World',
                style: const TextStyle(
                    fontWeight: FontWeight.bold),
              ),
              Text(
                'Level $level',
                style:
                    const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),

        body: Column(
          children: [

            /// ===================================================
            /// ⬆ VISIT NEXT WORLD (TOP)
            /// ===================================================
            _VisitNextWorldButton(
              worldComplete: worldComplete,
              onWorldChange: widget.onWorldChange,
            ),

            /// ===================================================
            /// 🎮 CANDY MAP SCROLL AREA
            /// ===================================================
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Stack(
                  children: [

                    /// Curved background path
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PathPainter(),
                      ),
                    ),

                    Column(
                      children: List.generate(
                        reversedUnlocks.length,
                        (index) {
                          final item =
                              reversedUnlocks[index];

                          return _LevelNode(
                            item: item,
                            isLeft:
                                index % 2 == 0,
                            isCurrent:
                                index ==
                                    currentIndex,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// ===================================================
            /// ⬇ VISIT PREVIOUS WORLD (BOTTOM)
            /// ===================================================
            _VisitPreviousWorldButton(
              onWorldChange:
                  widget.onWorldChange,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// 🍬 LEVEL NODE
/// ===============================================================

class _LevelNode extends StatelessWidget {
  final _UnlockableItem item;
  final bool isLeft;
  final bool isCurrent;

  const _LevelNode({
    required this.item,
    required this.isLeft,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment:
          isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(
            vertical: 40, horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            /// ✅ Marker ABOVE bubble (no clipping)
            if (isCurrent)
              Column(
                children: [
                  const Icon(
                    Icons.arrow_drop_down,
                    size: 30,
                    color: Colors.orange,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "YOU ARE HERE",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),

            /// Bubble Stack
              Stack(
                alignment: Alignment.center,
                children: [

                  /// WORLD START NODE
                  if (item.isWorldStart)
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.amber.shade400,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.5),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        "New World",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )

                  /// NORMAL UNLOCKABLE NODE
                  else
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: item.unlocked
                            ? const LinearGradient(
                                colors: [
                                  Color(0xFF6EC6FF),
                                  Color(0xFF1E88E5)
                                ],
                              )
                            : null,
                        color: item.unlocked ? null : Colors.grey.shade300,
                        boxShadow: item.unlocked
                            ? [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 16,
                                )
                              ]
                            : [],
                      ),
                      child: Opacity(
                        opacity: item.unlocked ? 1 : 0.4,
                        child: Image.asset(
                          item.asset,
                          width: 50,
                          height: 50,
                        ),
                      ),
                    ),

                  if (!item.unlocked && !item.isWorldStart)
                    const Icon(Icons.lock, color: Colors.white),
                ],
              ),

            const SizedBox(height: 8),

            Text(
              "Level ${item.unlockLevel}",
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// 🌀 CURVED PATH
/// ===============================================================

class _PathPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.shade200
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width / 2, 0);

    for (double i = 0;
        i < size.height;
        i += 160) {
      path.quadraticBezierTo(
        size.width *
            (i % 320 == 0 ? 0.2 : 0.8),
        i + 80,
        size.width / 2,
        i + 160,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
          CustomPainter oldDelegate) =>
      false;
}

/// ===============================================================
/// ⬆ VISIT NEXT WORLD
/// ===============================================================

class _VisitNextWorldButton
    extends StatelessWidget {
  final bool worldComplete;
  final void Function(
          List<FishDefinition>,
          List<DecorDefinition>)
      onWorldChange;

  const _VisitNextWorldButton({
    required this.worldComplete,
    required this.onWorldChange,
  });

  @override
  Widget build(BuildContext context) {
    final progression =
        context.watch<ProgressionProvider>();
    final state = progression.state;

    final index =
        Worlds.all.indexOf(state.world);
    final hasNext =
        index < Worlds.all.length - 1;

    final nextWorld =
        hasNext ? Worlds.all[index + 1] : null;

    final canVisit =
        hasNext && worldComplete;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ElevatedButton.icon(
        onPressed: canVisit
            ? () {
                progression.visitWorld(
                    nextWorld!.worldId);
                onWorldChange(
                  progression
                      .state.unlockedFish,
                  progression
                      .state.unlockedDecor,
                );
              }
            : null,
        icon: const Icon(Icons.arrow_upward),
        label: Text(
          hasNext
              ? canVisit
                  ? "Visit ${nextWorld!.name}"
                  : "Complete this world to unlock"
              : "Final World",
        ),
      ),
    );
  }
}

/// ===============================================================
/// ⬇ VISIT PREVIOUS WORLD
/// ===============================================================

class _VisitPreviousWorldButton
    extends StatelessWidget {
  final void Function(
          List<FishDefinition>,
          List<DecorDefinition>)
      onWorldChange;

  const _VisitPreviousWorldButton({
    required this.onWorldChange,
  });

  @override
Widget build(BuildContext context) {
  final progression = context.watch<ProgressionProvider>();
  final state = progression.state;

  final currentIndex = Worlds.all.indexOf(state.world);
  final hasPrevious = currentIndex > 0;

  // Only show the button if there is a previous world
  if (!hasPrevious) {
    return const SizedBox.shrink(); // renders nothing
  }

  final previousWorld = Worlds.all[currentIndex - 1];

  return Padding(
    padding: const EdgeInsets.all(12),
    child: ElevatedButton.icon(
      onPressed: () {
        progression.visitWorld(previousWorld.worldId);
        onWorldChange(
          progression.state.unlockedFish,
          progression.state.unlockedDecor,
        );
      },
      icon: const Icon(Icons.arrow_downward),
      label: Text("Visit ${previousWorld.name}"),
    ),
  );
}
}

/// Helper model
class _UnlockableItem {
  final String name;
  final String asset;
  final bool unlocked;
  final int unlockLevel;
  final bool isWorldStart; // NEW

  _UnlockableItem({
    required this.name,
    required this.asset,
    required this.unlocked,
    required this.unlockLevel,
    this.isWorldStart = false,
  });
}

