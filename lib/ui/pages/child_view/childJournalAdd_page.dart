import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '/data/models/journal_model.dart';
import '../../../data/providers/journal_provider.dart';

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

  // Controllers for journal text
  final _thankfulForController = TextEditingController();
  final _todayILearnedController = TextEditingController();
  final _todayITriedController = TextEditingController();
  final _bestPartOfDayController = TextEditingController();

  // ---------------- SAVE ENTRY ----------------
  Future<void> _saveEntry() async {
    final uuid = const Uuid().v4();

    final newEntry = JournalEntry(
      jid: uuid,
      cid: widget.childId,
      entryDate: DateTime.now(),
      stars: _stars,
      affirmation: "I am amazing",
      mood: _mood,
      thankfulFor: _thankfulForController.text,
      todayILearned: _todayILearnedController.text,
      todayITried: _todayITriedController.text,
      bestPartOfDay: _bestPartOfDayController.text,
      createdAt: DateTime.now(),
    );

    // Save via JournalProvider (which calls repository)
    await Provider.of<JournalProvider>(context, listen: false)
        .addEntry(widget.parentId, widget.childId, newEntry);

    Navigator.pop(context); // close page
  }

  @override
  void dispose() {
    _thankfulForController.dispose();
    _todayILearnedController.dispose();
    _todayITriedController.dispose();
    _bestPartOfDayController.dispose();
    super.dispose();
  }

  // ---------------- UI BUILDERS ----------------
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

  Widget _buildMoodButtons() {
    final moods = [
      {"label": "Calm", "emoji": "😊"},
      {"label": "Sad", "emoji": "😢"},
      {"label": "Happy", "emoji": "😃"},
      {"label": "Confused", "emoji": "😕"},
      {"label": "Angry", "emoji": "😡"},
      {"label": "Scared", "emoji": "😨"},
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: moods.map((m) {
        final selected = _mood == m["label"];
        return ChoiceChip(
          label: Text("${m["emoji"]} ${m["label"]}"),
          selected: selected,
          onSelected: (_) {
            setState(() => _mood = m["label"]!);
          },
          selectedColor: Colors.blue.shade100,
        );
      }).toList(),
    );
  }

  Widget _affirmationPage() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          "I am amazing",
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        _buildStars(),
        const SizedBox(height: 20),
        const SizedBox(height: 20),
        _buildMoodButtons(),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: (_stars > 0 && _mood.isNotEmpty)
              ? () => setState(() => _step = 1)
              : null,
          child: const Text("Next"),
        ),
      ],
    );
  }

  Widget _journalFormPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("I'm thankful for:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _thankfulForController,
            decoration: const InputDecoration(
              hintText: "Enter what you're thankful for",
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          const Text("Good things that happened today",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _todayILearnedController,
            decoration: const InputDecoration(
              hintText: "Today I Learned...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _todayITriedController,
            decoration: const InputDecoration(
              hintText: "Today I Tried...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bestPartOfDayController,
            decoration: const InputDecoration(
              hintText: "Best part of my day...",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _saveEntry,
            icon: const Icon(Icons.save),
            label: const Text("Save Entry"),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- MAIN BUILD ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Journal Entry'),
      automaticallyImplyLeading: false,),
      body: Center(
        child: _step == 0 ? _affirmationPage() : _journalFormPage(),
      ),
    );
  }
}
