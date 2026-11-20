import 'package:flutter/material.dart';

import '../../core/signal/signal_format.dart';
import '../../core/signal/signal_quality.dart';
import '../../core/theme/signal_pattern.dart';

/// Legend: swatch (colour + pattern) + word + dBm range.
class SignalLegend extends StatelessWidget {
  const SignalLegend({super.key});

  static String rangeFor(SignalQuality quality) => switch (quality) {
        SignalQuality.excellent => '${formatDbm(excellentMinDbm)} or stronger',
        SignalQuality.good =>
          '${formatDbm(goodMinDbm)} to ${formatDbm(excellentMinDbm - 1)}',
        SignalQuality.weak =>
          '${formatDbm(weakMinDbm)} to ${formatDbm(goodMinDbm - 1)}',
        SignalQuality.deadZone => '${formatDbm(weakMinDbm - 1)} or weaker',
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final quality in SignalQuality.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SignalSwatch(quality, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(quality.label, style: textTheme.titleMedium),
                      Text(
                        rangeFor(quality),
                        style: textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
