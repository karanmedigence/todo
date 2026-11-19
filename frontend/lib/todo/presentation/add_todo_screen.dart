import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/bloc/todo_event.dart';
import 'package:frontend/todo/bloc/todo_states.dart';
import 'package:frontend/todo/data/todo_model.dart';

class AddTodoScreen extends StatefulWidget {
  const AddTodoScreen({super.key, this.todo});

  final TodoModel? todo;

  @override
  State<AddTodoScreen> createState() => _AddTodoScreenState();
}

class _AddTodoScreenState extends State<AddTodoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.todo?.title ?? '';
    _descriptionController.text = widget.todo?.description ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveTodo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final description = _descriptionController.text.trim();
    if (widget.todo == null) {
      context.read<TodoBloc>().add(
        TodoCreateRequested(
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
        ),
      );
    } else {
      context.read<TodoBloc>().add(
        TodoUpdateRequested(
          id: widget.todo!.id,
          title: _titleController.text.trim(),
          description: description.isEmpty ? null : description,
          clearDescription: description.isEmpty,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TodoBloc, TodoState>(
      listener: (context, state) {
        if (!_isSubmitting) return;
        if (state is TodoError) {
          setState(() {
            _errorMessage = state.message;
            _isSubmitting = false;
          });
        } else if (state is TodoLoaded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.todo == null ? 'Todo created.' : 'Todo updated.',
              ),
            ),
          );
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.todo == null ? 'Add todo' : 'Edit todo'),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.todo == null
                            ? 'Create a todo'
                            : 'Edit your todo',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.todo == null
                            ? 'Turn an intention into a clear next step.'
                            : 'Refine the details and keep moving.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _titleController,
                                enabled: !_isSubmitting,
                                maxLength: 100,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Title',
                                  hintText: 'What needs to be done?',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Enter a todo title.';
                                  }
                                  if (value.trim().length > 100) {
                                    return 'Title must be 100 characters or fewer.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _descriptionController,
                                enabled: !_isSubmitting,
                                minLines: 4,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                  alignLabelWithHint: true,
                                  labelText: 'Description (optional)',
                                  hintText: 'Add context, notes, or a definition of done...',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _saveTodo,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                widget.todo == null
                                    ? 'Save todo'
                                    : 'Update todo',
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
