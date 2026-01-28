// ignore_for_file: file_names

import 'package:brightbuds_new/data/models/therapist_model.dart';
import 'package:brightbuds_new/data/providers/auth_provider.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistHome_page.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistJournalView_page.dart';
import 'package:brightbuds_new/ui/pages/therapist_view/therapistTaskList_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/providers/selected_child_provider.dart';

class TherapistNavigationShell extends StatefulWidget {
  const TherapistNavigationShell({super.key});

  @override
  State<TherapistNavigationShell> createState() =>
      _TherapistNavigationShellState();
}

class _TherapistNavigationShellState extends State<TherapistNavigationShell> {
  int _selectedIndex = 0;

  List<Widget> _buildPages({
    required String therapistId,
    required String creatorId,
    required String? parentId,
    required String creatorType,
    required String childId,
  }) {
    return [
      TherapistDashboardPage(therapistId: therapistId, parentId: parentId!),

      TherapistTaskListScreen(
        therapistId: therapistId,
        creatorId: creatorId,
        creatorType: creatorType,
        parentId: parentId,
      ),

      childId.isNotEmpty
          ? TherapistJournalListPage(childId: childId, parentId: parentId)
          : const PlaceholderPage(title: 'No child selected'),
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
    final selectedChildProvider = Provider.of<SelectedChildProvider>(context);

    // Redirect if not logged in
    if (auth.currentUserModel == null ||
        auth.currentUserModel is! TherapistUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/therapistAuth');
      });
      return const SizedBox.shrink();
    }

    final therapist = auth.currentUserModel as TherapistUser;

    final therapistId = therapist.uid;
    final creatorId = therapist.uid;
    final creatorType = 'therapist';
    final parentId = therapist.uid;

    final childId =
        selectedChildProvider.selectedChild?['cid']?.toString() ?? '';

    final pages = _buildPages(
      therapistId: therapistId,
      creatorId: creatorId,
      creatorType: creatorType,
      childId: childId,
      parentId: parentId,
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
          BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.pages), label: 'Journal'),
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(title, style: const TextStyle(fontSize: 24)));
  }
}
