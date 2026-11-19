import 'package:equatable/equatable.dart';

sealed class TodoEvent extends Equatable {
  const TodoEvent();

  @override
  List<Object?> get props => [];
}

final class TodoLoadRequested extends TodoEvent {
  const TodoLoadRequested();
}

final class TodoCreateRequested extends TodoEvent {
  const TodoCreateRequested({required this.title, this.description});

  final String title;
  final String? description;

  @override
  List<Object?> get props => [title, description];
}

final class TodoUpdateRequested extends TodoEvent {
  const TodoUpdateRequested({required this.id, required this.isCompleted});

  final String id;
  final bool isCompleted;

  @override
  List<Object?> get props => [id, isCompleted];
}

final class TodoDeleteRequested extends TodoEvent {
  const TodoDeleteRequested(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}
