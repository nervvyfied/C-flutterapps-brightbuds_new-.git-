import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../models/cbt_exercise_model.dart';
import '../../providers/cbt_provider.dart';

class StepStoneView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;
  final String parentId;

  const StepStoneView({super.key, required this.exercise, required this.childId, required this.parentId});

  @override
  State<StepStoneView> createState() => _StepStoneViewState();
}

class _StepStoneViewState extends State<StepStoneView> with TickerProviderStateMixin {
  int _currentStone = 0;
  bool _completed = false;
  bool _canProceed = false;

  final List<String> _prompts = [
    "What confuses me?",
    "What I understand 💡",
    "What I’ll try ➡️"
  ];

  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController()
  ];

  late AnimationController _hopController;
  late Animation<double> _hopAnimation;

  late List<Offset> stonePositions;

  @override
  void initState() {
    super.initState();

    stonePositions = [
      const Offset(0.45, 0.55), // Stone 1 bottom-left
      const Offset(0.65, 0.35), // Stone 2 middle-right
      const Offset(0.40, 0.15), // Stone 3 top-left
    ];

    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _hopAnimation = CurvedAnimation(parent: _hopController, curve: Curves.easeInOut);

    // Start on first stone (no hop)
    _hopController.value = 1.0;

    _controllers[_currentStone].addListener(_updateCanProceed);
    _updateCanProceed();
  }

  void _updateCanProceed() {
    setState(() {
      _canProceed = _controllers[_currentStone].text.trim().isNotEmpty;
    });
  }

  Future<void> _onAnswerSubmitted() async {
    if (!_canProceed) return; // Do nothing if empty

    // Here you can store _controllers[_currentStone].text into database
    final answer = _controllers[_currentStone].text.trim();
    print("Answer for stone $_currentStone: $answer"); // example

    if (_currentStone < 2) {
      _hopController.forward(from: 0).then((_) {
        setState(() {
          _currentStone++;
          _controllers[_currentStone].addListener(_updateCanProceed);
          _updateCanProceed();
        });
        _hopController.value = 1.0;
      });
    } else {
      setState(() => _completed = true);
      _markCompleted();
      _showCompletionDialog();
    }
  }

  Future<void> _markCompleted() async {
    final provider = context.read<CBTProvider>();
    final assigned = provider.assigned.firstWhere(
    (a) => a.exerciseId == widget.exercise.id && a.childId == widget.childId,
    orElse: () => throw Exception('Assigned CBT not found for this exercise'),
  );

  await provider.markAsCompleted(widget.parentId, widget.childId, assigned.id);
  }

  void _showCompletionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Great job! 🌟"),
        content: const Text(
            "You’ve completed the Step Stone exercise!\nKeep moving forward!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to CBT page
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hopController.dispose();
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.blue[100],
      appBar: AppBar(title: Text(widget.exercise.title)),
      body: Stack(
        children: [
          // River background
          Positioned.fill(
            child: Image.asset('assets/cbt/confused/River_bg.png', fit: BoxFit.fill),
          ),

          // Stepping stones
          ...List.generate(3, (index) {
            final stone = stonePositions[index];
            return Positioned(
              left: screenWidth * stone.dx - 40,
              top: screenHeight * stone.dy - 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_currentStone == index && !_completed)
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                    ),
                  Image.asset(
                    'assets/cbt/confused/stone${index + 1}.png',
                    width: 80,
                    height: 80,
                  ),
                ],
              ),
            );
          }),

          // Frog stacked on stone with top-down hop effect (scale)
          AnimatedBuilder(
            animation: _hopAnimation,
            builder: (_, child) {
              final frogPos = stonePositions[_currentStone];

              // Scale: 1.0 -> 1.4 -> 1.0 for hop
              final scale = 1.0 + 0.4 * (1 - (_hopAnimation.value - 0.5).abs() * 2);

              // Shadow smaller when frog "jumps"
              final shadowScale = 1.0 - 0.3 * (1 - (_hopAnimation.value - 0.5).abs() * 2);

              return Positioned(
                left: screenWidth * frogPos.dx - 25,
                top: screenHeight * frogPos.dy - 30,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Shadow behind frog
                    Transform.scale(
                      scale: shadowScale,
                      child: Container(
                        width: 50,
                        height: 50, // flatter shadow
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                    // Frog image scaled for hop
                    Transform.scale(
                      scale: scale,
                      child: Image.asset(
                        'assets/cbt/confused/frog.png',
                        width: 50,
                        height: 50,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // Bottom floating dialog
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Material(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _prompts[_currentStone],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _controllers[_currentStone],
                      decoration: InputDecoration(
                        hintText: 'Type your answer here...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) => _onAnswerSubmitted(),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _onAnswerSubmitted,
                      child: const Text("Next"),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sparkle when completed
          if (_completed)
            Center(
              child: Lottie.asset(
                'assets/cbt/sparkle.json',
                width: 250,
                repeat: false,
              ),
            ),
        ],
      ),
    );
  }
}
