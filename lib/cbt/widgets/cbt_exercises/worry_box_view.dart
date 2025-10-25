import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../models/cbt_exercise_model.dart';
import '../../providers/cbt_provider.dart';

class WorryBoxView extends StatefulWidget {
  final CBTExercise exercise;
  final String childId;
  final String parentId;

  const WorryBoxView({super.key, required this.exercise, required this.childId, required this.parentId});

  @override
  State<WorryBoxView> createState() => _WorryBoxViewState();
}

class _WorryBoxViewState extends State<WorryBoxView> with TickerProviderStateMixin {
  final TextEditingController _worryController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  late AnimationController _noteDropController;
  late AnimationController _noteFadeController;
  late AnimationController _lidController;
  bool _showInputModal = true;
  bool _showNoteDrop = false;
  bool _showLid = false;
  bool _showLockModal = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    // Slower drop (1 sec)
    _noteDropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Note fade-out after drop (0.6 sec)
    _noteFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Lid slide + fade (0.8 sec)
    _lidController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  Future<void> _submitWorry() async {
    if (_worryController.text.trim().isEmpty) return;

    setState(() => _showInputModal = false);

    // Show note drop
    setState(() => _showNoteDrop = true);
    await _noteDropController.forward();

    // Fade out note before lid animation
    await _noteFadeController.forward();
    setState(() => _showNoteDrop = false);

    // Show lid after note disappeared
    setState(() => _showLid = true);
    await _lidController.forward();

    // Show lock modal
    setState(() => _showLockModal = true);
  }

  Future<void> _onLockConfirmed() async {
    setState(() => _showLockModal = false);

    final provider = context.read<CBTProvider>();
    final assigned = provider.assigned.firstWhere(
    (a) => a.exerciseId == widget.exercise.id && a.childId == widget.childId,
    orElse: () => throw Exception('Assigned CBT not found for this exercise'),
  );

  await provider.markAsCompleted(widget.parentId, widget.childId, assigned.id);

    setState(() => _completed = true);
    _showCompletionDialog();
  }

  void _showCompletionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Well done! 💖"),
        content: const Text(
          "You’ve safely stored away your worry.\nYou are safe, you are cared for, and you can handle this.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _noteDropController.dispose();
    _noteFadeController.dispose();
    _lidController.dispose();
    _audioPlayer.dispose();
    _worryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
  backgroundColor: Colors.lightBlue[50],
  appBar: AppBar(title: Text(widget.exercise.title)),
  resizeToAvoidBottomInset: true, // ✅ adjust for keyboard
  body: SafeArea(
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Box centered
        Positioned(
          top: screenHeight * 0.3,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Box body
              Image.asset('assets/cbt/scared/box_body.png', width: screenWidth * 0.4),

              // Note drop animation
              if (_showNoteDrop)
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -1),
                    end: const Offset(0, 0),
                  ).animate(CurvedAnimation(
                    parent: _noteDropController,
                    curve: Curves.easeOut,
                  )),
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_noteFadeController),
                    child: Image.asset(
                      'assets/cbt/scared/paper_note.png',
                      width: screenWidth * 0.28,
                    ),
                  ),
                ),

              // Lid animation
              if (_showLid)
                Positioned(
                  top: -screenWidth * 0.03,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.5),
                      end: const Offset(0, 0),
                    ).animate(CurvedAnimation(
                      parent: _lidController,
                      curve: Curves.easeOut,
                    )),
                    child: FadeTransition(
                      opacity: _lidController,
                      child: Image.asset(
                        'assets/cbt/scared/box_lid.png',
                        width: screenWidth * 0.42,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Input modal
        // Input modal
if (_showInputModal)
  Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ), // adjust for keyboard height
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.4, // max modal height
            ),
            child: SingleChildScrollView(
              reverse: true, // keep focus on bottom
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _worryController,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,        // starts with 1 line
                    maxLines: 10,       // grows up to 10 lines
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: "Write your worry here...",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _submitWorry,
                    child: const Text("Put in Box"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),

        // Heart lock modal
        if (_showLockModal)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/cbt/scared/heart_lock.png',
                      width: screenWidth * 0.25,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Your worry is safely stored away.\nYou are safe, cared for, and can handle this.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _onLockConfirmed,
                      child: const Text("OK"),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  ),
);
  }
}
