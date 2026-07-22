import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

/// Card representing one daily trip assignment in the supervisor's zones.
/// Ports OperatorTripSummaryCard's layout: a tinted status header bar, area
/// name + waste chip, and a compact staff/vehicle row.
class SupervisorAssignmentCard extends StatelessWidget {
  const SupervisorAssignmentCard({
    super.key,
    required this.assignment,
    this.onTap,
    this.onNavigate,
  });

  final SupervisorAssignment assignment;
  final VoidCallback? onTap;

  /// When provided, renders a "Navigate" button that opens the driver's live
  /// route map (remaining collection points + ORS routing).
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final s = _StatusPalette.of(assignment.status);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: SupervisorTheme.cardRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: SupervisorTheme.surface,
            borderRadius: SupervisorTheme.cardRadius,
            border: Border.all(color: SupervisorTheme.hairline),
            boxShadow: SupervisorTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status header bar
              Container(
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Icon(s.icon, size: 16, color: s.color),
                    const SizedBox(width: 6),
                    Text(
                      assignment.statusLabel.toUpperCase(),
                      style: TextStyle(
                        color: s.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            assignment.areaName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: SupervisorTheme.strongText,
                            ),
                          ),
                        ),
                        if (assignment.wasteTypeName.isNotEmpty)
                          _wasteChip(assignment.wasteTypeName),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      assignment.zoneName.isNotEmpty
                          ? '${assignment.zoneName} · ${assignment.tripCode}'
                          : assignment.tripCode,
                      style: const TextStyle(
                        color: SupervisorTheme.mutedText,
                        fontSize: 11.5,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _staffRow(),
                  ],
                ),
              ),
              if (onNavigate != null) _navigateButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigateButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onNavigate,
          icon: const Icon(Icons.navigation_rounded, size: 18),
          label: const Text('Navigate'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SupervisorTheme.accent,
            side: BorderSide(
                color: SupervisorTheme.accent.withValues(alpha: 0.4)),
            padding: const EdgeInsets.symmetric(vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _staffRow() {
    final crew = assignment.crew;
    final children = <Widget>[];
    if (crew != null &&
        (crew.driver != null ||
            crew.operator != null ||
            crew.extraOperators.isNotEmpty)) {
      children.addAll([
        CrewAvatarStack(
          crew: crew,
          size: 22,
          overlap: 12,
          borderColor: SupervisorTheme.surface,
        ),
        const SizedBox(width: 8),
      ]);
    }
    if (assignment.vehicleNo.isNotEmpty) {
      children.addAll([
        const Icon(Icons.local_shipping_outlined,
            size: 14, color: SupervisorTheme.mutedText),
        const SizedBox(width: 4),
        Text(
          assignment.vehicleNo,
          style: const TextStyle(
            fontSize: 12,
            color: SupervisorTheme.mutedText,
          ),
        ),
      ]);
    }
    final staffName = assignment.driverName.isNotEmpty
        ? assignment.driverName
        : assignment.operatorName;
    if (staffName.isNotEmpty) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 12));
      children.addAll([
        const Icon(Icons.person_outline,
            size: 14, color: SupervisorTheme.mutedText),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            staffName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: SupervisorTheme.mutedText,
            ),
          ),
        ),
      ]);
    }
    if (children.isEmpty) {
      children.add(const Text(
        'No staff assigned',
        style: TextStyle(fontSize: 12, color: SupervisorTheme.mutedText),
      ));
    }
    return Row(children: children);
  }

  Widget _wasteChip(String waste) {
    final isWet = waste.toLowerCase().contains('wet');
    final color = isWet ? const Color(0xFF0EA5E9) : SupervisorTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: SupervisorTheme.chipRadius,
      ),
      child: Text(
        waste,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StatusPalette {
  const _StatusPalette({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  static _StatusPalette of(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED':
        return const _StatusPalette(
          color: SupervisorTheme.success,
          icon: Icons.check_circle_rounded,
        );
      case 'IN_PROGRESS':
        return const _StatusPalette(
          color: Color(0xFF0EA5E9),
          icon: Icons.directions_run_rounded,
        );
      case 'CANCELLED':
        return const _StatusPalette(
          color: SupervisorTheme.danger,
          icon: Icons.cancel_rounded,
        );
      default:
        return const _StatusPalette(
          color: SupervisorTheme.warning,
          icon: Icons.schedule_rounded,
        );
    }
  }
}
