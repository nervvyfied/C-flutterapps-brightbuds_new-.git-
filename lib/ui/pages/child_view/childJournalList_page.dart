import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '/data/models/journal_model.dart';
import '../../../data/providers/journal_provider.dart';
import 'childJournalAdd_page.dart';
import 'childJournalEdit_page.dart';
import 'package:brightbuds_new/utils/network_helper.dart';

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
  bool _isOffline = false;

  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeData());
  }

  Future<void> _checkConnectivity() async {
    final online = await NetworkHelper.isOnline();
    if (!mounted) return;
    setState(() => _isOffline = !online);
  }

  Future<void> _initializeData() async {
    final journalProvider = Provider.of<JournalProvider>(context, listen: false);
    setState(() => _isLoading = true);

    await _checkConnectivity();

    await journalProvider.getMergedEntries(
      parentId: widget.parentId,
      childId: widget.childId,
    );

    final entries = journalProvider.getEntries(widget.childId);
    if (entries.isNotEmpty) {
      _selectedMonth = DateTime(entries.first.entryDate.year, entries.first.entryDate.month);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _syncWithCloud() async {
    final journalProvider = Provider.of<JournalProvider>(context, listen: false);
    setState(() => _isSyncing = true);

    await _checkConnectivity();

    if (!_isOffline) {
      try {
        await journalProvider.pushPendingChanges(widget.parentId, widget.childId);
        await journalProvider.getMergedEntries(
          parentId: widget.parentId,
          childId: widget.childId,
        );
      } catch (e) {
        debugPrint('⚠️ Journal sync failed: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isSyncing = false);
  }

  List<JournalEntry> _filterEntries(List<JournalEntry> entries) {
    if (entries.isEmpty) return [];
    return entries.where((entry) {
      final matchMonth =
          entry.entryDate.year == _selectedMonth.year &&
          entry.entryDate.month == _selectedMonth.month;
      if (_selectedDay != null) {
        return matchMonth && entry.entryDate.day == _selectedDay!.day;
      }
      return matchMonth;
    }).toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  }

  void _pickMonth() {
    final journalProvider = Provider.of<JournalProvider>(context, listen: false);
    final entries = journalProvider.getEntries(widget.childId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select Day", style: Theme.of(context).textTheme.titleMedium),
              SizedBox(
                height: 400,
                child: TableCalendar(
                  firstDay: DateTime(DateTime.now().year - 5),
                  lastDay: DateTime.now(),
                  focusedDay: _selectedMonth,
                  calendarFormat: CalendarFormat.month,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: (day) {
                    return entries
                        .where((e) =>
                            e.entryDate.year == day.year &&
                            e.entryDate.month == day.month &&
                            e.entryDate.day == day.day)
                        .toList();
                  },
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _selectedMonth = DateTime(selectedDay.year, selectedDay.month);
                    });
                    Navigator.pop(context);
                  },
                  calendarBuilders: CalendarBuilders(
                    markerBuilder: (context, date, events) {
                      if (events.isNotEmpty) {
                        return Positioned(
                          bottom: 1,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoodIcon(String mood) {
    String assetPath = 'assets/moods/';
    switch (mood.toLowerCase()) {
      case 'happy':
        assetPath += 'happy_icon.png';
        break;
      case 'calm':
        assetPath += 'calm_icon.png';
        break;
      case 'sad':
        assetPath += 'sad_icon.png';
        break;
      case 'confused':
        assetPath += 'confused_icon.png';
        break;
      case 'angry':
        assetPath += 'angry_icon.png';
        break;
      case 'scared':
        assetPath += 'scared_icon.png';
        break;
      default:
        assetPath += 'happy_icon.png';
    }
    return Image.asset(assetPath, width: 32, height: 32);
  }

  Future<void> _showPreviewDialog(JournalEntry entry) async {
    final journalProvider = Provider.of<JournalProvider>(context, listen: false);

    await showDialog(
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
              const SizedBox(height: 8),
              Text(
                "Created: ${DateFormat('yMMMd – kk:mm').format(entry.entryDate)}",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
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
                await journalProvider.getMergedEntries(
                  parentId: widget.parentId,
                  childId: widget.childId,
                );
              }
              if (mounted) setState(() {});
              Navigator.pop(context);
            },
            child: const Text("Edit"),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JournalProvider>(
      builder: (context, journalProvider, _) {
        final entries = _filterEntries(journalProvider.getEntries(widget.childId));

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                    _selectedDay = null;
                  }),
                ),
                GestureDetector(
                  onTap: _pickMonth,
                  child: Text(
                    _selectedDay != null
                        ? "${DateFormat.yMMMd().format(_selectedDay!)} ▼"
                        : "${DateFormat.yMMM().format(_selectedMonth)} ▼",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                    _selectedDay = null;
                  }),
                ),
              ],
            ),
            actions: [
              if (_isSyncing)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              IconButton(icon: const Icon(Icons.sync), onPressed: _syncWithCloud),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_isOffline)
                      Container(
                        width: double.infinity,
                        color: Colors.redAccent,
                        padding: const EdgeInsets.all(8),
                        child: const Text(
                          "You're offline. Changes will sync automatically when online.",
                          style: TextStyle(color: Colors.white, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text("Add New Entry", style: TextStyle(color: Colors.white),),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8657F3),
                          ),
                          onPressed: () async {
                            final added = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JournalAddPage(
                                  parentId: widget.parentId,
                                  childId: widget.childId,
                                ),
                              ),
                            );

                            if (added == true) {
                              await journalProvider.getMergedEntries(
                                parentId: widget.parentId,
                                childId: widget.childId,
                              );
                              if (mounted) setState(() {});
                            }
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? const Center(child: Text("No journal entries yet"))
                          : RefreshIndicator(
                              onRefresh: _syncWithCloud,
                              child: ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (_, index) {
                                  final entry = entries[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      leading: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _buildMoodIcon(entry.mood),
                                          const SizedBox(width: 8),
                                          Text(DateFormat('yMMMd').format(entry.entryDate)),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text("${entry.stars}"),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.star, color: Colors.amber),
                                        ],
                                      ),
                                      onTap: () => _showPreviewDialog(entry),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
