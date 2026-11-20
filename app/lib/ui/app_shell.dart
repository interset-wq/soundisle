import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'widgets/mini_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<SearchPageState> _searchKey = GlobalKey<SearchPageState>();
  int _index = 0;

  void _select(int index) {
    setState(() => _index = index);
  }

  void _openSearch() {
    setState(() => _index = 1);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchKey.currentState?.focusSearch(),
    );
  }

  /// Android back returns to the home tab before leaving the app, matching the
  /// stock music app. On the home tab the system handles the exit normally.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    if (_index != 0) _select(0);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 920;

    final pages = <Widget>[
      HomePage(onOpenSearch: _openSearch, onOpenLibrary: () => _select(2)),
      SearchPage(key: _searchKey, showBack: false),
      LibraryPage(onOpenSearch: _openSearch),
      const SettingsPage(),
    ];

    final Widget shell;
    if (wide) {
      shell = Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                minWidth: 78,
                groupAlignment: -0.9,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7B6CFF), Color(0xFFFF6B9A)],
                      ),
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, size: 21),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_rounded),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('首页'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.search_rounded),
                    selectedIcon: Icon(Icons.search_rounded),
                    label: Text('搜索'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music_rounded),
                    selectedIcon: Icon(Icons.library_music_rounded),
                    label: Text('音乐库'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_rounded),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: Text('设置'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: IndexedStack(index: _index, children: pages),
                  ),
                  const AnimatedSize(
                    duration: Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: MiniPlayer(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      shell = Scaffold(
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(index: _index, children: pages),
            ),
            const AnimatedSize(
              duration: Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: MiniPlayer(),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, thickness: 1, color: context.subtleBorder),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: '搜索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: '音乐库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: '设置',
                ),
              ],
            ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: _handleBack,
      child: shell,
    );
  }
}
