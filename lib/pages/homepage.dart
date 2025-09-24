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

  void signOut() {
    FirebaseAuth.instance.signOut();
  }

  void _navigateToAddPost() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const Addpostpage()),
    );
  }

  final List<Widget> _pages = [
    const FeedPage(),
    const ChatListPage(),
    ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
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
