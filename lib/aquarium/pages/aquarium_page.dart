// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math';
import 'package:brightbuds_new/aquarium/catalogs/decor_catalog.dart';
import 'package:brightbuds_new/aquarium/catalogs/fish_catalog.dart';
import 'package:brightbuds_new/aquarium/manager/aquarium_level_composer.dart';
import 'package:brightbuds_new/aquarium/manager/tutorial_manager.dart';
import 'package:brightbuds_new/aquarium/pages/achievement_page.dart';
import 'package:brightbuds_new/aquarium/pages/world_unlocks_modal.dart';
import 'package:brightbuds_new/aquarium/progression/level_calculator.dart';
import 'package:brightbuds_new/aquarium/providers/progression_provider.dart';
import 'package:brightbuds_new/aquarium/widgets/floating_xp.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/data/repositories/user_repository.dart';
import 'package:brightbuds_new/utils/network_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import '../models/fish_definition.dart';
import '../models/decor_definition.dart';
import '../manager/unlockManager.dart';
import '../notifiers/unlockNotifier.dart';
import '../notifiers/unlockDialog.dart';
import '../pages/aquarium_tutorial_modal.dart';

/// ------------------------------------------------------------
/// Internal Visual Models (UI-only, NOT persisted)
/// ------------------------------------------------------------

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

class FoodPellet {
  double x;
  double y;
  double speed;
  FoodPellet({required this.x, required this.y, this.speed = 3});
}

/// ------------------------------------------------------------
/// Helper: Get background assets based on world
/// ------------------------------------------------------------
class WorldBackgrounds {
  final String waterBg;
  final String sandBg;
  final String sand1;
  final String sand2;

  const WorldBackgrounds({
    required this.waterBg,
    required this.sandBg,
    required this.sand1,
    required this.sand2,
  });
}

WorldBackgrounds getWorldBackgrounds(int worldId) {
  if (worldId == 2) {
    // Pond
    return const WorldBackgrounds(
      waterBg: 'assets/tank/pond_bg.png',
      sandBg: 'assets/tank/gravel_bg.png',
      sand1: 'assets/tank/gravel1.png',
      sand2: 'assets/tank/gravel2.png',
    );
  }

  // Default = Aquarium
  return const WorldBackgrounds(
    waterBg: 'assets/tank/water_bg.png',
    sandBg: 'assets/tank/sand_bg.png',
    sand1: 'assets/tank/sand1.png',
    sand2: 'assets/tank/sand2.png',
  );
}

class DecorInstance {
  final String id;
  final String assetPath;
  final int layer;
  final double anchorX; // 0..1
  final double anchorY; // 0..1
  final double widthFactor; // relative width

  DecorInstance({
    required this.id,
    required this.assetPath,
    required this.layer,
    required this.anchorX,
    required this.anchorY,
    required this.widthFactor,
  });
}

/// ------------------------------------------------------------
/// Aquarium Page
/// ------------------------------------------------------------

class AquariumPage extends StatefulWidget {
  const AquariumPage({super.key});

  @override
  State<AquariumPage> createState() => _AquariumPageState();
}

class _AquariumPageState extends State<AquariumPage>
    with TickerProviderStateMixin {
        double offsetX = 0.0;
  final UserRepository _userRepo = UserRepository();
  late Box _settingsBox;
  late AnimationController _controller;
  late Animation<double> _animation;
  late AnimationController _animController;
  int _foodPelletCountDuringDrag = 0;

  StreamSubscription<DocumentSnapshot>? _xpSubscription;

  final Map<String, double> parallax = {
    'sand_bg': 0.2,
    'sand1': 0.5,
    'sand2': 0.8,
  };

  late double maxOffsetSandBg;
  late double maxOffsetSand1;
  late double maxOffsetSand2;

  final Random random = Random();

  List<Bubble> bubbles = [];
  List<AquariumFish> fishes = [];
  List<Dirt> dirts = [];
  List<FoodPellet> foodPellets = [];
  List<DecorInstance> decors = [];

  Timer? _foodDragTimer;
  Offset? _lastDragPosition;
  // ignore: unused_field
  Timer? _tankDirtTimer;
  Timer? _xpRefreshTimer;
  String? _currentChildId;

  bool _xpGrantedThisFeeding = false;
  int childXP = 0;

  bool _isDraggingFood = false;
  bool _isDraggingSponge = false;
    
  late ProgressionProvider _progression;
  late UnlockManager _unlockManager;

  bool _initialized = false;

  int _lastLevel = -1;
  Set<String> _fedFishIds = {};

  @override
void didChangeDependencies() {
  super.didChangeDependencies();

  final auth = context.read<AuthProvider>();
  final child = auth.currentUserModel;
  if (child is! ChildUser) return;

  _currentChildId = child.cid;
  _listenToXPRealtime();

  if (!_initialized) {
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _progression = context.read<ProgressionProvider>();
      _unlockManager = context.read<UnlockManager>();
      _buildAquariumFromLevelIfNeeded();
    });
  }
}

  @override
  void initState() {
    super.initState();
    _progression = context.read<ProgressionProvider>();

    context.read<TaskProvider>().addListener(_onTasksChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _fetchXP();
    });
    _settingsBox = Hive.box('settingsBox');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _progression = context.read<ProgressionProvider>();
      _unlockManager = context.read<UnlockManager>();

      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.currentUserModel is! ChildUser) return;
      final child = auth.currentUserModel as ChildUser;
      final selectedChildProvider = Provider.of<SelectedChildProvider>(
        context,
        listen: false,
      );

      final justUnlocked = _unlockManager.lastUnlock;
      if (justUnlocked != null) {
    // Check if we already showed this unlock for this child
    final shownKey = 'shown_unlock_${child.cid}_${justUnlocked.id}';
    final alreadyShown = _settingsBox.get(shownKey, defaultValue: false);

    if (!alreadyShown) {
      // Mark as shown so it doesn't repeat
      await _settingsBox.put(shownKey, true);

      // Show the unlock dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UnlockDialog(unlockedItem: justUnlocked),
      );
    }

    // Clear lastUnlock so it doesn't trigger again on page rebuild
    _unlockManager.clearLastUnlock();
  }

      if (auth.currentUserModel is ChildUser) {
        final child = auth.currentUserModel as ChildUser;

        // Update local balance
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            childXP = child.xp;
          });
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
          await childDoc.reference.update({'firstVisitUnlocked': true});

          selectedChildProvider.updateSelectedChild({
            'firstVisitUnlocked': true,
          });
          child.firstVisitUnlocked = true;

          await Future.delayed(Duration(milliseconds: 100));
        }

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
      _buildAquariumFromLevelIfNeeded();
    });
  }

  void _onTasksChanged() {
  final auth = context.read<AuthProvider>();
  final child = auth.currentUserModel;
  if (child is! ChildUser) return;

  final tasks = context.read<TaskProvider>().tasks
      .where((t) => t.childId == child.cid)
      .toList();

  _unlockManager.checkAchievementUnlocks(tasks, child);
}

  void _listenToXPRealtime() {
  final auth = context.read<AuthProvider>();
  final child = auth.currentUserModel;
  if (child is! ChildUser) return;

  final parentId = child.parentUid;
  final childId = child.cid;

  _xpSubscription?.cancel();
  _xpSubscription = FirebaseFirestore.instance
      .collection('users')
      .doc(parentId)
      .collection('children')
      .doc(childId)
      .snapshots()
      .listen((doc) {
    if (!doc.exists) return;

    final fetchedXP = (doc['xp'] is int)
        ? doc['xp']
        : int.tryParse('${doc['xp']}') ?? 0;

    debugPrint('🔥 REALTIME XP UPDATE: $fetchedXP');
    _progression.updateXP(fetchedXP);
    _settingsBox.put('cached_xp_$childId', fetchedXP);
    _buildAquariumFromLevelIfNeeded();
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

    final List<String> toPersist = [];

    setState(() {
      for (var fish in fishes) {
        if (!fish.neglected) {
          fish.neglected = true;
          toPersist.add(fish.definition.id);
        }
      }
    });

    // Persist via new UnlockManager
    for (var defId in toPersist) {
      await _unlockManager.setFishNeglected(defId, true);
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

        bool allFedNow = false;

        for (var fish in fishes) {
          // If there's food, move toward the closest pellet
          if (foodPellets.isNotEmpty) {
            FoodPellet closestPellet = foodPellets.reduce(
              (a, b) =>
                  (sqrt(pow(fish.x - a.x, 2) + pow(fish.y - a.y, 2)) <
                          sqrt(pow(fish.x - b.x, 2) + pow(fish.y - b.y, 2)))
                      ? a
                      : b,
            );

            double dx = closestPellet.x - fish.x;
            double dy = closestPellet.y - fish.y;
            double distance = sqrt(dx * dx + dy * dy);

            // Face the direction of movement
            fish.movingRight = dx >= 0;

            if (distance < 5) {
              _fedFishIds.add(fish.definition.id);
              foodPellets.remove(closestPellet);

              // Reset health if all fish fed
              if (_fedFishIds.length >= fishes.length) {
                allFedNow = true;
                if (!_xpGrantedThisFeeding) {
                  _xpGrantedThisFeeding = true; // prevent multiple XP grants
                  _resetFishesHealth(); // reset immediately
                  _showXPGrandReward();
                }
              }
            } else {
              // Move toward the pellet
              fish.x += dx / distance * fish.speed;
              fish.y += dy / distance * fish.speed;
            }
          } else {
            // Normal swimming
            double swimAmplitude = fish.neglected ? 0.2 : 0.5;
            double swimSpeed = fish.neglected ? 0.5 : fish.speed;

            fish.x += fish.movingRight ? swimSpeed : -swimSpeed;
            if (fish.x < 0) fish.movingRight = true;
            if (fish.x > screenWidth - 50) fish.movingRight = false;
            fish.y += sin(fish.x * fish.sineFrequency) * swimAmplitude;
          }

          // Clamp vertical position
          fish.y = min(fish.y, maxY);

          if (allFedNow) {
            _showXPGrandReward();
          }
          if (foodPellets.isEmpty) {
            // reset flag so next feeding session works
            _xpGrantedThisFeeding = false;
            _fedFishIds.clear();
          }
        }
      });

      // Repeat animation
      _animateFishes();
    });
  }

  void _showXPGrandReward() async {
  if (!mounted) return;
  debugPrint("🎉 All fish fed! Granting XP!");

  final screenSize = MediaQuery.of(context).size;
  final position = Offset(screenSize.width / 2, screenSize.height * 0.4);

  // Overlay XP animation
  late OverlayEntry overlay;
  overlay = OverlayEntry(
    builder: (_) => FloatingXP(
      position: position,
      xp: 5,
      onCompleted: () {
        overlay.remove(); // safely remove overlay
      },
    ),
  );
  Overlay.of(context).insert(overlay);

  // Add XP locally
  setState(() {
    childXP += 5;
  });
  _progression.updateXP(childXP);

  try {
    // Get parentUid and childId safely from AuthProvider
    final auth = context.read<AuthProvider>();
    final currentUser = auth.currentUserModel;

    if (currentUser is! ChildUser) {
      debugPrint("❌ Current user is not a child. Cannot grant XP.");
      return;
    }

    final parentUid = currentUser.parentUid;
    final childId = currentUser.cid;

    // Update XP in repository
    await _userRepo.updateChildXP(parentUid, childId, 5);

    // Optional: fetch updated child for cache
    final updatedChild = await _userRepo.fetchChildAndCache(parentUid, childId);
    if (updatedChild != null) {
      setState(() => childXP = updatedChild.xp);
      _progression.updateXP(childXP);
    }

    debugPrint("✅ XP granted successfully: 5 XP");
  } catch (e) {
    debugPrint("⚠️ Failed to grant XP: $e");
  }
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
    if (!mounted) return;
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

  void _resetFishesHealth() async {
  final previouslyNeglected = fishes.where((f) => f.neglected).toList();
  if (previouslyNeglected.isEmpty) return;

  setState(() {
    for (var fish in previouslyNeglected) {
      fish.neglected = false;
    }
  });

  // Persist via UnlockManager
  for (var fish in fishes) {
    _unlockManager.setFishNeglected(fish.definition.id, false);
  }

  _fedFishIds.clear(); // ensure fed tracking resets immediately
  _xpGrantedThisFeeding = false;
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

  void _popBubble(Bubble b) {
    setState(() => bubbles.remove(b));
    final overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: b.x,
        top: b.y,
        child: Image.asset('assets/particles/bubble_pop.png', width: b.size, height: b.size),
      ),
    );
    Overlay.of(context).insert(overlay);
    Future.delayed(const Duration(milliseconds: 300), () => overlay.remove());
  }
  
  Future<void> _fetchXP() async {
  final auth = context.read<AuthProvider>();
  final currentUser = auth.currentUserModel;

  if (currentUser is! ChildUser) {
    debugPrint('❌ Only child accounts can fetch XP for the aquarium.');
    return;
  }

  final parentId = currentUser.parentUid;
  final childId = currentUser.cid;

  if (parentId.isEmpty || childId.isEmpty) {
    debugPrint('❌ Parent or Child ID is empty. Cannot fetch XP.');
    return;
  }

  final cachedKey = 'cached_xp_$childId';

  // Load cached XP immediately
  final cached = _settingsBox.get(cachedKey, defaultValue: 0);
  if (mounted) setState(() => childXP = cached);
  _progression.updateXP(cached);
  debugPrint('📦 Loaded cached XP: $cached');

  // Fetch from Firestore if online
  if (await NetworkHelper.isOnline()) {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .collection('children')
          .doc(childId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final val = doc['xp'];
      final fetched = (val is int)
          ? val
          : (val is double)
              ? val.toInt()
              : int.tryParse('$val') ?? 0;

      if (fetched != cached) {
        if (mounted) setState(() => childXP = fetched);
        await _settingsBox.put(cachedKey, fetched);
        _progression.updateXP(fetched);
        debugPrint('🟢 XP refreshed Firestore → Hive → ProgressionProvider: $fetched');
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching XP from Firestore: $e');
    }
  } else {
    debugPrint('📴 Offline mode — using cached Hive XP.');
  }

  _buildAquariumFromLevelIfNeeded();
}

 @override
void dispose() {
  _xpSubscription?.cancel();
  _progression.removeListener(() {});
  _animController.dispose();
  _controller.dispose();
  super.dispose();
}

  /// ------------------------------------------------------------
  /// Aquarium Composition (LEVEL-BASED)
  /// ------------------------------------------------------------

  void _buildAquariumFromLevelIfNeeded() {
  final progression = _progression.state;
  final level = progression.level;
  final worldId = progression.world.worldId;

  final auth = context.read<AuthProvider>();
  final child = auth.currentUserModel;
  if (child is! ChildUser) return;

 final previousLevel = _lastLevel;
  final levelChanged = level != previousLevel;

  if (!levelChanged) return;

  // ✅ Update level FIRST
  _lastLevel = level;

  debugPrint('🐠 Rebuilding aquarium → Level: $level | World: $worldId');

  // ✅ NOW trigger unlocks for the NEW level
  if (levelChanged && previousLevel != -1) {
    debugPrint('🔓 Level up detected: $previousLevel → $level');
    _unlockManager.checkLevelUnlocks(level);
  }

  final data = AquariumLevelComposer.getLevelData(
    level: level,
    world: worldId,
  );

  fishes.clear();
  dirts.clear();

  final size = MediaQuery.of(context).size;

  /// 🐟 Build fish
  for (final fishDef in data.fishes) {
    fishes.add(
      AquariumFish(
        definition: fishDef,
        x: random.nextDouble() * size.width,
        y: size.height * (0.25 + random.nextDouble() * 0.4),
        movingRight: random.nextBool(),
        speed: 0.8 + random.nextDouble(),
        sineFrequency: 0.01 + random.nextDouble() * 0.02,
        verticalOffset: random.nextDouble() * 20,
      ),
    );
  }

  /// 🌿 Build decor
  decors.clear();

for (final decorDef in DecorCatalog.byWorld(progression.world.worldId)
    .where((d) => d.unlockLevel <= level)) {
  decors.add(
    DecorInstance(
      id: decorDef.id,
      assetPath: decorDef.assetPath,
      anchorX: decorDef.anchorX,
      anchorY: decorDef.anchorY,
      layer: decorDef.layer,
      widthFactor: decorDef.widthFactor,
    ),
  );
}


  if (mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }
}

  /// ------------------------------------------------------------
  /// Build
  /// ------------------------------------------------------------

  @override
Widget build(BuildContext context) {
  final auth = context.watch<AuthProvider>();
  final currentUser = auth.currentUserModel;

  if (currentUser is! ChildUser) {
    return const Scaffold(
      body: Center(
        child: Text(
          '❌ Only child accounts can access the Aquarium.\nPlease log in as a child.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  final rootContext = context;
  context.watch<ProgressionProvider>();

  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;
  final size = MediaQuery.of(context).size;

  final double sandBgWidth = screenWidth * 1.2;
  final double sand1Width = screenWidth * 1.4;
  final double sand2Width = screenWidth * 1.6;

  maxOffsetSandBg = (sandBgWidth - screenWidth) / 2;
  maxOffsetSand1 = (sand1Width - screenWidth) / 2;
  maxOffsetSand2 = (sand2Width - screenWidth) / 2;

  final progression = context.watch<ProgressionProvider>();
  final worldId = progression.state.world.worldId;
  final bg = getWorldBackgrounds(worldId);

  return Scaffold(
  body: Stack(
    children: [

      // ===============================
      // 1️⃣ AQUARIUM (DRAG ONLY)
      // ===============================
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: (_) => _onDragEnd(),
        child: Stack(
          children: [

            // Background
            Positioned.fill(
              child: Image.asset(
                bg.waterBg,
                fit: BoxFit.cover,
              ),
            ),

            _buildLayer(bg.sandBg, sandBgWidth, offsetX * parallax['sand_bg']!),

            _buildLayer(bg.sand1, sand1Width, offsetX * parallax['sand1']!),

            // BUBBLES (behind sand2 as requested)
            ...bubbles.map((b) => Positioned(
                  left: b.x,
                  top: b.y,
                  child: Transform.translate(
                    offset: Offset(offsetX * parallax['sand2']!, 0), // same as sand2
                    child: GestureDetector(
                      onTap: () => _popBubble(b),
                      child: Image.asset(b.asset, width: b.size),
                    ),
                  ),
                )),

            // Fish / dirt / pellets (non-interactive)
            IgnorePointer(
              child: Stack(
                children: [
                  ...foodPellets.map((p) => Positioned(
                        left: p.x,
                        top: p.y,
                        child: Transform.translate(
                          offset: Offset(offsetX * parallax['sand2']!, 0),
                          child: Image.asset(
                            'assets/tools/foodpellet.png',
                            width: 20,
                          ),
                        ),
                      )),
                ],
              ),
            ),

            // Front sand
            _buildLayer(bg.sand2, sand2Width, offsetX * parallax['sand2']!),
            ...decors.map((decor) {
                      final screenSize = MediaQuery.of(context).size;

                      // Compute position using anchorX/Y (0..1) and parallax for x
                      final leftPos = screenSize.width * decor.anchorX + offsetX * parallax['sand2']!;
                      final topPos = screenSize.height * decor.anchorY;

                      return Positioned(
                        left: leftPos,
                        top: topPos,
                        child: Image.asset(
                          decor.assetPath,
                          width: screenSize.width * decor.widthFactor, // scaled for screen width
                        ),
                      );
                    }),
                  ...fishes.map((f) => Positioned(
                        left: f.x,
                        top: f.y,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(f.movingRight ? 0 : pi),
                          child: Transform.translate(
                            offset: Offset(offsetX * parallax['sand2']!, 0),
                            child: Image.asset(
                              f.currentAsset,
                              width: 80,
                            ),
                          ),
                        ),
                      )),
                  ...dirts.map((d) => Positioned(
                        left: d.x,
                        top: d.y,
                        child: Transform.translate(
                          offset: Offset(offsetX * parallax['sand2']!, 0),
                          child: Opacity(
                            opacity: d.opacity,
                            child: Image.asset(d.asset, width: 40),
                          ),
                        ),
                      )),
          ],
        ),
      ),

      // ===============================
      // 2️⃣ UI LAYER (NO DRAG HERE)
      // ===============================
      // Bottom-left tools overlay
      Positioned(
        bottom: 20,
        left: 20,
        child: _toolsOverlay(),
      ),

      // Bottom-right buttons (Achievements / World)
      Positioned(
        bottom: 20,
        right: 20,
        child: _bottomRightUI(),
      ),

      _xpProgressionBar(),
      
      _unlockListener(),
    ],
  ),
);
}

// Reusable layer builder for parallax sands
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


  Widget _toolsOverlay() {
    return Row(
      children: [
        // Feed Column
        Column(
          children: [
            Draggable(
              feedback: Image.asset(
                'assets/tools/fishfood_drop.gif',
                width: 60,
                height: 60,
              ),
              childWhenDragging: const SizedBox(width: 60, height: 60),
              onDragStarted: () {
                setState(() {
                  _isDraggingFood = true;
                });
                _onFoodDragStarted(
                  DragStartDetails(globalPosition: Offset(50, 50)),
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
            Visibility(
              visible: !_isDraggingFood,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
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

        // Clean Column
        Column(
          children: [
            Draggable(
              feedback: Image.asset(
                'assets/tools/sponge_icon.png',
                width: 60,
                height: 60,
              ),
              childWhenDragging: const SizedBox(width: 60, height: 60),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
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
    );
}

Widget _bottomRightUI() {
  return Material(
    color: Colors.transparent,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end, // Align to right
      children: [
        // 🌍 WORLD UNLOCKS BUTTON
        GestureDetector(
          onTap: () {
            final currentUser =
                context.read<AuthProvider>().currentUserModel;

            if (currentUser is! ChildUser) return;

            _openWorldUnlocks(context);
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('World', style: TextStyle(color: Colors.white)),
                SizedBox(width: 6),
                Icon(Icons.public, color: Colors.white),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // 🏆 ACHIEVEMENTS BUTTON
        GestureDetector(
          onTap: () {
            try {
              final currentUser =
                  context.read<AuthProvider>().currentUserModel;

              if (currentUser is! ChildUser) return;

              final child = currentUser;
              final tasks = context
                  .read<TaskProvider>()
                  .tasks
                  .where((t) => t.childId == child.cid)
                  .toList();

              Navigator.pushNamed(
                context,
                '/achievements',
                arguments: {
                  'child': child,
                  'tasks': tasks,
                },
              );
            } catch (e, st) {
              debugPrint('❌ Navigation failed: $e');
              debugPrint(st.toString());
            }
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orangeAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Achievements', style: TextStyle(color: Colors.white)),
                SizedBox(width: 6),
                Icon(Icons.emoji_events, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _xpProgressionBar() {
  return Consumer<ProgressionProvider>(
    builder: (_, progression, __) {
      final xp = progression.state.xp;
      final level = progression.state.level;
      final calculator = LevelCalculator();

      final currentLevelXp = calculator.xpForLevel(level);
      final nextLevelXp = calculator.xpForLevel(level + 1);
      final progress = (xp - currentLevelXp) / (nextLevelXp - currentLevelXp);
      final remainingXp = nextLevelXp - xp;

      return Positioned(
        top: 20,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Level $level', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$remainingXp XP to next level',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  Widget _unlockListener() {
  final unlockNotifier = context.watch<UnlockNotifier>();
  final unlockedItem = unlockNotifier.current;

  if (unlockedItem == null) return const SizedBox();

  // Clear after displaying
  WidgetsBinding.instance.addPostFrameCallback((_) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UnlockDialog(
        unlockedItem: unlockedItem,
      ),
    );
    unlockNotifier.clearCurrent();
  });

  return const SizedBox();
}

dynamic getNextUnlock({
  required int level,
  required int world,
}) {
  final nextFish = FishCatalog.all
      .where((f) => f.world == world && f.unlockLevel > level)
      .toList()
    ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

  final nextDecor = DecorCatalog.all
      .where((d) => d.world == world && d.unlockLevel > level)
      .toList()
    ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));

  if (nextFish.isEmpty && nextDecor.isEmpty) return null;

  if (nextFish.isEmpty) return nextDecor.first;
  if (nextDecor.isEmpty) return nextFish.first;

  return nextFish.first.unlockLevel <= nextDecor.first.unlockLevel
      ? nextFish.first
      : nextDecor.first;
}

void _openWorldUnlocks(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'World Unlocks',
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) {
      return const WorldUnlocksModal();
    },
    transitionBuilder: (_, animation, __, child) {
      return Transform.scale(
        scale: Curves.easeOutBack.transform(animation.value),
        child: Opacity(
          opacity: animation.value,
          child: child,
        ),
      );
    },
  );
}


}
