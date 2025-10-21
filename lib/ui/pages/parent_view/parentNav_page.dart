import 'package:brightbuds_new/data/models/parent_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentAccount_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentHome_page.dart';
import 'package:brightbuds_new/ui/pages/parent_view/parentTaskList_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ParentNavigationShell extends StatefulWidget {
  const ParentNavigationShell({super.key});

  @override
  State<ParentNavigationShell> createState() => _ParentNavigationShellState();
}

class _ParentNavigationShellState extends State<ParentNavigationShell> {
  int _selectedIndex = 0;

  List<Widget> _buildPages(String parentId) {
    return [
      ParentAccountPage(parentId: parentId),
      ParentDashboardPage(parentId: parentId),
      ParentTaskListScreen(parentId: parentId),
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
    final parentId = auth.isParent ? (auth.currentUserModel as ParentUser).uid : '';

    return Scaffold(
      body: _buildPages(parentId)[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Manage Quests'),
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
