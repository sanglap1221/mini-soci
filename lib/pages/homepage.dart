import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'feed_page.dart';
import 'profile_page.dart';
import 'chat_list_page.dart';
import 'addpostpage.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 0;
  Object? _feedRefreshToken;

  void signOut() {
    FirebaseAuth.instance.signOut();
  }

  Future<void> _navigateToAddPost() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const Addpostpage()),
    );

    if (created == true) {
      setState(() {
        _feedRefreshToken = Object();
      });
    }
  }

  Widget _getPage(int index) {
    switch (index) {
      case 0:
        return FeedPage(refreshTrigger: _feedRefreshToken);
      case 1:
        return const ChatListPage();
      case 2:
        return ProfilePage();
      default:
        return const FeedPage();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _getPage(_selectedIndex),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _navigateToAddPost,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
