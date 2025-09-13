import 'package:brightbuds_new/ui/pages/parent_view/parentHome_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentTaskList_page.dart';
import 'package:flutter/material.dart';

class ParentNavigationShell extends StatefulWidget {
  final String parentId;
  final String childId;

  const ParentNavigationShell({
    super.key,
    required this.parentId,
    required this.childId,
  });

  @override
  State<ParentNavigationShell> createState() => _ParentNavigationShellState();
}

class _ParentNavigationShellState extends State<ParentNavigationShell> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      ParentDashboardPage(parentId: widget.parentId, childId: widget.childId),
      ParentTaskListScreen(
        parentId: widget.parentId,
        childId: widget.childId,
      ),
      const PlaceholderPage(title: 'Account'),
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
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'Manage Quests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

// Placeholder Page Widget
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
