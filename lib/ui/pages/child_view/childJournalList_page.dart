import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '/data/models/journal_model.dart';
import '../../../data/providers/journal_provider.dart';
import 'childJournalAdd_page.dart';
import 'childJournalEdit_page.dart';

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
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadOfflineThenSync();
  }

  Future<void> _loadOfflineThenSync() async {
    final journalProvider = Provider.of<JournalProvider>(
      context,
      listen: false,
    );

    // 1️⃣ Load Hive data first (instant)
    await journalProvider.loadEntries(
      parentId: widget.parentId,
      childId: widget.childId,
    );

    // 2️⃣ Immediately update UI
    setState(() => _isLoading = false);

    // 3️⃣ Sync in background, only if Hive is empty or offline changes exist
    _syncWithOnline();
  }

  Future<void> _syncWithOnline() async {
    final journalProvider = Provider.of<JournalProvider>(
      context,
      listen: false,
    );

    setState(() => _isSyncing = true);
    try {
      await journalProvider.pushPendingChanges(widget.parentId, widget.childId);
      // Reload entries after syncing
      await journalProvider.loadEntries(
        parentId: widget.parentId,
        childId: widget.childId,
      );
      setState(() {}); // Refresh UI after sync
    } catch (e) {
      debugPrint("⚠️ Sync failed: $e");
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<bool?> _showPreviewDialog(JournalEntry entry) async {
    final journalProvider = Provider.of<JournalProvider>(
      context,
      listen: false,
    );

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Preview - ${DateFormat('yMMMd').format(entry.entryDate)}"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Stars: ${entry.stars}"),
              Text("Mood: ${entry.mood}"),
              Text("Affirmation: ${entry.affirmation}"),
              Text("Thankful For: ${entry.thankfulFor}"),
              Text("Today I Learned: ${entry.todayILearned}"),
              Text("Today I Tried: ${entry.todayITried}"),
              Text("Best Part Of Day: ${entry.bestPartOfDay}"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Edit"),
          ),
          TextButton(
            onPressed: () async {
              await journalProvider.deleteEntry(
                widget.parentId,
                widget.childId,
                entry.jid,
              );

              // Optimistic UI update
              setState(() {});

              // Reload Hive data just in case
              await journalProvider.loadEntries(
                parentId: widget.parentId,
                childId: widget.childId,
              );

              Navigator.of(context).pop(false);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journalProvider = Provider.of<JournalProvider>(context);
    final entries = journalProvider.getEntries(widget.childId);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Journal"),
        automaticallyImplyLeading: false,
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Sync Now",
            onPressed: _syncWithOnline,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("Add Journal"),
                      onPressed: () async {
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
                          // Optimistic UI update
                          setState(() {});
                          await journalProvider.loadEntries(
                            parentId: widget.parentId,
                            childId: widget.childId,
                          );
                        }
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(child: Text("No journal entries yet"))
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                title: Text(
                                  DateFormat('yMMMd').format(entry.entryDate),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  "Stars: ${entry.stars} | Mood: ${entry.mood}",
                                ),
                                onTap: () async {
                                  final edit = await _showPreviewDialog(entry);
                                  if (edit == true) {
                                    final edited = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => JournalEditPage(
                                          parentId: widget.parentId,
                                          childId: widget.childId,
                                          entry: entry,
                                        ),
                                      ),
                                    );
                                    if (edited == true) {
                                      setState(() {});
                                      await journalProvider.loadEntries(
                                        parentId: widget.parentId,
                                        childId: widget.childId,
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
