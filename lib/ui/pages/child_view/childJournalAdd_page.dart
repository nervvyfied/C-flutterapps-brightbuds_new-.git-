import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '/data/models/journal_model.dart';
import '../../../data/providers/journal_provider.dart';
import 'dart:math';

class JournalAddPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const JournalAddPage({
    super.key,
    required this.parentId,
    required this.childId,
  });

  @override
  State<JournalAddPage> createState() => _JournalAddPageState();
}

class _JournalAddPageState extends State<JournalAddPage> {
  int _stars = 0;
  String _mood = "";
  int _step = 0; // 0 = affirmation page, 1 = journal form page
  bool _isSaving = false;

  final _thankfulForController = TextEditingController();
  final _todayILearnedController = TextEditingController();
  final _todayITriedController = TextEditingController();
  final _bestPartOfDayController = TextEditingController();

  String _dailyAffirmation = "I am amazing";

  final List<String> _affirmations = [
    "I am capable of amazing things.",
    "Today, I choose happiness.",
    "I grow stronger every day.",
    "I am proud of who I am becoming.",
    "I radiate positivity and kindness.",
  ];

  @override
  void initState() {
    super.initState();
    _dailyAffirmation = _affirmations[Random().nextInt(_affirmations.length)];
  }

  Future<void> _showSaveConfirmationDialog() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Save'),
      content: const Text('Are you sure you want to save this journal entry?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    // Optionally disable the button while saving
    await _saveEntry();
  }
}


  Future<void> _saveEntry() async {
    setState(() => _isSaving = true);

    final uuid = const Uuid().v4();

    final newEntry = JournalEntry(
      jid: uuid,
      cid: widget.childId,
      entryDate: DateTime.now(),
      stars: _stars,
      affirmation: _dailyAffirmation,
      mood: _mood,
      thankfulFor: _thankfulForController.text,
      todayILearned: _todayILearnedController.text,
      todayITried: _todayITriedController.text,
      bestPartOfDay: _bestPartOfDayController.text,
      createdAt: DateTime.now(),
    );

    try {
      await Provider.of<JournalProvider>(context, listen: false)
          .addEntry(widget.parentId, widget.childId, newEntry);

      await Provider.of<JournalProvider>(context, listen: false)
          .getMergedEntries(
            parentId: widget.parentId,
            childId: widget.childId,
          );

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save entry: $e")),
      );
    }
    finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _thankfulForController.dispose();
    _todayILearnedController.dispose();
    _todayITriedController.dispose();
    _bestPartOfDayController.dispose();
    super.dispose();
  }

  Widget _buildStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            index < _stars ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 40,
          ),
          onPressed: () {
            setState(() => _stars = index + 1);
          },
        );
      }),
    );
  }

  Widget _buildMoodCard(String mood, List<String> emotions, Color color, String assetName) {
  final selected = _mood == mood;

  return GestureDetector(
    onTap: () => setState(() => _mood = mood),
    child: IntrinsicHeight(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.7) : color.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFA6C26F) : Colors.transparent,
            width: 3,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFFA6C26F).withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 🟢 let it shrink-wrap
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/moods/$assetName', width: 40, height: 40),
            const SizedBox(height: 4),
            ...emotions.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    e,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}




  Widget _affirmationPage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/general_bg.png', fit: BoxFit.cover),
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Daily Affirmation Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      "Affirmation of the Day:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "\"$_dailyAffirmation\"",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Stars Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "How do you rate your day?",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    _buildStars(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Mood selection container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8657F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Because I'm..",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildMoodCard("Calm", ["Calm", "Relaxed", "Peaceful"], const Color(0xFFA6C26F), "calm_icon.png"),
                        _buildMoodCard("Sad", ["Sad", "Gloomy", "Hurt"], const Color(0xFF57A0F3), "sad_icon.png"),
                        _buildMoodCard("Happy", ["Happy", "Glad", "Joyful"], const Color(0xFFFECE00), "happy_icon.png"),
                        _buildMoodCard("Confused", ["Confused", "Hesitant", "Unsure"], const Color(0xFFFC8B34), "confused_icon.png"),
                        _buildMoodCard("Angry", ["Angry", "Upset", "Irritated"], const Color(0xFFFD5C68), "angry_icon.png"),
                        _buildMoodCard("Scared", ["Scared", "Afraid", "Worried"], const Color(0xFF8657F3), "scared_icon.png"),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: (_stars > 0 && _mood.isNotEmpty)
                    ? () => setState(() => _step = 1)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA6C26F),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Next", style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _journalFormPage() {
  return Stack(
    fit: StackFit.expand,
    children: [
      Image.asset('assets/general_bg.png', fit: BoxFit.cover),
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Thankful For Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8657F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "I'm Thankful For",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Enter what you're thankful for",
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _thankfulForController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Good Things / Journal Form Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFA6C26F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "Good Things That Happened Today",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Today I Learned
                  Text(
                    "Today I Learned...",
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _todayILearnedController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Today I Tried
                  Text(
                    "Today I Tried...",
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _todayITriedController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Best Part of Day
                  Text(
                    "Best Part of My Day...",
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _bestPartOfDayController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Save Button
            ElevatedButton.icon(
              onPressed: _isSaving ? null : () => _showSaveConfirmationDialog(),
              icon: _isSaving 
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? "Saving..." : "Save Entry"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: const Color(0xFFA6C26F),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Journal Entry'),
        automaticallyImplyLeading: false,
      ),
      body: _step == 0 ? _affirmationPage() : _journalFormPage(),
    );
  }
}
