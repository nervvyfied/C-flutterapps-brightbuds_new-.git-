import 'package:brightbuds_new/ui/pages/child_view/childJournalList_page.dart';
import 'package:brightbuds_new/ui/pages/child_view/childTaskView_page.dart';
import 'package:flutter/material.dart';

class ChildNavigationShell extends StatefulWidget {
  final String childId;
  final String childName;
  final String parentId;

  const ChildNavigationShell({
    super.key,
    required this.childId,
    required this.childName,
    required this.parentId,
  });

  @override
  State<ChildNavigationShell> createState() => _ChildNavigationShellState();
}

class _ChildNavigationShellState extends State<ChildNavigationShell> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      ChildQuestsPage(
        childId: widget.childId,
        childName: widget.childName,
        parentId: widget.parentId,
      ),
      JournalListPage(childId: widget.childId, parentId: widget.parentId,), // ✅ Journal is live now
      const PlaceholderPage(title: 'Power Pack'),
      const PlaceholderPage(title: 'Aquarium'),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.task),
            label: 'Quests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.book),
            label: 'Journal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt),
            label: 'Power Pack',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.water),
            label: 'Aquarium',
          ),
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
