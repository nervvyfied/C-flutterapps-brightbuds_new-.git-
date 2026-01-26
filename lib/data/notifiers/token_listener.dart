import 'package:brightbuds_new/data/models/task_model.dart';
import 'package:brightbuds_new/data/notifiers/tokenDialog.dart';
import 'package:brightbuds_new/data/notifiers/tokenNotifier.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:confetti/confetti.dart';

class TokenListener extends StatefulWidget {
  final Widget child;
  const TokenListener({required this.child, super.key});

  @override
  State<TokenListener> createState() => _TokenListenerState();
}

class _TokenListenerState extends State<TokenListener> {
  late ConfettiController _confettiController;
  bool _dialogShown = false; // prevent double popups

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));

    // ✅ Fetch unseen tasks after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = Provider.of<TokenNotifier>(context, listen: false);
      final unseenTasks = await notifier.checkAndNotify();

      if (unseenTasks.isNotEmpty) {
        _showTokenDialog(context, notifier);
      }
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _showTokenDialog(BuildContext context, TokenNotifier notifier) async {
    if (_dialogShown || notifier.newTasks.isEmpty) return;
    _dialogShown = true;

    _confettiController.play();

    // Copy the current tasks to display
    final tasksToShow = List<TaskModel>.from(notifier.newTasks);

    // Wait a tiny delay to ensure the context is ready in release mode
    await Future.delayed(const Duration(milliseconds: 50));

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => XPDialog(
        tasks: tasksToShow,
        confettiController: _confettiController,
      ),
    );

    // Mark tasks as seen AFTER the dialog closes
    final unseenKey = 'seen_verified_tasks_${notifier.childId}';
    final seenIds =
        List<String>.from(notifier.settingsBox.get(unseenKey, defaultValue: []));
    seenIds.addAll(tasksToShow.map((t) => t.id));
    await notifier.settingsBox.put(unseenKey, seenIds);

    notifier.clearNewTasks();
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TokenNotifier>(
      builder: (context, notifier, _) {
        // Schedule dialog after the frame to avoid build-time issues
        if (notifier.newTasks.isNotEmpty && !_dialogShown) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showTokenDialog(context, notifier);
          });
        }
        return widget.child;
      },
    );
  }
}
