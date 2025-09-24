import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text('Chats')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUserId)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Something went wrong'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return Center(child: Text('No chats yet'));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index].data() as Map<String, dynamic>;
              final otherUserId = (chat['participants'] as List).firstWhere(
                (id) => id != currentUserId,
              );

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUserId)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return ListTile(
                      leading: CircleAvatar(child: CircularProgressIndicator()),
                      title: Text('Loading...'),
                    );
                  }

                  final userData =
                      userSnapshot.data?.data() as Map<String, dynamic>?;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(
                        userData?['profilePicture'] ??
                            'https://via.placeholder.com/150',
                      ),
                    ),
                    title: Text(userData?['username'] ?? 'Unknown User'),
                    subtitle: Text(chat['lastMessage'] ?? 'No messages yet'),
                    trailing: chat['unreadCount'] > 0
                        ? CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.blue,
                            child: Text(
                              chat['unreadCount'].toString(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            chatId: chats[index].id,
                            otherUserId: otherUserId,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
