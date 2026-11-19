class ChatContact {
  const ChatContact({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final email = json['email'];
    if (id is! String || name is! String || email is! String) {
      throw const FormatException('Invalid chat user response from server.');
    }
    return ChatContact(id: id, name: name, email: email);
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String content;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final senderId = json['sender_id'];
    final recipientId = json['recipient_id'];
    final content = json['content'];
    final createdAt = json['created_at'];
    if (id is! String ||
        senderId is! String ||
        recipientId is! String ||
        content is! String ||
        createdAt is! String) {
      throw const FormatException('Invalid chat message from server.');
    }
    final timestamp = DateTime.tryParse(createdAt);
    if (timestamp == null) {
      throw const FormatException('Invalid chat message timestamp.');
    }
    return ChatMessage(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      content: content,
      createdAt: timestamp,
    );
  }
}
