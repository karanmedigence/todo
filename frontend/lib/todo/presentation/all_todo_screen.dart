import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/bloc/todo_event.dart';
import 'package:frontend/todo/bloc/todo_states.dart';
import 'package:frontend/todo/data/todo_model.dart';
import 'package:frontend/todo/presentation/add_todo_screen.dart';
import 'package:frontend/core/theme/app_theme.dart';

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

  Future<void> _editTodo(TodoModel todo) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => AddTodoScreen(todo: todo)),
  );

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
        title: const Text('My workspace'),
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
      return RefreshIndicator(
        onRefresh: _loadTodos,
        color: AppTheme.gold,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 120),
          children: [
            Text('Today', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            Text(
              'One clear plan for everything ahead.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.add_task_rounded,
                        color: AppTheme.gold,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'No todos yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add your first todo and start with a clean slate.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final completed = todos.where((todo) => todo.isCompleted).length;
    final progress = todos.isEmpty ? 0.0 : completed / todos.length;

    return RefreshIndicator(
      onRefresh: _loadTodos,
      color: AppTheme.gold,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
        itemCount: todos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$completed of ${todos.length} complete',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 6,
                                    backgroundColor: AppTheme.elevated,
                                    color: AppTheme.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: AppTheme.gold,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                color: AppTheme.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final todo = todos[index - 1];
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _editTodo(todo),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit todo',
                  ),
                  IconButton(
                    onPressed: () => _deleteTodo(todo),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete todo',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
