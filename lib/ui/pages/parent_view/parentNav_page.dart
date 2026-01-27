// ignore_for_file: file_names

import 'package:brightbuds_new/data/models/parent_model.dart'; // <- make sure this is the parent model
import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
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

  List<Widget> _buildPages({
    required String parentId,
    required String therapistId,
    required String creatorId,
    required String creatorType,
  }) {
    return [
      ParentDashboardPage(parentId: parentId),

      ParentTaskListScreen(
        parentId: parentId,
        therapistId: therapistId,
        creatorId: creatorId,
        creatorType: creatorType,
      ),
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

    // Redirect if not logged in or not a parent
    if (auth.currentUserModel == null || auth.currentUserModel is! ParentUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/parentAuth');
      });
      return const SizedBox.shrink();
    }

    final parent = auth.currentUserModel as ParentUser;

    final parentId = parent.uid;
    final creatorId = parent.uid;
    final creatorType = 'parent';
    final therapistId = parent.uid;

    final pages = _buildPages(
      parentId: parentId,
      therapistId: therapistId,
      creatorId: creatorId,
      creatorType: creatorType,
    );

    return Scaffold(
      body: pages[_selectedIndex],
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
    return Center(child: Text(title, style: const TextStyle(fontSize: 24)));
  }
}
