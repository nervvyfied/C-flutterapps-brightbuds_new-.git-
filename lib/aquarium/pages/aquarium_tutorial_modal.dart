import 'package:flutter/material.dart';

class AquariumTutorialModal extends StatefulWidget {
  final VoidCallback onComplete;
  const AquariumTutorialModal({super.key, required this.onComplete});

  @override
  State<AquariumTutorialModal> createState() => _AquariumTutorialModalState();
}

class _AquariumTutorialModalState extends State<AquariumTutorialModal> {
  int currentStep = 0;

  final List<Map<String, String>> tutorialSteps = [
    {
      'title': 'Welcome to Your Aquarium! 🐠',
      'desc': 'Take care of your aquarium by cleaning, feeding, and decorating it. Let’s get started!',
      'asset': 'assets/tutorial/tutorial1.png',
    },
    {
      'title': 'Cleaning the Tank 🧽',
      'desc': 'Simply drag the sponge around the tank to clean the dirt and keep your fishes happy!',
      'asset': 'assets/tutorial/tutorial2.png',
    },
    {
      'title': 'Feeding the Fish 🍽️',
      'desc': 'Drag the fish food around the tank to feed your fish. They’ll swim toward the pellets!',
      'asset': 'assets/tutorial/tutorial3.png',
    },
    {
      'title': 'Earning Tokens 💰',
      'desc': 'Complete daily tasks to earn tokens! Tokens are used to buy new decors and fishes.',
      'asset': 'assets/tutorial/tutorial4.png',
    },
    {
      'title': 'Buying Items 🏪',
      'desc': 'Open the Store to buy decors and fish. Use your tokens to expand your aquarium!',
      'asset': 'assets/tutorial/tutorial5.png',
    },
    {
      'title': 'Using the Inventory 📦',
      'desc': 'Check your Inventory to see your purchased items. Tap “Place” to add them into your tank!',
      'asset': 'assets/tutorial/tutorial6.png',
    },
    {
      'title': 'Editing the Tank 🧰',
      'desc': 'Tap the “Edit Mode” button to rearrange, sell, or store decors before saving changes.',
      'asset': 'assets/tutorial/tutorial7.png',
    },
    {
      'title': 'Achievements 🏆',
      'desc': 'Visit your Achievements to view unlockables and milestones as you progress!',
      'asset': 'assets/tutorial/tutorial8.png',
    },
    {
      'title': 'You’re All Set! 🌊',
      'desc': 'Enjoy your aquarium and keep it healthy. You can reopen this tutorial anytime using the “?” button.',
    },
  ];

  void _next() {
    if (currentStep < tutorialSteps.length - 1) {
      setState(() => currentStep++);
    } else {
      widget.onComplete();
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (currentStep > 0) setState(() => currentStep--);
  }

  @override
  Widget build(BuildContext context) {
    final step = tutorialSteps[currentStep];
    final total = tutorialSteps.length;

    return Dialog(
      backgroundColor: Colors.black.withOpacity(0.7),
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(step['title']!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (step.containsKey('asset'))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Image.asset(step['asset']!, height: 150, fit: BoxFit.contain),
              ),
            Text(step['desc']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (currentStep > 0)
                  ElevatedButton(
                    onPressed: _prev,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[400]),
                    child: const Text('Back'),
                  )
                else
                  const SizedBox(width: 80),
                Text('${currentStep + 1} / $total'),
                ElevatedButton(
                  onPressed: _next,
                  child: Text(currentStep == total - 1 ? 'Finish' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
