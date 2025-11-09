import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/journal_model.dart';
import '../../../data/providers/journal_provider.dart';

class JournalEditPage extends StatefulWidget {
  final String parentId;
  final String childId;
  final JournalEntry entry;

  const JournalEditPage({
    super.key,
    required this.parentId,
    required this.childId,
    required this.entry,
  });

  @override
  State<JournalEditPage> createState() => _JournalEditPageState();
}

class _JournalEditPageState extends State<JournalEditPage> {
  late int _stars;
  late String _mood;
  int _step = 0;
  bool _isSaving = false;

  late TextEditingController _thankfulForController;
  late TextEditingController _todayILearnedController;
  late TextEditingController _todayITriedController;
  late TextEditingController _bestPartOfDayController;

  late String _dailyAffirmation;

  @override
  void initState() {
    super.initState();
    _stars = widget.entry.stars;
    _mood = widget.entry.mood;
    _dailyAffirmation = widget.entry.affirmation;

    _thankfulForController = TextEditingController(text: widget.entry.thankfulFor);
    _todayILearnedController = TextEditingController(text: widget.entry.todayILearned);
    _todayITriedController = TextEditingController(text: widget.entry.todayITried);
    _bestPartOfDayController = TextEditingController(text: widget.entry.bestPartOfDay);
  }

  Future<void> _showSaveConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Update'),
        content: const Text('Are you sure you want to update this journal entry?'),
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
      await _updateEntry();
    }
  }

  Future<void> _updateEntry() async {
    setState(() => _isSaving = true);

    final updatedEntry = widget.entry.copyWith(
      stars: _stars,
      mood: _mood,
      affirmation: _dailyAffirmation,
      thankfulFor: _thankfulForController.text,
      todayILearned: _todayILearnedController.text,
      todayITried: _todayITriedController.text,
      bestPartOfDay: _bestPartOfDayController.text,
      createdAt: DateTime.now(),
    );

    try {
      await Provider.of<JournalProvider>(context, listen: false)
          .updateEntry(widget.parentId, widget.childId, updatedEntry);

      await Provider.of<JournalProvider>(context, listen: false)
          .getMergedEntries(parentId: widget.parentId, childId: widget.childId);

      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update entry: $e")),
      );
    } finally {
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
          onPressed: () => setState(() => _stars = index + 1),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/moods/$assetName', width: 40, height: 40),
              const SizedBox(height: 4),
              ...emotions.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        e,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )),
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
                      "Affirmation of the Day:",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "\"$_dailyAffirmation\"",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
                    _buildStars(),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                        _buildMoodCard("Calm", ["Calm", "Relaxed", "Peaceful"],
                            const Color(0xFFA6C26F), "calm_icon.png"),
                        _buildMoodCard("Sad", ["Sad", "Gloomy", "Hurt"],
                            const Color(0xFF57A0F3), "sad_icon.png"),
                        _buildMoodCard("Happy", ["Happy", "Glad", "Joyful"],
                            const Color(0xFFFECE00), "happy_icon.png"),
                        _buildMoodCard("Confused",
                            ["Confused", "Hesitant", "Unsure"],
                            const Color(0xFFFC8B34), "confused_icon.png"),
                        _buildMoodCard("Angry", ["Angry", "Upset", "Irritated"],
                            const Color(0xFFFD5C68), "angry_icon.png"),
                        _buildMoodCard("Scared", ["Scared", "Afraid", "Worried"],
                            const Color(0xFF8657F3), "scared_icon.png"),
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
              // Thankful For
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
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
              // Good Things
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField("Today I Learned...", _todayILearnedController),
                    const SizedBox(height: 12),
                    _buildTextField("Today I Tried...", _todayITriedController),
                    const SizedBox(height: 12),
                    _buildTextField("Best Part of My Day...", _bestPartOfDayController),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _showSaveConfirmationDialog,
                icon: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? "Saving..." : "Save Changes"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA6C26F),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Journal Entry'),
        automaticallyImplyLeading: false,
      ),
      body: _step == 0 ? _affirmationPage() : _journalFormPage(),
    );
  }
}
