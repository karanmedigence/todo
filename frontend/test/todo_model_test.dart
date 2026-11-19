import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/todo/data/todo_model.dart';

void main() {
  test('maps the backend todo response', () {
    final todo = TodoModel.fromJson({
      'id': 'todo-1',
      'title': 'Buy milk',
      'description': null,
      'is_completed': false,
    });

    expect(todo.id, 'todo-1');
    expect(todo.title, 'Buy milk');
    expect(todo.description, isNull);
    expect(todo.isCompleted, isFalse);
  });

  test('rejects an invalid backend todo response', () {
    expect(
      () => TodoModel.fromJson({
        'id': 'todo-1',
        'title': 'Buy milk',
        'description': null,
        'is_completed': 'false',
      }),
      throwsFormatException,
    );
  });
}
