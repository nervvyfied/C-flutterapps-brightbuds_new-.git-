import 'package:brightbuds_new/cbt/pages/child_cbt_page.dart';
import 'package:brightbuds_new/data/models/child_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/ui/pages/child_view/childJournalList_page.dart';
import 'package:brightbuds_new/ui/pages/child_view/childTaskView_page.dart';
import 'package:brightbuds_new/aquarium/pages/aquarium_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '/cbt/providers/cbt_provider.dart';
import '/cbt/models/cbt_exercise_model.dart'; // if you have Hive types here

class ChildNavigationShell extends StatefulWidget {
  const ChildNavigationShell({super.key});

  @override
  State<ChildNavigationShell> createState() => _ChildNavigationShellState();
}

class _ChildNavigationShellState extends State<ChildNavigationShell> {
  int _selectedIndex = 0;

  List<Widget> _buildPages(String parentId, String childId, String childName) {
    return [
      ChildQuestsPage(parentId: parentId, childId: childId, childName: childName),
      JournalListPage(parentId: parentId, childId: childId),
      ChildCBTPage(childId:childId),
      AquariumPage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final child = auth.isChild ? auth.currentUserModel as ChildUser : null;

    final parentId = child?.parentUid ?? '';
    final childId = child?.cid ?? '';
    final childName = child?.name ?? 'Child';

    return Scaffold(
      body: _buildPages(parentId, childId, childName)[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Quests'),
          BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Journal'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: 'Power Pack'),
          BottomNavigationBarItem(icon: Icon(Icons.water), label: 'Aquarium'),
        ],
      ),
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
