import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'task_model.g.dart';

@HiveType(typeId: 1)
class TaskModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final String assignedTo;

  @HiveField(4)
  final String createdBy;

  @HiveField(5)
  final bool isCompleted;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime? completedAt;

  TaskModel({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedTo,
    required this.createdBy,
    required this.isCompleted,
    required this.createdAt,
    this.completedAt,
  });

  // Firestore → Model
  factory TaskModel.fromFirestore(Map<String, dynamic> data, String id) {
    return TaskModel(
      id: id,
      title: data['title'],
      description: data['description'],
      assignedTo: data['assignedTo'],
      createdBy: data['createdBy'],
      isCompleted: data['isCompleted'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      completedAt: data['completedAt'] != null
          ? (data['completedAt'] as Timestamp).toDate()
          : null,
    );
  }

  // Model → Firestore
  Map<String, dynamic> toFirestore() {
    return {
      "title": title,
      "description": description,
      "assignedTo": assignedTo,
      "createdBy": createdBy,
      "isCompleted": isCompleted,
      "createdAt": createdAt,
      "completedAt": completedAt,
    };
  }

  void delete() {}
}
