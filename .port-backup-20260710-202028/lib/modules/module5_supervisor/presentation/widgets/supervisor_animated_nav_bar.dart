import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Supervisor bottom navigation — a FLOATING rounded-rectangle bar (App Store
/// style: detached from the screen edges, big corner radius, soft shadow, and
/// a frosted-glass fill) with 4 evenly-spaced tabs. Mirrors the driver's
/// [CaptainNavBar] visual treatment exactly — the glass card, 28px radius,
/// backdrop blur, animated indicator pill, scaled icon and always-visible
/// label — adapted to the supervisor's light theme tokens.
///
/// There is no centered FAB (the supervisor has no scan/today action), so the
/// four slots are simply distributed evenly across the width.
/// Layout: [tab0][tab1][tab2][tab3].
class SupervisorAnimatedNavBar extends StatelessWidget {
  const SupervisorAnimatedNavBar({
    super.key,
    required this.activeIndex,
    required this.onTabSelected,
    required this.items,
    this.height = 68,
  });

  final int activeIndex;
  final ValueChanged<int> onTabSelected;
  final List<SupervisorNavItem> items;
  final double height;

  @override
  Widget build(BuildContext context) {
    assert(items.length == 4, 'SupervisorAnimatedNavBar expects exactly 4 tabs');

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            // Frosted floating bar — content scrolling beneath blurs through.
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: SupervisorTheme.surface.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: const Color(0xFF0B1220).withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: SupervisorTheme.elevatedShadow,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(child: _slot(i)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(int index) => _AnimatedNavTab(
        item: items[index],
        selected: index == activeIndex,
        onTap: () => onTabSelected(index),
      );
}

class SupervisorNavItem {
  const SupervisorNavItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class _AnimatedNavTab extends StatelessWidget {
  const _AnimatedNavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SupervisorNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SupervisorTheme.accent : SupervisorTheme.mutedText;

    return InkResponse(
      onTap: onTap,
      radius: 38,
      highlightColor: SupervisorTheme.accent.withValues(alpha: 0.06),
      splashColor: SupervisorTheme.accent.withValues(alpha: 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active indicator pill above the icon (slides in on select)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: selected ? 22 : 0,
            height: 3,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: SupervisorTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: Icon(item.icon, color: color, size: 22),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}
