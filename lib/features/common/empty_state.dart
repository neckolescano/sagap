import 'package:flutter/material.dart';

/// Icon in a soft radar badge + title + message, with an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.22),
                  scheme.primary.withValues(alpha: 0.0),
                ],
              ),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, size: 52, color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action case final action?) ...[
            const SizedBox(height: 24),
            action,
          ],
        ],
      ),
    );
  }
}
