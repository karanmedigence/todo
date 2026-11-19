import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/bloc/todo_event.dart';
import 'package:frontend/todo/bloc/todo_states.dart';
import 'package:frontend/todo/data/todo_model.dart';
import 'package:frontend/todo/presentation/add_todo_screen.dart';

class AllTodoScreen extends StatefulWidget {
  const AllTodoScreen({super.key});

  @override
  State<AllTodoScreen> createState() => _AllTodoScreenState();
}

class _AllTodoScreenState extends State<AllTodoScreen> {
  @override
  void initState() {
    super.initState();
    context.read<TodoBloc>().add(const TodoLoadRequested());
  }

  Future<void> _loadTodos() async {
    final bloc = context.read<TodoBloc>();
    final loaded = bloc.stream.firstWhere(
      (state) => state is TodoLoaded || state is TodoError,
    );
    bloc.add(const TodoLoadRequested());
    await loaded;
  }

  Future<void> _addTodo() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const AddTodoScreen()));

  Future<void> _setCompletion(TodoModel todo, bool isCompleted) async {
    context.read<TodoBloc>().add(
      TodoUpdateRequested(id: todo.id, isCompleted: isCompleted),
    );
  }

  Future<void> _deleteTodo(TodoModel todo) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete todo?'),
        content: Text('Delete "${todo.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true || !mounted) return;

    context.read<TodoBloc>().add(TodoDeleteRequested(todo.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My todos'),
        actions: [
          IconButton(
            onPressed: () =>
                context.read<TodoBloc>().add(const TodoLoadRequested()),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh todos',
          ),
        ],
      ),
      body: BlocBuilder<TodoBloc, TodoState>(
        builder: (context, state) => _buildBody(context, state),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTodo,
        icon: const Icon(Icons.add),
        label: const Text('Add todo'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TodoState state) {
    if (state is TodoInitial || state is TodoLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is TodoError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    context.read<TodoBloc>().add(const TodoLoadRequested()),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final todos = (state as TodoLoaded).todos;
    if (todos.isEmpty) {
      return const Center(child: Text('No todos yet. Add one to get started.'));
    }

    return RefreshIndicator(
      onRefresh: _loadTodos,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
        itemCount: todos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final todo = todos[index];
          return Card(
            child: ListTile(
              leading: Checkbox(
                value: todo.isCompleted,
                onChanged: (value) {
                  if (value != null) _setCompletion(todo, value);
                },
              ),
              title: Text(
                todo.title,
                style: TextStyle(
                  decoration: todo.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              subtitle: todo.description == null || todo.description!.isEmpty
                  ? null
                  : Text(todo.description!),
              trailing: IconButton(
                onPressed: () => _deleteTodo(todo),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete todo',
              ),
            ),
          );
        },
      ),
    );
  }
}
