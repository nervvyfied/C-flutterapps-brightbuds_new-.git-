import 'dart:async';
import 'dart:math';
import 'package:brightbuds_new/aquarium/pages/inventory_modal.dart';
import 'package:brightbuds_new/aquarium/pages/store_page.dart';
import 'package:brightbuds_new/aquarium/providers/decor_provider.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

// ----- Test Fish Class -----
class TestFish {
  double x;
  double y;
  double speed;
  bool movingRight;
  String asset;
  double verticalOffset;
  double sineFrequency;
  bool neglected;

  TestFish({
    required this.x,
    required this.y,
    required this.speed,
    required this.movingRight,
    required this.asset,
    required this.verticalOffset,
    required this.sineFrequency,
    this.neglected = false,
  });
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
    with SingleTickerProviderStateMixin {
  double offsetX = 0.0;
  late AnimationController _controller;
  late Animation<double> _animation;
  int _foodPelletCountDuringDrag = 0;

  final Map<String, double> parallax = {
    'sand_bg': 0.2,
    'sand1': 0.5,
    'sand2': 0.8,
  };

  final Map<String, String> neglectedMap = {
    'assets/fish/normal/fish1_normal.gif':
        'assets/fish/neglected/fish1_neglected.png',
    'assets/fish/normal/fish2_normal.gif':
        'assets/fish/neglected/fish2_neglected.png',
    'assets/fish/normal/fish3_normal.gif':
        'assets/fish/neglected/fish3_neglected.png',
  };

  late double maxOffsetSandBg;
  late double maxOffsetSand1;
  late double maxOffsetSand2;

  final Random random = Random();

  List<Bubble> bubbles = [];
  List<TestFish> fishes = [];
  List<Dirt> dirts = [];
  List<FoodPellet> foodPellets = [];

  Timer? _foodDragTimer;
  Offset? _lastDragPosition;
  Timer? _tankDirtTimer;

  // Dummy child data for top-right display
  double childBalance = 0;
  List<bool> fishAchievements = [true, false, false]; // true = unlocked

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBubbles();
      _initTestFishes();
      _initDirts();
      _animateBubbles();
      _animateFishes();
      _animateFoodPellets();
      _startNeglectTimer();
      _startTankDirtTimer();
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.currentUserModel is ChildUser) {
        setState(() {
          childBalance = (auth.currentUserModel as ChildUser).balance.toDouble();
        });
      }
    });
  }

  void _startNeglectTimer() {
    Future.delayed(const Duration(minutes: 1), () {
      if (!mounted) return;

      setState(() {
        for (var fish in fishes) {
          if (!fish.neglected) {
            fish.neglected = true;
            fish.asset = neglectedMap[fish.asset]!;
          }
        }
      });

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
          dirts.add(Dirt(
            x: random.nextDouble() * screenWidth,
            y: random.nextDouble() * screenHeight * 0.7,
            asset: dirtAssets[random.nextInt(dirtAssets.length)],
          ));
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

  // ----- Initialize Test Fishes -----
  void _initTestFishes() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final fishAssets = [
      'assets/fish/normal/fish1_normal.gif',
      'assets/fish/normal/fish2_normal.gif',
      'assets/fish/normal/fish3_normal.gif',
    ];

    for (var asset in fishAssets) {
      fishes.add(
        TestFish(
          x: random.nextDouble() * screenWidth,
          y: screenHeight * 0.3 + random.nextDouble() * screenHeight * 0.4,
          speed: 1 + random.nextDouble() * 2,
          movingRight: random.nextBool(),
          asset: asset,
          verticalOffset: random.nextDouble() * 20,
          sineFrequency: 0.01 + random.nextDouble() * 0.02,
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

        for (var fish in fishes) {
          // Check if there is a nearby food pellet
          if (foodPellets.isNotEmpty) {
            FoodPellet closestPellet = foodPellets.reduce((a, b) =>
                (sqrt(pow(fish.x - a.x, 2) + pow(fish.y - a.y, 2)) <
                        sqrt(pow(fish.x - b.x, 2) + pow(fish.y - b.y, 2)))
                    ? a
                    : b);

            // Move fish towards pellet
            double dx = closestPellet.x - fish.x;
            double dy = closestPellet.y - fish.y;
            double distance = sqrt(dx * dx + dy * dy);

            if (distance < 5) {
              foodPellets.remove(closestPellet);
              _foodPelletCountDuringDrag = max(0, _foodPelletCountDuringDrag - 1);
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
    _animation = Tween<double>(begin: offsetX, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
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

    foodPellets.add(FoodPellet(
      x: localPosition.dx,
      y: localPosition.dy,
      speed: 2.5,
    ));

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
    for (var fish in fishes) {
      if (fish.neglected) {
        fish.neglected = false;
        fish.asset = neglectedMap.entries
            .firstWhere((entry) => entry.value == fish.asset)
            .key;
      }
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final decorProvider = Provider.of<DecorProvider>(context);
    final itemsToRender = decorProvider.isInEditMode
    ? decorProvider.editingDecors.toList()
    : decorProvider.placedDecors.where((d) => d.isPlaced).toList();


    final double sandBgWidth = screenWidth * 1.2;
    final double sand1Width = screenWidth * 1.4;
    final double sand2Width = screenWidth * 1.6;

    maxOffsetSandBg = (sandBgWidth - screenWidth) / 2;
    maxOffsetSand1 = (sand1Width - screenWidth) / 2;
    maxOffsetSand2 = (sand2Width - screenWidth) / 2;

    return Scaffold(
      body: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: (_) => _onDragEnd(),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/tank/water_bg.png',
                fit: BoxFit.cover,
              ),
            ),
            _buildLayer(
                'assets/tank/sand_bg.png', sandBgWidth, offsetX * parallax['sand_bg']!),
            _buildLayer(
                'assets/tank/sand1.png', sand1Width, offsetX * parallax['sand1']!),

            // ----- Placed Decors (above sand1, behind sand2) -----
// Determine which list to render: edit buffer if editing, otherwise persisted placed items


...itemsToRender.map((decor) {
  final decorDef = decorProvider.getDecorDefinition(decor.decorId);
  if (decorDef == null) return const SizedBox();

  final double displayW = decor.isPlaced ? 120 : 80;
  final double displayH = decor.isPlaced ? 120 : 80;

  return Positioned(
    left: decor.x,
    top: decor.y,
    child: GestureDetector(
      onLongPress: () {
        decorProvider.toggleDecorSelection(decor.id);
      },
      onDoubleTap: () {
        decorProvider.toggleDecorSelection(decor.id);
      },
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Move/Delete buttons
          if (decor.isSelected && decorProvider.isInEditMode)
            Positioned(
              top: -40,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      decorProvider.startMovingDecor(decor.id);
                    },
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.open_with, size: 16, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      await decorProvider.deleteDecorInBuffer(decor.id, refund: true);
                    },
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.red,
                      child: Icon(Icons.delete, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          // Draggable only for moving decor
          if (decorProvider.isInEditMode && decorProvider.movingDecorId == decor.id)
            Draggable<String>(
              data: decor.id,
              feedback: Image.asset(decorDef.assetPath, width: displayW, height: displayH),
              childWhenDragging: const SizedBox(width: 120, height: 120),
              child: Image.asset(decorDef.assetPath, width: displayW, height: displayH),
              onDragEnd: (details) {
                final RenderBox box = context.findRenderObject() as RenderBox;
                final local = box.globalToLocal(details.offset);

                decorProvider.updateDecorPositionInBuffer(decor.id, local.dx, local.dy);
                decorProvider.stopMovingDecor();
              },
            )
          else
            Image.asset(decorDef.assetPath, width: displayW, height: displayH),
        ],
      ),
    ),
  );
}).toList(),

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
            ...fishes.map(
              (fish) => Positioned(
                left: fish.x,
                top: fish.y,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(fish.movingRight ? 0 : pi),
                  child: Image.asset(
                    fish.asset,
                    width: 80,
                    height: 80,
                  ),
                ),
              ),
            ),
            ...dirts.map(
              (dirt) => Positioned(
                left: dirt.x,
                top: dirt.y,
                child: Opacity(
                  opacity: dirt.opacity,
                  child: Image.asset(
                    dirt.asset,
                    width: 40,
                    height: 40,
                  ),
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
                'assets/tank/sand2.png', sand2Width, offsetX * parallax['sand2']!),
           // ----- Care Tools Top Left -----
            Positioned(
              top: 20,
              left: 20,
              child: Row(
                children: [
                  // Fish Food
                  Draggable(
                    feedback: Image.asset(
                      'assets/tools/fishfood_drop.gif',
                      width: 60,
                      height: 60,
                    ),
                    childWhenDragging: const SizedBox(width: 60, height: 60),
                    onDragStarted: () =>
                        _onFoodDragStarted(DragStartDetails(globalPosition: Offset(50, 50))),
                    onDragUpdate: _onFoodDragUpdate,
                    onDragEnd: _onFoodDragEnd, // disappears while dragging
                    child: Image.asset(
                      'assets/tools/fishfood_icon.png',
                      width: 60,
                      height: 60,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Sponge
                  Draggable(
                    feedback: Image.asset(
                      'assets/tools/sponge_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    childWhenDragging: const SizedBox(width: 60, height: 60),
                    child: Image.asset(
                      'assets/tools/sponge_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    onDragUpdate: (details) {
                      _cleanDirt(details.globalPosition);
                    },
                  ),
                ],
              ),
            ),
            // ----- Child Info Top Right -----
            Positioned(
  top: 20,
  right: 20,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      // Balance (now live)
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Balance: \$${decorProvider.currentChild.balance}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      const SizedBox(height: 10),
      // Edit Tank / Save / Cancel buttons
      if (!decorProvider.isInEditMode)
        GestureDetector(
          onTap: () {
            decorProvider.enterEditMode();
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Edit Tank', style: TextStyle(color: Colors.white)),
          ),
        )
      else
        Row(
          children: [
            // Save
            GestureDetector(
              onTap: () async {
                // Save edits (persist)
                await decorProvider.saveEditMode();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(width: 8),
            // Cancel
            GestureDetector(
              onTap: () {
                decorProvider.cancelEditMode();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Cancel', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      const SizedBox(height: 10),
      // Shop button remains
      GestureDetector(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const DecorStorePage()));
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Shop', style: TextStyle(color: Colors.white)),
        ),
      ),
    ],
  ),
),
ElevatedButton(
  onPressed: () async {
    final selected = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const InventoryModal(),
    );

    if (selected != null) {
      // Place decor at default location
      final decorProvider = Provider.of<DecorProvider>(context, listen: false);
      await decorProvider.placeFromInventory(selected.decorId, 100, 200); 
    }
  },
  child: const Text("Open Inventory"),
)


          ],
        ),
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
          child: Image.asset(
            asset,
            width: layerWidth,
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }
}
