import 'package:flutter/material.dart';

import '../theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.action, this.onAction});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: context.neutral(0.45))),
                ],
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.name, this.dense = false});

  final String name;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(name);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 5 : 7, vertical: dense ? 1 : 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.7),
      ),
      child: Text(
        name,
        style: TextStyle(fontSize: dense ? 9 : 10, fontWeight: FontWeight.w700, color: color, height: 1.2),
      ),
    );
  }

  Color _colorFor(String source) {
    switch (source) {
      case 'netease':
        return const Color(0xFFFF5A6E);
      case 'qq':
        return const Color(0xFF31C27C);
      case 'kugou':
        return const Color(0xFF2E8BFF);
      case 'kuwo':
        return const Color(0xFFFFB02E);
      case 'migu':
        return const Color(0xFFFF4D8D);
      case 'soda':
        return const Color(0xFF25D0C0);
      case 'bilibili':
        return const Color(0xFFFF7AAE);
      case 'apple':
        return const Color(0xFFFA5C7A);
      case 'spotify':
        return const Color(0xFF1ED760);
      default:
        return AppColors.accent;
    }
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.subtleFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.subtleBorder),
      ),
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.neutral(0.05),
              ),
              child: Icon(icon, size: 34, color: context.neutral(0.35)),
            ),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.neutral(0.42), height: 1.5),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.count = 8});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: context.neutral(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 150 + (index % 3) * 30,
                  height: 12,
                  decoration: BoxDecoration(
                    color: context.neutral(0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: 90,
                  height: 10,
                  decoration: BoxDecoration(
                    color: context.neutral(0.035),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void showAppSnack(BuildContext context, String message) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
}
