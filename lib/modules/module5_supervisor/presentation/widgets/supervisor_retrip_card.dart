import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// The pinned "needs your decision" block at the top of the Trips tab.
///
/// Deliberately loud: an amber rail, a count in the heading and a primary
/// "Review" affordance per request. A driver is parked waiting on this, so it
/// should not read like just another trip card.
class SupervisorRetripRequestsPanel extends StatelessWidget {
  const SupervisorRetripRequestsPanel({
    super.key,
    required this.requests,
    required this.onReview,
  });

  final List<SupervisorRetripRequest> requests;
  final ValueChanged<SupervisorRetripRequest> onReview;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border: Border.all(color: SupervisorTheme.warning.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: SupervisorTheme.warning.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: SupervisorTheme.hairline.withValues(alpha: 0.35),
              ),
            _RetripRow(
              request: requests[i],
              onReview: () => onReview(requests[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final count = requests.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: SupervisorTheme.warning.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              size: 18, color: SupervisorTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? 'Re-Trip request needs your approval'
                  : '$count Re-Trip requests need your approval',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetripRow extends StatelessWidget {
  const _RetripRow({required this.request, required this.onReview});

  final SupervisorRetripRequest request;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    // Prefer the live count — a colleague may have collected a stop since the
    // driver raised the request.
    final pending = request.livePendingTotal > 0
        ? request.livePendingTotal
        : request.snapshotPendingTotal;
    final typeLabel = request.isHousehold ? 'Households' : 'Collection points';

    return InkWell(
      onTap: onReview,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.areaName.isNotEmpty
                        ? request.areaName
                        : request.assignmentUniqueId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SupervisorTheme.warning.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$pending left',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${request.assignmentUniqueId} · $typeLabel'
              '${request.vehicleNo.isNotEmpty ? ' · ${request.vehicleNo}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: SupervisorTheme.mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: SupervisorTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.format_quote_rounded,
                        size: 14, color: SupervisorTheme.mutedText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        request.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: SupervisorTheme.strongText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (request.requestedByName.isNotEmpty)
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            size: 14, color: SupervisorTheme.mutedText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            request.requestedByName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: SupervisorTheme.mutedText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 8),
                _ReviewButton(onTap: onReview),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewButton extends StatelessWidget {
  const _ReviewButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SupervisorTheme.accent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Review',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 15, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
