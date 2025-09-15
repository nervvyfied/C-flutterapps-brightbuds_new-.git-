import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '/data/models/journal_model.dart';
import '/providers/journal_provider.dart';
import 'childJournalAdd_page.dart';

class JournalListPage extends StatefulWidget {
  final String parentId;
  final String childId;

  const JournalListPage({
    super.key,
    required this.parentId,
    required this.childId,
  });

  @override
  State<JournalListPage> createState() => _JournalListPageState();
}

class _JournalListPageState extends State<JournalListPage> {
  @override
  Widget build(BuildContext context) {
    final journalProvider = Provider.of<JournalProvider>(context);
    final entries = journalProvider.getEntries(widget.parentId, widget.childId);

    return Scaffold(
      appBar: AppBar(title: const Text("My Journal")),
      body: entries.isEmpty
          ? const Center(child: Text("No journal entries yet"))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final formattedDate = DateFormat('yMMMd').format(entry.entryDate);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(
                      formattedDate,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text("Stars: ${entry.stars} | Mood: ${entry.mood}"),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          // Navigate to Add Journal Page with parentId and childId
          final refreshed = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JournalAddPage(
                parentId: widget.parentId,
                childId: widget.childId,
              ),
            ),
          );

          if (refreshed == true) {
            setState(() {}); // refresh list after save
          }
        },
      ),
    );
  }
}
