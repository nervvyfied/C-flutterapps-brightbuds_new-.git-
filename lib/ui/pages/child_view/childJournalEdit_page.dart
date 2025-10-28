import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/data/models/journal_model.dart';
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
  int _stars = 0;
  String _mood = "";
  int _step = 0;
  bool _isSaving = false;

  final _thankfulForController = TextEditingController();
  final _todayILearnedController = TextEditingController();
  final _todayITriedController = TextEditingController();
  final _bestPartOfDayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stars = widget.entry.stars;
    _mood = widget.entry.mood;
    _thankfulForController.text = widget.entry.thankfulFor;
    _todayILearnedController.text = widget.entry.todayILearned;
    _todayITriedController.text = widget.entry.todayITried;
    _bestPartOfDayController.text = widget.entry.bestPartOfDay;
  }

  @override
  void dispose() {
    _thankfulForController.dispose();
    _todayILearnedController.dispose();
    _todayITriedController.dispose();
    _bestPartOfDayController.dispose();
    super.dispose();
  }

  Future<void> _showSaveConfirmationDialog() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Save'),
      content: const Text('Are you sure you want to save changes to this entry?'),
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
    setState(() => _isSaving = true);

    final updatedEntry = widget.entry.copyWith(
      stars: _stars,
      mood: _mood,
      thankfulFor: _thankfulForController.text,
      todayILearned: _todayILearnedController.text,
      todayITried: _todayITriedController.text,
      bestPartOfDay: _bestPartOfDayController.text,
      createdAt: DateTime.now(),
    );

    final provider = Provider.of<JournalProvider>(context, listen: false);

    try {
      await provider.deleteEntry(widget.parentId, widget.childId, widget.entry.jid);
      await provider.addEntry(widget.parentId, widget.childId, updatedEntry);
      await provider.getMergedEntries(
        parentId: widget.parentId,
        childId: widget.childId,
      );

      Navigator.pop(context, true); // Go back to journal list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update entry: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}


  Future<void> _saveEdit() async {
    final updatedEntry = widget.entry.copyWith(
      stars: _stars,
      mood: _mood,
      thankfulFor: _thankfulForController.text,
      todayILearned: _todayILearnedController.text,
      todayITried: _todayITriedController.text,
      bestPartOfDay: _bestPartOfDayController.text,
      createdAt: DateTime.now(),
    );

    final provider = Provider.of<JournalProvider>(context, listen: false);

    try {
      await provider.deleteEntry(widget.parentId, widget.childId, widget.entry.jid);
      await provider.addEntry(widget.parentId, widget.childId, updatedEntry);
      await provider.getMergedEntries(
        parentId: widget.parentId,
        childId: widget.childId,
      );
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update entry: $e")),
      );
    }
  }

  Widget _buildStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return IconButton(
          icon: Icon(
            index < _stars ? Icons.star : Icons.star_border,
            color: const Color(0xFFF7D047),
            size: 40,
          ),
          onPressed: () => setState(() => _stars = index + 1),
        );
      }),
    );
  }

  Widget _buildMoodCard(String label, Color color, List<String> emotions, String icon) {
  final selected = _mood == label;
  return GestureDetector(
    onTap: () => setState(() => _mood = label),
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.9) : color.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? color : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/moods/$icon',
            width: 40,
            height: 40,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          ...emotions.map((e) => Text(
                e,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontSize: 12,
                ),
              )),
        ],
      ),
    ),
  );
}


  Widget _affirmationPage() {
      final moods = [
    {
      "label": "Calm",
      "color": const Color(0xFFA6C26F),
      "emotions": ["Calm", "Content", "Relaxed", "Peaceful"],
      "icon": "calm_icon.png",
    },
    {
      "label": "Sad",
      "color": const Color(0xFF57A0F3),
      "emotions": ["Sad", "Down", "Gloomy", "Hurt"],
      "icon": "sad_icon.png",
    },
    {
      "label": "Happy",
      "color": const Color(0xFFFECE00),
      "emotions": ["Happy", "Glad", "Joyful", "Delighted"],
      "icon": "happy_icon.png",
    },
    {
      "label": "Confused",
      "color": const Color(0xFFFC8B34),
      "emotions": ["Confused", "Hesitant", "Unsure", "Uncertain"],
      "icon": "confused_icon.png",
    },
    {
      "label": "Angry",
      "color": const Color(0xFFFD5C68),
      "emotions": ["Angry", "Upset", "Irritated", "Furious"],
      "icon": "angry_icon.png",
    },
    {
      "label": "Scared",
      "color": const Color(0xFF8657F3),
      "emotions": ["Scared", "Afraid", "Worried", "Terrified"],
      "icon": "scared_icon.png",
    },
  ];

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset('assets/general_bg.png', fit: BoxFit.cover),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Affirmation container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      "Affirmation of the Day:",
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "\"${widget.entry.affirmation}\"",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildStars(),
              const SizedBox(height: 16),

              // Mood grid with sub-emotions
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8657F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        "Because I'm...",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      physics: const NeverScrollableScrollPhysics(),
                      children: moods
                          .map((m) => _buildMoodCard(
                                m["label"] as String,
                                m["color"] as Color,
                                m["emotions"] as List<String>,
                                m["icon"] as String,
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: (_stars > 0 && _mood.isNotEmpty)
                    ? () => setState(() => _step = 1)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA6C26F),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Next"),
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
              // Thankful Section
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
                    const Text(
                      "Enter what you're thankful for",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    _buildInput(_thankfulForController, 2),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Good Things Section
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
                    const Text("Today I Learned...",
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    _buildInput(_todayILearnedController),
                    const SizedBox(height: 12),
                    const Text("Today I Tried...",
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    _buildInput(_todayITriedController),
                    const SizedBox(height: 12),
                    const Text("Best Part of My Day...",
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    _buildInput(_bestPartOfDayController),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _showSaveConfirmationDialog,
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
                label: Text(_isSaving ? "Saving..." : "Save Changes"),
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

  Widget _buildInput(TextEditingController controller, [int maxLines = 1]) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFA6C26F), width: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Journal Entry'),
        backgroundColor: const Color(0xFFA6C26F),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: _step == 0 ? _affirmationPage() : _journalFormPage(),
    );
  }
}
