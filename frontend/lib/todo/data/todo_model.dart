class TodoModel {
  const TodoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.isCompleted,
  });

  final String id;
  final String title;
  final String? description;
  final bool isCompleted;

  factory TodoModel.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final description = json['description'];
    final isCompleted = json['is_completed'];

    if (id is! String ||
        title is! String ||
        (description != null && description is! String) ||
        isCompleted is! bool) {
      throw const FormatException('Invalid todo response from server.');
    }

    return TodoModel(
      id: id,
      title: title,
      description: description as String?,
      isCompleted: isCompleted,
    );
  }
}
