import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/widgets/captain_glass.dart';

/// A card showing one collection point in the operator's daily trip.
///
/// Displays sequence, CP name, bin name, status (Pending/Collected), and weight
/// once collected. Rendered as a Captain liquid-glass panel with a success
/// treatment when collected.
class OperatorCpCard extends StatelessWidget {
  final OperatorTripCollectionPoint cp;
  final VoidCallback? onTap;

  const OperatorCpCard({super.key, required this.cp, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCollected = cp.isCollected;
    final statusColor = isCollected ? CaptainTheme.success : CaptainTheme.gold;
    final statusLabel = isCollected ? 'Collected' : 'Pending';

    return CaptainGlassCard(
      onTap: onTap,
      tint: isCollected ? CaptainTheme.success : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sequenceBadge(isCollected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cp.collectionPoint.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: CaptainTheme.strongText,
                        ),
                      ),
                    ),
                    _statusChip(statusLabel, statusColor),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded,
                        size: 16, color: CaptainTheme.mutedText),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        cp.bin.binQr,
                        style: TextStyle(
                          color: CaptainTheme.mutedText,
                          fontSize: 12.5,
                          letterSpacing: 0.4,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${cp.bin.binName} · ${cp.bin.binCapacity} L',
                  style: TextStyle(
                    color: CaptainTheme.mutedText,
                    fontSize: 12,
                  ),
                ),
                if (isCollected) ...[
                  const SizedBox(height: 10),
                  _collectedFooter(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sequenceBadge(bool isCollected) {
    final gradient = isCollected
        ? LinearGradient(
            colors: [CaptainTheme.success, CaptainTheme.accentDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : CaptainTheme.accentGradient;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: isCollected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 24)
          : Text(
              '${cp.sequence}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: CaptainTheme.chipRadius,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _collectedFooter() {
    final weight = cp.collectedWeightKg ?? 0;
    final at = cp.collectedAt;
    final time = at != null
        ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
        : '--:--';
    return Row(
      children: [
        Icon(Icons.scale_rounded, size: 14, color: CaptainTheme.success),
        const SizedBox(width: 4),
        Text('${weight.toStringAsFixed(2)} kg',
            style: TextStyle(
              fontSize: 12.5,
              color: CaptainTheme.success,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(width: 10),
        Icon(Icons.schedule_rounded, size: 14, color: CaptainTheme.mutedText),
        const SizedBox(width: 4),
        Text(time,
            style: TextStyle(
              fontSize: 12,
              color: CaptainTheme.mutedText,
            )),
      ],
    );
  }
}
