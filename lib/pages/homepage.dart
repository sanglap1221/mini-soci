import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_list_page.dart';
import 'addpostpage.dart';
import 'feed_page.dart';
import 'profile_page.dart';
import 'reels_page.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  int _selectedIndex = 0;
  Object? _feedRefreshToken;
  bool _isNavVisible = true;

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
        return ReelsPage(refreshTrigger: _feedRefreshToken);
      case 2:
        return const ChatListPage();
      case 3:
        return ProfilePage();
      default:
        return FeedPage(refreshTrigger: _feedRefreshToken);
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is UserScrollNotification) {
      switch (notification.direction) {
        case ScrollDirection.forward:
          _setNavVisible(true);
          break;
        case ScrollDirection.reverse:
          _setNavVisible(false);
          break;
        case ScrollDirection.idle:
          break;
      }
    }
    return false;
  }

  void _setNavVisible(bool visible) {
    if (_isNavVisible == visible) return;
    setState(() {
      _isNavVisible = visible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final navBar = SafeArea(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        offset: _isNavVisible ? Offset.zero : const Offset(0, 1.2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          opacity: _isNavVisible ? 1 : 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: IgnorePointer(
                  ignoring: !_isNavVisible,
                  child: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    selectedItemColor: Colors.white,
                    unselectedItemColor: Colors.white70,
                    type: BottomNavigationBarType.fixed,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.home),
                        label: 'Feed',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.smart_display),
                        label: 'Reels',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.chat),
                        label: 'Chats',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person),
                        label: 'Profile',
                      ),
                    ],
                    currentIndex: _selectedIndex,
                    onTap: _onItemTapped,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: _getPage(_selectedIndex),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: navBar),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _selectedIndex == 0
          ? AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom:
                    (_isNavVisible ? 96.0 : 24.0) +
                    MediaQuery.of(context).padding.bottom,
                right: 8,
              ),
              child: FloatingActionButton(
                onPressed: _navigateToAddPost,
                child: const Icon(Icons.add),
              ),
            )
          : null,
    );
  }
}
