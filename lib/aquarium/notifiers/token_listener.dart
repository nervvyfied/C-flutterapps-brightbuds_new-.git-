import 'package:brightbuds_new/aquarium/notifiers/tokenDialog.dart';
import 'package:brightbuds_new/aquarium/notifiers/tokenNotifier.dart';
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

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = Provider.of<TokenNotifier>(context, listen: false);
      notifier.addListener(_showDialogOnNewTokens);
      notifier.checkAndNotify(); // check once on init
    });
  }

  void _showDialogOnNewTokens() {
    final notifier = Provider.of<TokenNotifier>(context, listen: false);
    if (notifier.newTasks.isEmpty) return;

    _confettiController.play();
    showDialog(
      context: context,
      builder: (_) => TokenDialog(tasks: notifier.newTasks, confettiController: _confettiController),
    );
  }

  @override
  void dispose() {
    _confettiController.dispose();
    final notifier = Provider.of<TokenNotifier>(context, listen: false);
    notifier.removeListener(_showDialogOnNewTokens);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
