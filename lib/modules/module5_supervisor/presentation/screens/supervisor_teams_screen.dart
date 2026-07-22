import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:iwms_citizen_app/core/di.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/logic/supervisor_bloc.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_assignment_picker_dialog.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_state_views.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_visuals.dart';
import 'package:iwms_citizen_app/shared/widgets/crew_avatar_stack.dart';

/// Teams — the staff template list (driver + operator + extra operators).
class SupervisorTeamsScreen extends StatefulWidget {
  const SupervisorTeamsScreen({super.key});

  @override
  State<SupervisorTeamsScreen> createState() => _SupervisorTeamsScreenState();
}

class _SupervisorTeamsScreenState extends State<SupervisorTeamsScreen> {
  final SupervisorRepository _repo = getIt<SupervisorRepository>();

  bool _loading = true;
  String? _error;
  List<SupervisorTeam> _teams = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await _repo.fetchTeams();
      if (!mounted) return;
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load teams';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Teams'),
      ),
      body: SupervisorPatternBackground(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const SupervisorLoadingView();
    if (_error != null) {
      return SupervisorErrorView(message: _error!, onRetry: _load);
    }
    if (_teams.isEmpty) {
      return SupervisorEmptyView(
        message: 'No staff templates found.',
        icon: Icons.groups_2_rounded,
        onRefresh: _load,
      );
    }

    // Today's assignments (shared SupervisorBloc), so each team card can show
    // whether it's on a trip right now, its attendance, and a "View trip"
    // action — without a second network round trip.
    return BlocBuilder<SupervisorBloc, SupervisorState>(
      builder: (context, state) {
        return RefreshIndicator(
          color: SupervisorTheme.accent,
          onRefresh: () async {
            await Future.wait([
              _load(),
              () async {
                context.read<SupervisorBloc>().add(
                      const SupervisorRefreshRequested(),
                    );
              }(),
            ]);
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            itemCount: _teams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final team = _teams[i];
              final teamAssignments = _assignmentsFor(team, state.assignments);
              final assignment = _primaryAssignment(teamAssignments);
              return _TeamCard(
                team: team,
                index: i,
                assignment: assignment,
                assignments: teamAssignments,
              );
            },
          ),
        );
      },
    );
  }

  List<SupervisorAssignment> _assignmentsFor(
    SupervisorTeam team,
    List<SupervisorAssignment> assignments,
  ) {
    final matches = assignments
        .where((a) => a.staffTemplateId == team.uniqueId)
        .toList()
      ..sort((a, b) {
        final rankA = _assignmentSortRank(a);
        final rankB = _assignmentSortRank(b);
        if (rankA != rankB) return rankA.compareTo(rankB);
        final dateA = a.tripDate;
        final dateB = b.tripDate;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });
    return matches;
  }

  SupervisorAssignment? _primaryAssignment(List<SupervisorAssignment> matches) {
    if (matches.isEmpty) return null;
    for (final a in matches) {
      if (a.isInProgress) return a;
    }
    return matches.first;
  }

  int _assignmentSortRank(SupervisorAssignment assignment) {
    if (assignment.isInProgress) return 0;
    if (assignment.isScheduled) return 1;
    if (assignment.isCompleted) return 2;
    if (assignment.isCancelled) return 3;
    return 4;
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.index,
    required this.assignment,
    required this.assignments,
  });

  final SupervisorTeam team;
  final int index;
  final SupervisorAssignment? assignment;
  final List<SupervisorAssignment> assignments;

  bool get _onTrip => assignment?.isInProgress ?? false;

  Color get _statusColor {
    if (_onTrip) return SupervisorTheme.success;
    switch (team.status.toUpperCase()) {
      case 'ACTIVE':
        return SupervisorTheme.success;
      case 'INACTIVE':
        return SupervisorTheme.mutedText;
      default:
        return SupervisorTheme.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final crew = assignment?.crew;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _onTrip
            ? SupervisorTheme.success.withValues(alpha: 0.10)
            : SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border: Border.all(
          color: _onTrip
              ? SupervisorTheme.success.withValues(alpha: 0.45)
              : SupervisorTheme.hairline.withValues(alpha: 0.6),
        ),
        boxShadow: SupervisorTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (crew != null &&
                  (crew.driver != null ||
                      crew.operator != null ||
                      crew.extraOperators.isNotEmpty)) ...[
                CrewAvatarStack(
                  crew: crew,
                  size: 24,
                  overlap: 13,
                  borderColor: SupervisorTheme.surface,
                ),
                const SizedBox(width: 10),
              ] else ...[
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: SupervisorTheme.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: SupervisorTheme.accent,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  'Team ${index + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SupervisorTheme.strongText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _onTrip ? 'ON TRIP' : team.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: _statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _memberRow(
            icon: Icons.local_shipping_rounded,
            label: 'Driver',
            value: team.driverName.isNotEmpty ? team.driverName : 'Unassigned',
            attendanceStatus: crew?.driver?.attendanceStatus,
          ),
          const SizedBox(height: 8),
          _memberRow(
            icon: Icons.engineering_rounded,
            label: 'Operator',
            value:
                team.operatorName.isNotEmpty ? team.operatorName : 'Unassigned',
            attendanceStatus: crew?.operator?.attendanceStatus,
          ),
          if (team.extraCount > 0) ...[
            const SizedBox(height: 8),
            _memberRow(
              icon: Icons.group_add_rounded,
              label: 'Extra operators',
              value: '${team.extraCount}',
            ),
          ],
          if (assignment != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAssignmentsDialog(context),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('View trips'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SupervisorTheme.accent,
                  side: BorderSide(
                    color: SupervisorTheme.accent.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: SupervisorTheme.chipRadius,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberRow({
    required IconData icon,
    required String label,
    required String value,
    String? attendanceStatus,
  }) {
    final isPresent = attendanceStatus == 'Present';
    return Row(
      children: [
        Icon(icon, size: 15, color: SupervisorTheme.mutedText),
        const SizedBox(width: 8),
        Text(
          '$label:  ',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: SupervisorTheme.mutedText,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
        if (attendanceStatus != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (isPresent ? SupervisorTheme.success : SupervisorTheme.danger)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              attendanceStatus,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color:
                    isPresent ? SupervisorTheme.success : SupervisorTheme.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showAssignmentsDialog(BuildContext context) {
    SupervisorAssignmentPickerDialog.show(
      context,
      title: 'Team ${index + 1}',
      assignments: assignments,
    );
  }
}
