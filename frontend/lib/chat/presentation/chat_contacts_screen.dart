import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:frontend/chat/data/chat_models.dart';
import 'package:frontend/chat/data/chat_repository.dart';
import 'package:frontend/chat/presentation/chat_conversation_screen.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/di/injection.dart';

class ChatContactsScreen extends StatefulWidget {
  const ChatContactsScreen({super.key, required this.currentUserId});

  final String currentUserId;

  @override
  State<ChatContactsScreen> createState() => _ChatContactsScreenState();
}

class _ChatContactsScreenState extends State<ChatContactsScreen> {
  final _repository = getIt<ChatRepository>();
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ChatContact> _contacts = [];
  String? _error;
  bool _isLoading = false;
  int _searchVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final search = value.trim();
    final searchVersion = ++_searchVersion;
    setState(() {
      _contacts = [];
      _error = null;
      _isLoading = search.length >= 3;
    });
    if (search.length < 3) return;

    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchUsers(search, searchVersion),
    );
  }

  Future<void> _searchUsers(String search, int searchVersion) async {
    try {
      final contacts = await _repository.findUsers(search);
      if (!mounted || searchVersion != _searchVersion) return;
      setState(() {
        _contacts = contacts;
        _error = null;
      });
    } on ChatException catch (error) {
      if (!mounted || searchVersion != _searchVersion) return;
      setState(() {
        _error = error.message;
      });
    } on FormatException catch (error) {
      if (!mounted || searchVersion != _searchVersion) return;
      setState(() {
        _error = error.message;
      });
    } finally {
      if (mounted && searchVersion == _searchVersion) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openChat(ChatContact contact) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatConversationScreen(
          contact: contact,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Find a user by email',
                hintText: 'name@example.com',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_searchController.text.trim().length < 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Enter at least 3 characters of an email to find a chat partner.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_contacts.isEmpty) {
      return const Center(child: Text('No users found for that email.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: _contacts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final contact = _contacts[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.elevated,
              child: Text(
                contact.name.isEmpty
                    ? '?'
                    : contact.name.trim()[0].toUpperCase(),
              ),
            ),
            title: Text(contact.name),
            subtitle: Text(contact.email),
            trailing: const Icon(Icons.chat_bubble_outline_rounded),
            onTap: () => _openChat(contact),
          ),
        );
      },
    );
  }
}
