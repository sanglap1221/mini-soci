import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfilePage extends StatelessWidget {
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  Future<void> _editUsername(
    BuildContext context,
    String currentUsername,
  ) async {
    final TextEditingController _controller = TextEditingController(
      text: currentUsername,
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Username'),
        content: TextField(
          controller: _controller,
          decoration: InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => {Navigator.pop(context)},
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              //let me
              if (_controller.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({'username': _controller.text.trim()});
                Navigator.pop(context);
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return Center(child: Text('Please login to view profile'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // TODO: Navigate to settings page
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(child: Text('Something went wrong'));
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;

          return Column(
            children: [
              // Profile Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(
                        userData?['profilePicture'] ??
                            'https://via.placeholder.com/150',
                      ),
                    ),
                    SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => _editUsername(
                        context,
                        userData?['username'] ?? 'Username',
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            userData?['username'] ?? 'Username',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.edit, size: 20),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      userData?['bio'] ?? 'No bio available',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // User's Posts Grid
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('posts')
                      .where('userId', isEqualTo: userId)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, postsSnapshot) {
                    if (postsSnapshot.hasError) {
                      return Center(child: Text('Error loading posts'));
                    }

                    if (postsSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final posts = postsSnapshot.data?.docs ?? [];

                    if (posts.isEmpty) {
                      return Center(child: Text('No posts yet'));
                    }

                    return GridView.builder(
                      padding: EdgeInsets.all(4),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final post =
                            posts[index].data() as Map<String, dynamic>;
                        return GestureDetector(
                          onTap: () {
                            // TODO: Navigate to post detail page
                          },
                          child: Image.network(
                            post['imageUrl'],
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
