import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ParentAccountPage extends StatefulWidget {
  final String parentId;
  const ParentAccountPage({super.key, required this.parentId});

  @override
  State<ParentAccountPage> createState() => _ParentAccountPageState();
}

class _ParentAccountPageState extends State<ParentAccountPage> {
  Map<String, dynamic>? parentData;
  List<Map<String, String>> childrenList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchParentData();
  }

  Future<void> fetchParentData() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Fetch parent document
      DocumentSnapshot parentSnapshot = await FirebaseFirestore.instance
          .collection('users/parent')
          .doc(widget.parentId)
          .get();

      if (!parentSnapshot.exists) {
        setState(() {
          parentData = null;
          childrenList = [];
          isLoading = false;
        });
        return;
      }

      Map<String, dynamic> data =
          (parentSnapshot.data() as Map<String, dynamic>?) ?? {};

      // Fetch children from map inside parent doc
      Map<String, dynamic> childrenMap = data['children'] ?? {};

      List<Map<String, String>> tempChildren = childrenMap.entries.map((entry) {
        // entry.key is childId, entry.value is accessCode
        return {
          "name": entry.key, // You can replace with actual child name if stored elsewhere
          "topMood": "N/A",  // You can fetch mood from another place if needed
        };
      }).toList();

      setState(() {
        parentData = data;
        childrenList = tempChildren;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching parent data: $e");
      setState(() {
        parentData = null;
        childrenList = [];
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (parentData == null) {
      return const Center(child: Text("Parent data not found."));
    }

    String parentName = parentData!['name']?.toString() ?? "Parent";
    int numberOfChildren = childrenList.length;

    return RefreshIndicator(
      onRefresh: fetchParentData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Section
            Row(
              children: [
                Stack(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundImage: AssetImage("assets/profile_placeholder.png"),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          // Add change profile picture functionality
                        },
                        child: const CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.blue,
                          child: Icon(
                            Icons.edit,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            parentName,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              // Navigate to edit profile page
                            },
                            icon: const Icon(Icons.edit, size: 20),
                          ),
                        ],
                      ),
                      Text(
                        "$numberOfChildren children",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Children Mood Cards
            Column(
              children: childrenList.map((child) {
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(child['name']![0]),
                    ),
                    title: Text(child['name']!),
                    subtitle: Text("Top Mood: ${child['topMood']}"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // Navigate to child's detailed view
                    },
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
