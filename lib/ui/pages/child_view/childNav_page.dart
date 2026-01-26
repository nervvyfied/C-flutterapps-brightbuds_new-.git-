// ignore_for_file: file_names

import 'package:brightbuds_new/cbt/pages/child_cbt_page.dart';
import 'package:brightbuds_new/data/managers/token_manager.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/notifiers/tokenNotifier.dart';
import 'package:brightbuds_new/data/notifiers/token_listener.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/data/providers/selected_child_provider.dart';
import 'package:brightbuds_new/data/providers/task_provider.dart';
import 'package:brightbuds_new/ui/pages/child_view/childJournalList_page.dart';
import 'package:brightbuds_new/ui/pages/child_view/childTaskView_page.dart';
import 'package:brightbuds_new/aquarium/pages/aquarium_page.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart'; // if you have Hive types here

class ChildNavigationShell extends StatefulWidget {
  const ChildNavigationShell({super.key});

  @override
  State<ChildNavigationShell> createState() => _ChildNavigationShellState();
}

class _ChildNavigationShellState extends State<ChildNavigationShell> {
  int _selectedIndex = 0;
  TokenNotifier? _tokenNotifier;

  List<Widget> _buildPages(String parentId, String childId, String childName) {
    final selectedChildProvider = context.read<SelectedChildProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      selectedChildProvider.setSelectedChild({
        'id': childId,
        'name': childName,
        'xp': 0,
        'unlockedDecor': [],
      });
    });
  
    return [
      ChildQuestsPage(parentId: parentId, childId: childId, childName: childName),
      JournalListPage(parentId: parentId, childId: childId),
      ChildCBTPage(childId: childId, parentId: parentId),
      AquariumPage(),
    ];
  }


  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final child = auth.isChild ? auth.currentUserModel as ChildUser : null;

    final parentId = child?.parentUid ?? '';
    final childId = child?.cid ?? '';
    final childName = child?.name ?? 'Child';

    return FutureBuilder(
      future: Hive.openBox('settings'),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final settingsBox = snapshot.data as Box;

        // ✅ Only create once
        _tokenNotifier ??= TokenNotifier(
          TokenManager(
            taskProvider: context.read<TaskProvider>(),
            settingsBox: settingsBox,
            childId: childId,
          ),
          settingsBox: settingsBox,
          childId: childId,
        );

        return ChangeNotifierProvider.value(
          value: _tokenNotifier!,
          child: TokenListener(
            child: Scaffold(
              body: _buildPages(parentId, childId, childName)[_selectedIndex],
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) => setState(() => _selectedIndex = index),
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Quests'),
                  BottomNavigationBarItem(icon: Icon(Icons.auto_stories), label: 'Journal'),
                  BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Power Pack'),
                  BottomNavigationBarItem(icon: Icon(Icons.bubble_chart), label: 'Aquarium'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Still useful for unfinished sections
class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: const TextStyle(fontSize: 24)),
    );
  }
}
