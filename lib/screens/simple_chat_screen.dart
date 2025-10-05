import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/socket_service.dart';

class SimpleChatScreen extends StatefulWidget {
  const SimpleChatScreen({super.key});

  @override
  State<SimpleChatScreen> createState() => _SimpleChatScreenState();
}

class _SimpleChatScreenState extends State<SimpleChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    // Escuchar nuevos mensajes
    SocketService.instance.on('new_message', (data) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage.fromSocket(data));
        });
        _scrollToBottom();
      }
    });

    // Escuchar eventos de conexión
    SocketService.instance.on('connected', (_) {
      if (mounted) {
        _addSystemMessage('✅ Conectado al servidor');
        // Unirse a la sala general automáticamente
        SocketService.instance.joinRoom('room_1');
      }
    });

    SocketService.instance.on('disconnected', (_) {
      if (mounted) {
        _addSystemMessage('❌ Desconectado del servidor');
      }
    });

    SocketService.instance.on('joined_room', (data) {
      if (mounted) {
        _addSystemMessage('🏠 Te uniste a: ${data['roomName']}');
      }
    });
  }

  void _addSystemMessage(String message) {
    setState(() {
      _messages.add(ChatMessage.system(message));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    // Enviar mensaje por socket
    SocketService.instance.sendMessage(
      roomId: 'room_1', // Sala general
      content: message,
      type: 'text',
    );

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            return Row(
              children: [
                // Avatar del usuario
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: auth.currentUser?.avatarColor != null 
                        ? _parseColor(auth.currentUser!.avatarColor)
                        : Colors.blue,
                  ),
                  child: Center(
                    child: Text(
                      auth.currentUser?.initials ?? '??',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.currentUser?.username ?? 'Usuario',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Consumer<ChatProvider>(
                      builder: (context, chat, child) {
                        return Text(
                          chat.isConnected ? '🟢 Conectado' : '🔴 Desconectado',
                          style: TextStyle(
                            fontSize: 12,
                            color: chat.isConnected ? Colors.green : Colors.red,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        backgroundColor: Colors.blue.shade400,
        foregroundColor: Colors.white,
        actions: [
          // Botón de estadísticas
          IconButton(
            onPressed: _showStats,
            icon: const Icon(Icons.info_outline),
          ),
          // Botón de logout
          IconButton(
            onPressed: () => _logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          // Lista de mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageWidget(message);
              },
            ),
          ),
          
          // Input de mensaje
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                    maxLines: null,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue.shade400,
                  child: IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageWidget(ChatMessage message) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    final isMe = message.senderId == 
        Provider.of<AuthProvider>(context, listen: false).currentUser?.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar del remitente
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _parseColor(message.senderAvatarColor),
              ),
              child: Center(
                child: Text(
                  message.senderInitials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          // Burbuja del mensaje
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade400 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.senderName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          if (isMe) const SizedBox(width: 40),
        ],
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      return Color(int.parse(colorString.substring(1, 7), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue.shade400;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void _showStats() {
    // Mostrar estadísticas simples
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 Estadísticas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💬 Mensajes enviados: ${_messages.where((m) => !m.isSystem).length}'),
            Text('🔄 Estado: ${Provider.of<ChatProvider>(context).isConnected ? "Conectado" : "Desconectado"}'),
            Text('🏠 Sala: Sala General'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    Provider.of<AuthProvider>(context, listen: false).logout();
    Navigator.of(context).pushReplacementNamed('/welcome');
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// Modelo simple de mensaje para la UI
class ChatMessage {
  final String id;
  final String content;
  final String senderId;
  final String senderName;
  final String senderInitials;
  final String senderAvatarColor;
  final DateTime timestamp;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.content,
    required this.senderId,
    required this.senderName,
    required this.senderInitials,
    required this.senderAvatarColor,
    required this.timestamp,
    this.isSystem = false,
  });

  factory ChatMessage.fromSocket(Map<String, dynamic> data) {
    final sender = data['sender'];
    final avatar = sender['avatar'] ?? 'UN:#4ECDC4';
    final avatarParts = avatar.split(':');
    
    return ChatMessage(
      id: data['id'],
      content: data['content'],
      senderId: sender['id'],
      senderName: sender['username'],
      senderInitials: avatarParts.isNotEmpty ? avatarParts[0] : 'UN',
      senderAvatarColor: avatarParts.length > 1 ? avatarParts[1] : '#4ECDC4',
      timestamp: DateTime.parse(data['createdAt']),
    );
  }

  factory ChatMessage.system(String message) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: message,
      senderId: 'system',
      senderName: 'Sistema',
      senderInitials: 'SY',
      senderAvatarColor: '#666666',
      timestamp: DateTime.now(),
      isSystem: true,
    );
  }
}