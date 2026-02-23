import 'package:flutter/material.dart';

class LevelFeedbackDialog extends StatefulWidget {
  final int level;
  final void Function(int rating, String emoji, String notes) onSubmit;

  const LevelFeedbackDialog({
    super.key,
    required this.level,
    required this.onSubmit,
  });

  @override
  State<LevelFeedbackDialog> createState() => _LevelFeedbackDialogState();
}

class _LevelFeedbackDialogState extends State<LevelFeedbackDialog> {
  int selectedRating = 0;
  String selectedEmoji = '';
  String selectedIssue = '';

  final emojis = ['😞','😐','🙂','😃','🤩'];

  final List<String> lowRatingReasons = [
    "Too hard",
    "Too easy",
    "Confusing",
    "Not fun",
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      title: Column(
        children: [
          Text(
            "Level ${widget.level} Complete!",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "How was your experience?",
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          /// Emoji Selection (No Overflow Version)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: List.generate(emojis.length, (index) {
              final isSelected = selectedRating == index + 1;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    selectedRating = index + 1;
                    selectedEmoji = emojis[index];

                    if (selectedRating > 2) {
                      selectedIssue = '';
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.transparent,
                    border: isSelected
                        ? Border.all(color: Colors.blue, width: 2)
                        : null,
                  ),
                  child: Text(
                    emojis[index],
                    style: TextStyle(
                      fontSize: isSelected ? 38 : 32,
                    ),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 16),

          /// Conditional Follow-Up for Low Ratings
          if (selectedRating <= 2 && selectedRating != 0) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "What made it difficult?",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: lowRatingReasons.map((reason) {
                final isSelected = selectedIssue == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      selectedIssue = reason;
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: selectedRating == 0
              ? null
              : () {
                  widget.onSubmit(
                    selectedRating,
                    selectedEmoji,
                    selectedIssue, // now only structured reason
                  );
                  Navigator.of(context).pop();
                },
          child: const Text("Submit"),
        ),
      ],
    );
  }
}