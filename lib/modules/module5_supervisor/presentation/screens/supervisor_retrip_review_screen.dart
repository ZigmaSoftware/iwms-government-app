import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/core/di.dart';
import 'package:iwms_citizen_app/core/ui/app_flash.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';

/// Open the review screen for the Re-Trip request named in a notification.
///
/// The push/in-app payload only carries `retrip_request_id`, so the full
/// request has to be fetched before the screen can render. Returns true when a
/// decision was recorded, so the caller can refresh.
///
/// Handles the two "nothing to review" cases explicitly instead of silently
/// doing nothing, which is what makes a tapped notification feel broken:
///   * the id is missing from the payload;
///   * the request was already decided (often by another supervisor).
Future<bool> openSupervisorRetripFromNotification(
  BuildContext context, {
  required String? retripRequestId,
}) async {
  if (retripRequestId == null || retripRequestId.isEmpty) {
    AppFlash.error(context, 'This request is no longer available.');
    return false;
  }

  // Fetch every status, not just Pending — an already-decided request must
  // still resolve so we can explain that rather than showing nothing.
  List<SupervisorRetripRequest> all;
  try {
    all = await getIt<SupervisorRepository>().fetchRetripRequests(status: '');
  } on SupervisorException catch (e) {
    if (context.mounted) AppFlash.error(context, e.message);
    return false;
  }
  if (!context.mounted) return false;

  SupervisorRetripRequest? match;
  for (final r in all) {
    if (r.uniqueId == retripRequestId) {
      match = r;
      break;
    }
  }
  if (match == null) {
    AppFlash.error(context, 'This request is no longer available.');
    return false;
  }
  if (!match.isPending) {
    AppFlash.info(
      context,
      'This request was already ${match.status.toLowerCase()}.',
    );
    return false;
  }

  final decided = await SupervisorRetripReviewScreen.push(context, match);
  return decided == true;
}

/// Supervisor's decision screen for one Re-Trip request.
///
/// The whole point of this screen is the collection-type split:
///   * household / bulk — every remaining household carries over, so there is
///     nothing to choose. The list is shown read-only and the primary action
///     is a straight "Assign new trip".
///   * bin — the supervisor ticks which collection points carry over. Those
///     daily-stop ids go back as `collection_point_ids`; anything unticked is
///     dropped for the day.
///
/// Pops `true` when a decision was recorded, so the caller refreshes.
class SupervisorRetripReviewScreen extends StatefulWidget {
  const SupervisorRetripReviewScreen({super.key, required this.request});

  final SupervisorRetripRequest request;

  static Future<bool?> push(
    BuildContext context,
    SupervisorRetripRequest request,
  ) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SupervisorRetripReviewScreen(request: request),
      ),
    );
  }

  @override
  State<SupervisorRetripReviewScreen> createState() =>
      _SupervisorRetripReviewScreenState();
}

class _SupervisorRetripReviewScreenState
    extends State<SupervisorRetripReviewScreen> {
  late final Set<String> _selected;
  final _remarksController = TextEditingController();
  bool _busy = false;

  SupervisorRetripRequest get _request => widget.request;

  @override
  void initState() {
    super.initState();
    // Default to carrying everything over — the common case is "the driver ran
    // out of time", not "drop half of these".
    _selected = {for (final stop in _request.liveStops) stop.uniqueId};
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _setAll(bool value) {
    setState(() {
      _selected
        ..clear()
        ..addAll(value ? _request.liveStops.map((s) => s.uniqueId) : const []);
    });
  }

  Future<void> _approve() async {
    if (_busy) return;
    final isHousehold = _request.isHousehold;

    if (!isHousehold && _selected.isEmpty) {
      final confirmed = await _confirmDropAll();
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final newId = await getIt<SupervisorRepository>().approveRetripRequest(
        _request.uniqueId,
        // Households carry over wholesale — sending a list there would be
        // interpreted as a bin-style selection.
        collectionPointIds: isHousehold ? null : _selected.toList(),
        remarks: _remarksController.text,
      );
      if (!mounted) return;
      AppFlash.success(
        context,
        newId != null
            ? 'New trip $newId assigned to the driver'
            : 'Re-Trip approved',
      );
      Navigator.of(context).pop(true);
    } on SupervisorException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final remarks = await _askRejectReason();
    if (remarks == null) return;

    setState(() => _busy = true);
    try {
      await getIt<SupervisorRepository>().rejectRetripRequest(
        _request.uniqueId,
        remarks: remarks,
      );
      if (!mounted) return;
      AppFlash.success(context, 'Request declined — driver notified');
      Navigator.of(context).pop(true);
    } on SupervisorException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDropAll() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carry nothing over?'),
        content: const Text(
          'No collection points are selected, so the trip will be closed and '
          'the remaining stops dropped for today. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close trip'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askRejectReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The trip stays In Progress and the driver is asked to continue '
              'the remaining stops.',
              style: TextStyle(fontSize: 13, color: SupervisorTheme.mutedText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Message to the driver (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: SupervisorTheme.danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHousehold = _request.isHousehold;
    final stops = _request.liveStops;

    return Scaffold(
      backgroundColor: SupervisorTheme.background,
      appBar: AppBar(
        backgroundColor: SupervisorTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Re-Trip request'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 14),
                  _outcomeNotice(isHousehold, stops.length),
                  const SizedBox(height: 14),
                  _stopsHeader(isHousehold, stops.length),
                  const SizedBox(height: 8),
                  if (stops.isEmpty)
                    _emptyStops()
                  else
                    _stopsList(isHousehold, stops),
                  const SizedBox(height: 16),
                  _remarksField(),
                ],
              ),
            ),
            _actionBar(isHousehold),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final rows = <List<String>>[
      ['Trip', _request.assignmentUniqueId],
      ['Area', _request.areaName.isNotEmpty ? _request.areaName : '—'],
      if (_request.vehicleNo.isNotEmpty) ['Vehicle', _request.vehicleNo],
      if (_request.requestedByName.isNotEmpty)
        ['Requested by', _request.requestedByName],
      if (_request.tripDate.isNotEmpty) ['Trip date', _request.tripDate],
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: SupervisorTheme.cardRadius,
        border: Border.all(color: SupervisorTheme.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      row[0],
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SupervisorTheme.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row[1],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SupervisorTheme.strongText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_request.reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: SupervisorTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: SupervisorTheme.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Driver's reason",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: SupervisorTheme.warning,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _request.reason,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: SupervisorTheme.strongText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Says plainly what pressing the primary button will do — the two collection
  /// types behave differently and the supervisor must not have to guess.
  Widget _outcomeNotice(bool isHousehold, int stopCount) {
    final carried = isHousehold ? stopCount : _selected.length;
    final text = isHousehold
        ? 'All $stopCount remaining household(s) will move to a new trip on the '
            'same trip plan. This trip will be closed with its actual end time.'
        : '$carried of $stopCount collection point(s) will move to a new trip. '
            'Unticked stops are dropped for today, and this trip is closed.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SupervisorTheme.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SupervisorTheme.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, size: 17, color: SupervisorTheme.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: SupervisorTheme.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopsHeader(bool isHousehold, int total) {
    return Row(
      children: [
        Expanded(
          child: Text(
            isHousehold
                ? 'Remaining households ($total)'
                : 'Select collection points (${_selected.length}/$total)',
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: SupervisorTheme.strongText,
            ),
          ),
        ),
        // Bulk toggles only make sense where there is a choice to make.
        if (!isHousehold && total > 0)
          TextButton(
            onPressed: _busy
                ? null
                : () => _setAll(_selected.length != total),
            child: Text(
              _selected.length == total ? 'Clear all' : 'Select all',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _emptyStops() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SupervisorTheme.hairline.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 18, color: SupervisorTheme.success),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Nothing is outstanding any more — the crew resolved the '
              'remaining stops after raising this request. Approving will '
              'simply close the trip.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: SupervisorTheme.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopsList(bool isHousehold, List<SupervisorRetripStop> stops) {
    return Container(
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SupervisorTheme.hairline.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stops.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: SupervisorTheme.hairline.withValues(alpha: 0.3),
              ),
            _stopRow(isHousehold, stops[i]),
          ],
        ],
      ),
    );
  }

  Widget _stopRow(bool isHousehold, SupervisorRetripStop stop) {
    final selected = _selected.contains(stop.uniqueId);

    final title = Text(
      stop.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: SupervisorTheme.strongText,
      ),
    );
    final subtitle = Text(
      stop.status.isNotEmpty ? stop.status : 'Pending',
      style: const TextStyle(
        fontSize: 11.5,
        color: SupervisorTheme.mutedText,
        fontWeight: FontWeight.w600,
      ),
    );

    // Households have no choice to make, so render them as a plain read-only
    // list rather than a disabled checkbox (which reads as "blocked").
    if (isHousehold) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.home_rounded,
                size: 17, color: SupervisorTheme.mutedText),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 2), subtitle],
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _busy ? null : () => _toggle(stop.uniqueId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: _busy ? null : (_) => _toggle(stop.uniqueId),
              activeColor: SupervisorTheme.accent,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 2), subtitle],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _remarksField() {
    return TextField(
      controller: _remarksController,
      maxLines: 2,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: 'Remarks (optional)',
        hintText: 'Note for the record…',
        filled: true,
        fillColor: SupervisorTheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        isDense: true,
      ),
    );
  }

  Widget _actionBar(bool isHousehold) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom * 0.2,
      ),
      decoration: BoxDecoration(
        color: SupervisorTheme.surface,
        border: Border(
          top: BorderSide(
            color: SupervisorTheme.hairline.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : _reject,
              style: OutlinedButton.styleFrom(
                foregroundColor: SupervisorTheme.danger,
                side: const BorderSide(color: SupervisorTheme.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Decline',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _busy ? null : _approve,
              style: ElevatedButton.styleFrom(
                backgroundColor: SupervisorTheme.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    SupervisorTheme.accent.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      isHousehold ? 'Assign new trip' : 'Re-Trip',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
