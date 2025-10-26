import 'dart:async';
import 'dart:math';
import 'package:brightbuds_new/aquarium/catalogs/fish_catalog.dart';
import 'package:brightbuds_new/aquarium/manager/unlockManager.dart';
import 'package:brightbuds_new/aquarium/models/fish_definition.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockDialog.dart';
import 'package:brightbuds_new/aquarium/notifiers/unlockNotifier.dart';
import 'package:brightbuds_new/aquarium/pages/inventory_modal.dart';
import 'package:brightbuds_new/aquarium/pages/store_page.dart';
import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/aquarium/providers/fish_provider.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:brightbuds_new/aquarium/pages/aquarium_tutorial_modal.dart';
import 'package:brightbuds_new/aquarium/manager/tutorial_manager.dart';

// ----- Bubble Class -----
class Bubble {
  double x;
  double y;
  double size;
  double speed;
  String asset;

  Bubble({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.asset,
  });
}

class AquariumFish {
  final FishDefinition definition;
  double x;
  double y;
  double speed;
  bool movingRight;
  double verticalOffset;
  double sineFrequency;
  bool neglected;

  AquariumFish({
    required this.definition,
    required this.x,
    required this.y,
    required this.speed,
    required this.movingRight,
    required this.verticalOffset,
    required this.sineFrequency,
    this.neglected = false,
  });

  String get currentAsset =>
      neglected ? definition.neglectedAsset : definition.normalAsset;
}

// ----- Dirt Class -----
class Dirt {
  double x;
  double y;
  String asset;
  double opacity;

  Dirt({
    required this.x,
    required this.y,
    required this.asset,
    this.opacity = 1.0,
  });
}

// ----- Food Pellet Class -----
class FoodPellet {
  double x;
  double y;
  double speed;
  FoodPellet({required this.x, required this.y, this.speed = 3});
}

class AquariumPage extends StatefulWidget {
  const AquariumPage({super.key});

  @override
  State<AquariumPage> createState() => _AquariumPageState();
}

class _AquariumPageState extends State<AquariumPage>
    with TickerProviderStateMixin {
  double offsetX = 0.0;
  late AnimationController _controller;
  late Animation<double> _animation;
  late AnimationController _animController;
  int _foodPelletCountDuringDrag = 0;

  final Map<String, double> parallax = {
    'sand_bg': 0.2,
    'sand1': 0.5,
    'sand2': 0.8,
  };

  late double maxOffsetSandBg;
  late double maxOffsetSand1;
  late double maxOffsetSand2;
  DecorProvider get decorProvider => context.watch<DecorProvider>();

  final Random random = Random();

  List<Bubble> bubbles = [];
  List<AquariumFish> fishes = [];
  List<Dirt> dirts = [];
  List<FoodPellet> foodPellets = [];

  Timer? _foodDragTimer;
  Offset? _lastDragPosition;
  // ignore: unused_field
  Timer? _tankDirtTimer;

  // Dummy child data for top-right display
  double childBalance = 0;
  List<bool> fishAchievements = [true, false, false]; // true = unlocked

  bool _isDraggingFood = false;
  bool _isDraggingSponge = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final selectedChildProvider = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );
      final fishProvider = Provider.of<FishProvider>(context, listen: false);
      final unlockNotifier = Provider.of<UnlockNotifier>(
        context,
        listen: false,
      );

      final unlockManager = UnlockManager(
        fishProvider: fishProvider,
        unlockNotifier: unlockNotifier,
        selectedChildProvider: selectedChildProvider,
      );

      final justUnlocked = unlockNotifier.justUnlocked;
      if (justUnlocked != null) {
        unlockNotifier.clear(); // clear first to prevent repeated triggers
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => UnlockDialog(fish: justUnlocked),
        );
      }

      if (auth.currentUserModel is ChildUser) {
        final child = auth.currentUserModel as ChildUser;

        // Update local balance
        setState(() {
          childBalance = child.balance.toDouble();
        });

        // --- FIRST VISIT LOGIC ---
        final childDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(child.parentUid)
            .collection('children')
            .doc(child.cid)
            .get();

        bool firstVisitUnlocked =
            childDoc.data()?['firstVisitUnlocked'] ?? false;

        if (!firstVisitUnlocked) {
          // Unlock fish in provider first
          final firstFish = FishCatalog.all.firstWhere(
            (f) => f.unlockConditionId == "first_aquarium_visit",
          );
          await fishProvider.unlockFish(firstFish.id);

          // Update Firestore
          await childDoc.reference.update({'firstVisitUnlocked': true});

          // Update local selectedChildProvider state
          selectedChildProvider.updateSelectedChild({
            'firstVisitUnlocked': true,
          });
          child.firstVisitUnlocked = true;

          await Future.delayed(Duration(milliseconds: 100));

          // Trigger UnlockNotifier (will show popup + glow)
          unlockNotifier.setUnlocked(firstFish);
        }

        // --- OTHER UNLOCKABLES ---
        final unlockedFish = await unlockManager.checkUnlocks();

        if (unlockedFish.isNotEmpty && mounted) {
          for (var fish in unlockedFish) {
            unlockNotifier.setUnlocked(fish);
            await Future.delayed(const Duration(milliseconds: 400));
            if (!mounted) break;
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => UnlockDialog(fish: fish),
            );
          }
        }

        final childId = child.cid; // already have child
        await _maybeShowTutorial();
      }

      // Initialize aquarium visuals, bubbles, etc.
      _initBubbles();
      _initDirts();
      _animateBubbles();
      _animateFishes();
      _animateFoodPellets();
      _startNeglectTimer();
      _startTankDirtTimer();
    });
  }

  Future<void> _maybeShowTutorial() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final selectedChildProvider = Provider.of<SelectedChildProvider>(
      context,
      listen: false,
    );

    String? parentId;
    String? childId;

    // Determine which user we’re dealing with
    if (auth.currentUserModel is ChildUser) {
      final child = auth.currentUserModel as ChildUser;
      parentId = child.parentUid;
      childId = child.cid;
    } else if (selectedChildProvider.selectedChild != null) {
      final child = selectedChildProvider.selectedChild!;
      // since this is a Map<String, dynamic>
      parentId = child['parentUid'];
      childId = child['cid'];
    }

    if (parentId == null || childId == null) return;

    final seen = await AquariumTutorial.hasSeenTutorial(
      parentId: parentId,
      childId: childId,
    );

    if (seen || !mounted) return;

    await Future.delayed(const Duration(milliseconds: 400));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AquariumTutorialModal(
        onComplete: () async {
          await AquariumTutorial.markTutorialSeen(
            parentId: parentId!,
            childId: childId!,
          );
        },
      ),
    );
  }

  void _startNeglectTimer() {
    Future.delayed(const Duration(minutes: 1), () async {
      if (!mounted) return;

      final fishProvider = Provider.of<FishProvider>(context, listen: false);

      // collect affected fish definitions to persist after setState
      final List<String> toPersist = [];

      setState(() {
        for (var fish in fishes) {
          if (!fish.neglected) {
            fish.neglected = true;
            toPersist.add(fish.definition.id);
          }
        }
      });

      // persist neglected state (no need to await sequentially; fire-and-forget is OK)
      for (var defId in toPersist) {
        fishProvider.setNeglected(defId, true);
      }

      _startNeglectTimer();
    });
  }

  void _startTankDirtTimer() {
    _tankDirtTimer = Timer.periodic(const Duration(hours: 1), (_) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;

      setState(() {
        final dirtAssets = [
          'assets/particles/dirt1.png',
          'assets/particles/dirt2.png',
          'assets/particles/dirt3.png',
          'assets/particles/dirt4.png',
          'assets/particles/dirt5.png',
        ];
        for (int i = 0; i < 5; i++) {
          dirts.add(
            Dirt(
              x: random.nextDouble() * screenWidth,
              y: random.nextDouble() * screenHeight * 0.7,
              asset: dirtAssets[random.nextInt(dirtAssets.length)],
            ),
          );
        }
      });
    });
  }

  // ----- Initialize Bubbles -----
  void _initBubbles() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    for (int i = 0; i < 20; i++) {
      final bubbleTypes = [
        {'asset': 'assets/particles/bubble_s.png', 'size': 20.0, 'speed': 1.0},
        {'asset': 'assets/particles/bubble_m.png', 'size': 30.0, 'speed': 1.5},
        {'asset': 'assets/particles/bubble_l.png', 'size': 50.0, 'speed': 2.0},
      ];
      final type = bubbleTypes[random.nextInt(bubbleTypes.length)];

      bubbles.add(
        Bubble(
          x: random.nextDouble() * screenWidth,
          y: screenHeight - random.nextDouble() * 150,
          size: type['size']! as double,
          speed: type['speed']! as double,
          asset: type['asset']! as String,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fishProvider = Provider.of<FishProvider>(context);

    // Update fishes whenever activeFishes changes
    setState(() {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      fishes = fishProvider.activeFishes.map((owned) {
        final def = FishCatalog.byId(owned.fishId);
        return AquariumFish(
          definition: def,
          x: random.nextDouble() * screenWidth,
          y: screenHeight * 0.3 + random.nextDouble() * screenHeight * 0.4,
          speed: 1 + random.nextDouble() * 2,
          movingRight: random.nextBool(),
          verticalOffset: random.nextDouble() * 20,
          sineFrequency: 0.01 + random.nextDouble() * 0.02,
          neglected: owned.isNeglected,
        );
      }).toList();
    });
  }

  // ----- Initialize Dirts -----
  void _initDirts() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dirtAssets = [
      'assets/particles/dirt1.png',
      'assets/particles/dirt2.png',
      'assets/particles/dirt3.png',
      'assets/particles/dirt4.png',
      'assets/particles/dirt5.png',
    ];

    for (int i = 0; i < 10; i++) {
      dirts.add(
        Dirt(
          x: random.nextDouble() * screenWidth,
          y: random.nextDouble() * screenHeight * 0.7,
          asset: dirtAssets[random.nextInt(dirtAssets.length)],
        ),
      );
    }
  }

  // ----- Animate Bubbles -----
  void _animateBubbles() {
    Future.delayed(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      setState(() {
        final screenHeight = MediaQuery.of(context).size.height;
        for (var bubble in bubbles) {
          bubble.y -= bubble.speed;
          if (bubble.y + bubble.size < 0) {
            bubble.y = screenHeight;
            bubble.x = random.nextDouble() * MediaQuery.of(context).size.width;
          }
        }
      });
      _animateBubbles();
    });
  }

  // ----- Animate Fishes -----
  void _animateFishes() {
    Future.delayed(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      setState(() {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        final double maxY = screenHeight * 0.6;

        for (var fish in fishes) {
          // Check if there is a nearby food pellet
          if (foodPellets.isNotEmpty) {
            FoodPellet closestPellet = foodPellets.reduce(
              (a, b) =>
                  (sqrt(pow(fish.x - a.x, 2) + pow(fish.y - a.y, 2)) <
                      sqrt(pow(fish.x - b.x, 2) + pow(fish.y - b.y, 2)))
                  ? a
                  : b,
            );

            // Move fish towards pellet
            double dx = closestPellet.x - fish.x;
            double dy = closestPellet.y - fish.y;
            double distance = sqrt(dx * dx + dy * dy);

            if (distance < 5) {
              foodPellets.remove(closestPellet);
              _foodPelletCountDuringDrag = max(
                0,
                _foodPelletCountDuringDrag - 1,
              );
              _resetFishesHealth();
            } else {
              fish.x += dx / distance * fish.speed;
              fish.y += dy / distance * fish.speed;
            }
          } else {
            // Normal movement
            if (!fish.neglected) {
              fish.x += fish.movingRight ? fish.speed : -fish.speed;
              if (fish.x < 0) fish.movingRight = true;
              if (fish.x > screenWidth - 50) fish.movingRight = false;
              fish.y += sin(fish.x * fish.sineFrequency) * 0.5;
            } else {
              fish.x += fish.movingRight ? 0.5 : -0.5;
              if (fish.x < 0) fish.movingRight = true;
              if (fish.x > screenWidth - 50) fish.movingRight = false;
              fish.y += sin(fish.x * fish.sineFrequency) * 0.2;
            }
          }
          fish.y = min(fish.y, maxY);
        }
      });
      _animateFishes();
    });
  }

  // ----- Animate Food Pellets -----
  void _animateFoodPellets() {
    Future.delayed(const Duration(milliseconds: 16), () {
      if (!mounted) return;
      setState(() {
        final screenHeight = MediaQuery.of(context).size.height;
        for (var pellet in foodPellets) {
          pellet.y += pellet.speed;
        }
        foodPellets.removeWhere((p) => p.y > screenHeight);
      });
      _animateFoodPellets();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      offsetX += details.delta.dx;
      offsetX = offsetX.clamp(-maxOffsetSand2, maxOffsetSand2);
    });
  }

  void _onDragEnd() {
    _animation = Tween<double>(
      begin: offsetX,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.reset();
    _controller.forward();
    _animation.addListener(() {
      setState(() {
        offsetX = _animation.value;
      });
    });
  }

  // ----- Feed Fish -----
  void _spawnFoodPellet(Offset globalPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);

    final screenHeight = MediaQuery.of(context).size.height;
    final double maxY = screenHeight * 0.6; // only allow top 60% of screen

    foodPellets.add(
      FoodPellet(
        x: localPosition.dx,
        y: min(localPosition.dy, maxY), // clamp Y position
        speed: 2.5,
      ),
    );

    _foodPelletCountDuringDrag++;
    if (_foodPelletCountDuringDrag >= fishes.length) {
      _resetFishesHealth();
    }

    setState(() {});
  }

  void _onFoodDragStarted(DragStartDetails details) {
    _lastDragPosition = details.globalPosition;
    _foodPelletCountDuringDrag = 0;

    _foodDragTimer?.cancel();
    _foodDragTimer = Timer.periodic(
      Duration(milliseconds: 500 + random.nextInt(500)),
      (_) {
        if (_lastDragPosition != null) _spawnFoodPellet(_lastDragPosition!);
      },
    );
  }

  void _onFoodDragUpdate(DragUpdateDetails details) {
    _lastDragPosition = details.globalPosition;
  }

  void _onFoodDragEnd(DraggableDetails details) {
    _stopFoodDragTimer();
    _lastDragPosition = null;
    _foodPelletCountDuringDrag = 0;
  }

  void _resetFishesHealth() {
    final fishProvider = Provider.of<FishProvider>(context, listen: false);
    final previouslyNeglected = fishes.where((f) => f.neglected).toList();
    if (previouslyNeglected.isEmpty) return;

    setState(() {
      for (var fish in previouslyNeglected) fish.neglected = false;
    });

    for (var fish in previouslyNeglected) {
      fishProvider.setNeglected(fish.definition.id, false);
    }
  }

  void _stopFoodDragTimer() {
    _foodDragTimer?.cancel();
    _foodDragTimer = null;
  }

  // ----- Clean Dirt -----
  void _cleanDirt(Offset globalPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);

    setState(() {
      for (var dirt in dirts) {
        final dx = (dirt.x - localPosition.dx).abs();
        final dy = (dirt.y - localPosition.dy).abs();
        if (dx < 50 && dy < 50) {
          dirt.opacity -= 0.05;
          if (dirt.opacity <= 0) dirt.opacity = 0;
        }
      }
    });
  }

  void dispose() {
    decorProvider.saveEditMode(); // final sync in case some moves are unsaved
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // ignore: unused_local_variable
    final screenHeight = MediaQuery.of(context).size.height;
    final decorProvider = Provider.of<DecorProvider>(context);
    final itemsToRender = decorProvider.isInEditMode
        ? decorProvider.editingDecors
        : decorProvider.placedDecors.where((d) => d.isPlaced).toList();

    final double sandBgWidth = screenWidth * 1.2;
    final double sand1Width = screenWidth * 1.4;
    final sand2Width = screenWidth * 1.6;

    maxOffsetSandBg = (sandBgWidth - screenWidth) / 2;
    maxOffsetSand1 = (sand1Width - screenWidth) / 2;
    maxOffsetSand2 = (sand2Width - screenWidth) / 2;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: (_) => _onDragEnd(),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Image.asset(
                  'assets/tank/water_bg.png',
                  fit: BoxFit.cover,
                ),
              ),
              _buildLayer(
                'assets/tank/sand_bg.png',
                sandBgWidth,
                offsetX * parallax['sand_bg']!,
              ),
              _buildLayer(
                'assets/tank/sand1.png',
                sand1Width,
                offsetX * parallax['sand1']!,
              ),

              // ----- Placed Decors (above sand1, behind sand2) -----
              // Determine which list to render: edit buffer if editing, otherwise persisted placed items

              // ----- Placed Decors / Edit Mode -----
              Stack(
                children: [
                  // ----- Placed Decors -----
                  ...itemsToRender.map((decor) {
                    final decorDef = decorProvider.getDecorDefinition(
                      decor.decorId,
                    );
                    // ignore: dead_code, unnecessary_null_comparison
                    if (decorDef == null) return const SizedBox();

                    final double displayW = decor.isPlaced ? 120 : 80;
                    final double displayH = decor.isPlaced ? 120 : 80;

                    final isSelected = decorProvider.isDecorSelected(decor.id);
                    final isMoving = decorProvider.movingDecorId == decor.id;

                    // compute parallax-ed screen position
                    final left = decor.x + offsetX * parallax['sand2']!;
                    final top = decor.y;

                    // -------------------- NON-EDIT MODE --------------------
                    if (!decorProvider.isInEditMode) {
                      return Positioned(
                        left: left,
                        top: top,
                        child: AnimatedOpacity(
                          opacity: decor.isPlaced ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: displayW,
                            height: displayH,
                            child: Image.asset(decorDef.assetPath),
                          ),
                        ),
                      );
                    }

                    // -------------------- EDIT MODE --------------------
                    return Positioned(
                      left: left,
                      top: top,
                      child: LongPressDraggable<String>(
                        data: decor.id,
                        onDragStarted: () {
                          decorProvider.startMovingDecor(decor.id);
                        },
                        onDragEnd: (details) async {
                          decorProvider.stopMovingDecor();

                          final RenderBox box =
                              context.findRenderObject() as RenderBox;
                          final local = box.globalToLocal(details.offset);

                          final newX = local.dx - offsetX * parallax['sand2']!;
                          final newY = local.dy;

                          await decorProvider.updateDecorPosition(
                            decor.id,
                            newX,
                            newY,
                            persist: true,
                          );
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: displayW,
                            height: displayH,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.green, width: 3),
                            ),
                            child: Image.asset(
                              decorDef.assetPath,
                              width: displayW,
                              height: displayH,
                            ),
                          ),
                        ),
                        childWhenDragging: SizedBox(
                          width: displayW,
                          height: displayH,
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () {
                            if (!decorProvider.isInEditMode) return;
                            if (isSelected) {
                              decorProvider.isDecorSelected(decor.id);
                            } else {
                              decorProvider.toggleDecorSelection(decor.id);
                            }
                          },
                          child: AnimatedOpacity(
                            opacity: decor.isPlaced ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: displayW,
                              height: displayH,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? (isMoving
                                            ? Colors.green
                                            : Colors.yellow)
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: Image.asset(
                                decorDef.assetPath,
                                width: displayW,
                                height: displayH,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  // ----- Edit Mode Banner -----
                  if (decorProvider.isInEditMode)
                    Positioned(
                      top: 50,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "You are in Edit Mode",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ----- Action Buttons Overlay (rendered after the decors so they are on top) -----
                  // For every selected decor render the store/sell buttons positioned above it.
                  // Buttons are wrapped in IgnorePointer while any decor is being dragged so they don't block drags.
                  ...itemsToRender
                      .where((d) => decorProvider.isDecorSelected(d.id))
                      .map((decor) {
                        final left = decor.x + offsetX * parallax['sand2']!;
                        final top = decor.y;

                        return Positioned(
                          left: left,
                          top:
                              top -
                              50, // float above the decor; tweak as desired
                          child: IgnorePointer(
                            // when moving any decor, ignore taps on buttons so they don't block a drag
                            ignoring: decorProvider.movingDecorId != null,
                            child: Material(
                              color: Colors.transparent,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildDecorActionButton(
                                    color: Colors.orange,
                                    icon: Icons.inventory,
                                    tooltip: 'Store',
                                    onTap: () async {
                                      debugPrint(
                                        '🟠 Store tapped for ${decor.id}',
                                      );
                                      await decorProvider.storeDecor(decor.id);
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _buildDecorActionButton(
                                    color: Colors.green,
                                    icon: Icons.attach_money,
                                    tooltip: 'Sell',
                                    onTap: () async {
                                      debugPrint(
                                        '🟢 Sell tapped for ${decor.id}',
                                      );
                                      await decorProvider.sellDecor(decor.id);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ],
              ),

              ...bubbles.map(
                (bubble) => Positioned(
                  left: bubble.x,
                  top: bubble.y,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        bubbles.remove(bubble);
                      });
                      OverlayEntry? overlayEntry;
                      overlayEntry = OverlayEntry(
                        builder: (context) => Positioned(
                          left: bubble.x,
                          top: bubble.y,
                          child: Image.asset(
                            'assets/particles/bubble_pop.png',
                            width: bubble.size,
                            height: bubble.size,
                          ),
                        ),
                      );
                      Overlay.of(context).insert(overlayEntry);
                      Future.delayed(const Duration(milliseconds: 300), () {
                        overlayEntry?.remove();
                      });
                    },
                    child: Image.asset(
                      bubble.asset,
                      width: bubble.size,
                      height: bubble.size,
                    ),
                  ),
                ),
              ),
              ...fishes.map((fish) {
                return Positioned(
                  left: fish.x,
                  top: fish.y,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(fish.movingRight ? 0 : pi),
                    child: Image.asset(
                      fish.currentAsset,
                      width: 80,
                      height: 80,
                    ),
                  ),
                );
              }),
              ...dirts.map(
                (dirt) => Positioned(
                  left: dirt.x,
                  top: dirt.y,
                  child: Opacity(
                    opacity: dirt.opacity,
                    child: Image.asset(dirt.asset, width: 40, height: 40),
                  ),
                ),
              ),
              ...foodPellets.map(
                (pellet) => Positioned(
                  left: pellet.x,
                  top: pellet.y,
                  child: Image.asset(
                    'assets/tools/foodpellet.png',
                    width: 25,
                    height: 25,
                  ),
                ),
              ),
              _buildLayer(
                'assets/tank/sand2.png',
                sand2Width,
                offsetX * parallax['sand2']!,
              ),
              // ----- Care Tools Top Left -----
              if (!decorProvider.isInEditMode)
                Positioned(
                  top: 20,
                  left: 20,
                  child: Row(
                    children: [
                      // Fish Food Column
                      Column(
                        children: [
                          Draggable(
                            feedback: Image.asset(
                              'assets/tools/fishfood_drop.gif',
                              width: 60,
                              height: 60,
                            ),
                            childWhenDragging: const SizedBox(
                              width: 60,
                              height: 60,
                            ),
                            onDragStarted: () {
                              setState(() {
                                _isDraggingFood = true;
                              });
                              _onFoodDragStarted(
                                DragStartDetails(
                                  globalPosition: Offset(50, 50),
                                ),
                              );
                            },
                            onDragUpdate: _onFoodDragUpdate,
                            onDragEnd: (details) {
                              setState(() {
                                _isDraggingFood = false;
                              });
                              _onFoodDragEnd(details);
                            },
                            child: Image.asset(
                              'assets/tools/fishfood_icon.png',
                              width: 60,
                              height: 60,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Label wrapped in Container
                          Visibility(
                            visible: !_isDraggingFood,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(
                                  255,
                                  255,
                                  255,
                                  255,
                                ).withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Feed',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      // Sponge Column
                      Column(
                        children: [
                          Draggable(
                            feedback: Image.asset(
                              'assets/tools/sponge_icon.png',
                              width: 60,
                              height: 60,
                            ),
                            childWhenDragging: const SizedBox(
                              width: 60,
                              height: 60,
                            ),
                            onDragStarted: () {
                              setState(() {
                                _isDraggingSponge = true;
                              });
                            },
                            onDragUpdate: (details) {
                              _cleanDirt(details.globalPosition);
                            },
                            onDragEnd: (details) {
                              setState(() {
                                _isDraggingSponge = false;
                              });
                            },
                            child: Image.asset(
                              'assets/tools/sponge_icon.png',
                              width: 60,
                              height: 60,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Visibility(
                            visible: !_isDraggingSponge,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(
                                  255,
                                  255,
                                  255,
                                  255,
                                ).withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Clean',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // ----- Child Info Top Right -----
              if (!decorProvider.isInEditMode)
                Positioned(
                  top: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Balance
                      Consumer2<DecorProvider, FishProvider>(
                        builder: (context, decorProvider, fishProvider, _) {
                          // Take balance from FishProvider if available, otherwise fallback to DecorProvider
                          final balance = fishProvider.currentChild.balance;

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$balance',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Image.asset(
                                  'assets/coin.png',
                                  width: 18,
                                  height: 18,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      // Achievement Page Button
                      GestureDetector(
                        onTap: () =>
                            Navigator.pushNamed(context, '/achievements'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Color.fromRGBO(254, 206, 0, 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Achievements',
                                style: TextStyle(color: Colors.white),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.emoji_events, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Store Button
                      GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StorePage(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(
                              134,
                              87,
                              243,
                              100,
                            ).withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Store',
                                style: TextStyle(color: Colors.white),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.storefront, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      GestureDetector(
                        onTap: () {
                          final auth = Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          );

                          // Check if the logged-in user is a child
                          if (auth.currentUserModel is ChildUser) {
                            final child = auth.currentUserModel as ChildUser;
                            final childId = child.cid;
                            final parentId =
                                child.parentUid; // ✅ also include parent ID

                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => AquariumTutorialModal(
                                onComplete: () async {
                                  await AquariumTutorial.markTutorialSeen(
                                    parentId: parentId,
                                    childId: childId,
                                  );
                                },
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.help_outline,
                            color: Colors.blue[800],
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bottom-right stacked buttons
              // ----- Inline Bottom Menu in main Stack -----
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Dropdown buttons
                    SizeTransition(
                      sizeFactor: _animController,
                      axis: Axis.vertical,
                      axisAlignment: 1, // expand upwards
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Inventory button
                          if (!decorProvider.isInEditMode)
                            GestureDetector(
                              onTap: () async {
                                final selected = await showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => const InventoryModal(),
                                );
                                if (selected != null) {
                                  await decorProvider.placeFromInventory(
                                    selected.decorId,
                                    100,
                                    200,
                                  );
                                }
                              },
                              child: _menuButton(
                                'Open Inventory',
                                Icons.inventory_2,
                                Colors.orangeAccent,
                              ),
                            ),
                          if (!decorProvider.isInEditMode)
                            const SizedBox(height: 8),

                          // Edit / Save button
                          GestureDetector(
                            onTap: () async {
                              if (decorProvider.isInEditMode) {
                                await decorProvider.saveEditMode();
                                final unlockManager = context
                                    .read<UnlockManager>();
                                await unlockManager.checkUnlocks();
                              } else {
                                decorProvider.enterEditMode();
                              }
                            },
                            child: _menuButton(
                              decorProvider.isInEditMode
                                  ? 'Save Changes'
                                  : 'Edit Aquarium',
                              decorProvider.isInEditMode
                                  ? Icons.save
                                  : Icons.edit,
                              Colors.greenAccent,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),

                    // Main menu button (always visible)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_animController.isCompleted) {
                            _animController.reverse();
                          } else {
                            _animController.forward();
                          }
                        });
                      },
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Icon(
                          _animController.isCompleted
                              ? Icons.close
                              : Icons.menu,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuButton(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14, // slightly smaller font
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 30, color: Colors.white), // slightly smaller icon
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  Widget _buildLayer(String asset, double layerWidth, double offset) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: OverflowBox(
        maxWidth: double.infinity,
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
          offset: Offset(offset, 0),
          child: Image.asset(asset, width: layerWidth, fit: BoxFit.fill),
        ),
      ),
    );
  }

  Widget _buildDecorActionButton({
    required Color color,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    double size = 40,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 4,
                offset: const Offset(1, 2),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}
