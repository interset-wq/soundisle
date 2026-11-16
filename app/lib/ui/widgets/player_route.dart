import 'package:flutter/material.dart';

import '../pages/player_page.dart';

/// Slides the now-playing page in from the bottom.
///
/// Shared by the mini player and by "tap a song" so both open the player in
/// exactly the same way.
Future<void> openPlayerPage(BuildContext context) {
  if (!context.mounted) return Future.value();
  return Navigator.of(context).push<void>(PageRouteBuilder(
    opaque: false,
    pageBuilder: (_, _, _) => const PlayerPage(),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
  ));
}
