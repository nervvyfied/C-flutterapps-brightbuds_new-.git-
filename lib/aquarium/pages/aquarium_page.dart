import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

class AquariumPage extends StatefulWidget {
  const AquariumPage({super.key});

  @override
  State<AquariumPage> createState() => _AquariumPageState();
}

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

  // --- Drag spawn timer ---
  Timer? _foodDragTimer;
  Offset? _lastDragPosition;

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

  // ----- Feed Fish (final on drag end or tap) -----
  void _feedFishes(Offset globalPosition) {
    _spawnFoodPellet(globalPosition);
    _stopFoodDragTimer();
  }

  void _spawnFoodPellet(Offset globalPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final localPosition = box.globalToLocal(globalPosition);

    foodPellets.add(FoodPellet(x: localPosition.dx, y: localPosition.dy));

    for (var fish in fishes) {
      if (fish.neglected) {
        fish.neglected = false;
        fish.asset = neglectedMap.entries
            .firstWhere((entry) => entry.value == fish.asset)
            .key;
      }
    }

    setState(() {});
  }

  void _startFoodDragTimer(Offset initialPosition) {
    _foodDragTimer?.cancel();
    _foodDragTimer = Timer.periodic(
      Duration(milliseconds: 500 + random.nextInt(500)),
      (timer) {
        if (_lastDragPosition != null) _spawnFoodPellet(_lastDragPosition!);
      },
    );
  }

  void _onFoodDragStarted(DragStartDetails details) {
  _lastDragPosition = details.globalPosition;
  _foodPelletCountDuringDrag = 0;

  // Start timer immediately
  _foodDragTimer?.cancel();
  _foodDragTimer = Timer.periodic(
    Duration(milliseconds: 500 + random.nextInt(500)),
    (_) {
      if (_lastDragPosition != null) {
        _spawnFoodPellet(_lastDragPosition!);
        _foodPelletCountDuringDrag++;

        // Check if we have spawned enough pellets to reset fish health
        if (_foodPelletCountDuringDrag >= fishes.length) {
          _resetFishesHealth();
        }
      }
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

// ----- Reset Fish Health -----
void _resetFishesHealth() {
  for (var fish in fishes) {
    if (fish.neglected) {
      fish.neglected = false;
      fish.asset = neglectedMap.entries
          .firstWhere((entry) => entry.value == fish.asset)
          .key;
    }
  }
  setState(() {});
}

// ----- Stop Timer -----
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
                    width: 60,
                    height: 60,
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
                  width: 15,
                  height: 15,
                ),
              ),
            ),
            _buildLayer(
                'assets/tank/sand2.png', sand2Width, offsetX * parallax['sand2']!),

            // Fish Food Draggable
            Positioned(
              bottom: 20,
              left: 20,
              child: Draggable(
  feedback: Image.asset('assets/tools/fishfood_drop.gif', width: 40, height: 40),
  childWhenDragging: Image.asset('assets/tools/fishfood_icon.png', width: 40, height: 40),
  child: Image.asset('assets/tools/fishfood_icon.png', width: 40, height: 40),
  onDragStarted: () => _onFoodDragStarted(DragStartDetails(globalPosition: Offset(50, 50))),
  onDragUpdate: _onFoodDragUpdate,
  onDragEnd: _onFoodDragEnd,
),

            ),

            // Sponge Draggable
            Positioned(
              bottom: 20,
              right: 20,
              child: Draggable(
                feedback: Image.asset(
                  'assets/tools/sponge_icon.png',
                  width: 40,
                  height: 40,
                ),
                childWhenDragging: Image.asset(
                  'assets/tools/sponge_icon.png',
                  width: 40,
                  height: 40,
                ),
                child: Image.asset(
                  'assets/tools/sponge_icon.png',
                  width: 40,
                  height: 40,
                ),
                onDragUpdate: (details) {
                  _cleanDirt(details.globalPosition);
                },
              ),
            ),
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
