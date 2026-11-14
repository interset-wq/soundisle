import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 12,
    this.heroTag,
    this.seed = '',
    this.icon = Icons.music_note_rounded,
  });

  final String url;
  final double size;
  final double radius;
  final String? heroTag;
  final String seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? _fallback(context)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 220),
                placeholder: (_, _) => _fallback(context, loading: true),
                errorWidget: (_, _, _) => _fallback(context),
              ),
      ),
    );
    if (heroTag == null) return child;
    return Hero(tag: heroTag!, child: child);
  }

  Widget _fallback(BuildContext context, {bool loading = false}) {
    final colors = _palette(seed);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: loading
            ? SizedBox(
                width: size * 0.24,
                height: size * 0.24,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.white.withValues(alpha: 0.7)),
              )
            : Icon(icon, size: size * 0.36, color: Colors.white.withValues(alpha: 0.82)),
      ),
    );
  }

  List<Color> _palette(String value) {
    const palettes = [
      [Color(0xFF6A5AE0), Color(0xFFB06AB3)],
      [Color(0xFF1F6FEB), Color(0xFF20C4C9)],
      [Color(0xFFE85D75), Color(0xFFFFA26B)],
      [Color(0xFF00B09B), Color(0xFF96C93D)],
      [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
      [Color(0xFFF857A6), Color(0xFFFF5858)],
    ];
    final hash = value.isEmpty ? 0 : value.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return palettes[hash % palettes.length];
  }
}
