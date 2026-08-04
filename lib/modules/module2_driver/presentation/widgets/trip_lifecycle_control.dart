import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:iwms_citizen_app/core/ui/app_flash.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';

/// Start / End control for the trip hero card.
///
/// Three states, driven entirely by [trip]:
///   * not started  -> "Start Trip" pill
///   * in progress  -> "End Trip" pill
///   * retrip pending -> a banner; no button (the driver already asked, the
///     supervisor decides next — see `TripRetripRequest`)
///
/// [onChanged] is called after any successful start/end so the caller can
/// refresh (mirrors `onChanged` on the stop tiles / household action sheet).
class TripLifecycleControl extends StatefulWidget {
  const TripLifecycleControl({
    super.key,
    required this.trip,
    required this.locked,
    required this.onChanged,
  });

  final OperatorTripToday trip;
  final bool locked;
  final VoidCallback onChanged;

  @override
  State<TripLifecycleControl> createState() => _TripLifecycleControlState();
}

class _TripLifecycleControlState extends State<TripLifecycleControl> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await GetIt.instance<OperatorTripRepository>().startTrip(
        widget.trip.assignmentUniqueId,
      );
      if (mounted) AppFlash.success(context, 'Trip started');
      widget.onChanged();
    } on OperatorTripException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end({String? reason}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await GetIt.instance<OperatorTripRepository>().endTrip(
        widget.trip.assignmentUniqueId,
        reason: reason,
      );

      if (result.reasonRequired) {
        if (!mounted) return;
        setState(() => _busy = false);
        final givenReason = await showEndTripReasonSheet(
          context,
          pendingBinCount: result.pendingBinCount,
          pendingHouseholdCount: result.pendingHouseholdCount,
        );
        if (givenReason != null && givenReason.trim().isNotEmpty) {
          await _end(reason: givenReason.trim());
        }
        return;
      }

      if (result.ended) {
        if (mounted) AppFlash.success(context, 'Trip completed');
      } else if (result.retripRequested) {
        if (mounted) {
          AppFlash.success(
            context,
            'Requested next trip for the remaining stops — awaiting supervisor approval',
          );
        }
      }
      widget.onChanged();
    } on OperatorTripException catch (e) {
      if (mounted) AppFlash.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEnd() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: CaptainTheme.surface,
      builder: (sheetContext) => _ConfirmEndSheet(trip: widget.trip),
    );
    if (confirmed == true) await _end();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;

    if (trip.hasPendingRetrip) {
      final retrip = trip.retripRequest!;
      return _PendingRetripBanner(retrip: retrip);
    }

    if (widget.locked || trip.isFinished) {
      return const SizedBox.shrink();
    }

    final isRunning = trip.isStarted && trip.status.toLowerCase() == 'in progress';

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : (isRunning ? _confirmEnd : _start),
        style: ElevatedButton.styleFrom(
          backgroundColor: isRunning ? CaptainTheme.danger : CaptainTheme.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              (isRunning ? CaptainTheme.danger : CaptainTheme.accent)
                  .withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(
          isRunning ? 'End Trip' : 'Start Trip',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ConfirmEndSheet extends StatelessWidget {
  const _ConfirmEndSheet({required this.trip});

  final OperatorTripToday trip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'End this trip?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CaptainTheme.strongText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trip.progress.resolved >= trip.progress.total
                  ? 'All stops are resolved. The trip will be marked completed.'
                  : 'You still have ${trip.progress.total - trip.progress.resolved} stop(s) '
                      'left. If you end now, you\'ll be asked for a reason and a '
                      'supervisor will need to approve carrying the rest to a new trip.',
              style: TextStyle(fontSize: 14, color: CaptainTheme.mutedText, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CaptainTheme.danger,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('End Trip'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the driver taps a stop (bin or household) before pressing
/// Start. The backend rejects any collection write on a not-started trip
/// (`TRIP_NOT_STARTED`), so this is purely explanatory — there is nothing to
/// confirm, just a short sheet telling the driver what to do first.
void showStartRequiredSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: CaptainTheme.surface,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_clock_rounded, color: CaptainTheme.accent, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Start required',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: CaptainTheme.strongText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Press "Start Trip" first to begin collecting stops on this trip.',
              style: TextStyle(fontSize: 13.5, color: CaptainTheme.mutedText, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: CaptainTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The mandatory-reason prompt shown when stops remain. Returns the trimmed
/// reason, or `null` if the driver backed out.
Future<String?> showEndTripReasonSheet(
  BuildContext context, {
  required int pendingBinCount,
  required int pendingHouseholdCount,
}) {
  final pendingTotal = pendingBinCount + pendingHouseholdCount;
  final controller = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: CaptainTheme.surface,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_rounded, color: CaptainTheme.gold, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$pendingTotal stop${pendingTotal == 1 ? '' : 's'} still pending',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: CaptainTheme.strongText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${[
                    if (pendingBinCount > 0) '$pendingBinCount collection point(s)',
                    if (pendingHouseholdCount > 0) '$pendingHouseholdCount household(s)',
                  ].join(' and ')} have not been collected or marked yet. Enter a '
                  'reason to request the next trip for the remaining stops — a '
                  'supervisor will review and approve it.',
                  style: TextStyle(fontSize: 13.5, color: CaptainTheme.mutedText, height: 1.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'Reason',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CaptainTheme.strongText,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'e.g. Vehicle full, shift ending, road blocked…',
                    filled: true,
                    fillColor: CaptainTheme.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (_, value, __) => ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CaptainTheme.accent,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : () => Navigator.of(sheetContext).pop(value.text.trim()),
                          child: const Text('Request Next Trip'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PendingRetripBanner extends StatelessWidget {
  const _PendingRetripBanner({required this.retrip});

  final OperatorTripRetripRequest retrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CaptainTheme.goldSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CaptainTheme.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, color: CaptainTheme.gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Awaiting supervisor approval',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: CaptainTheme.strongText,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Requested to end this trip with ${retrip.pendingTotal} stop(s) left. '
                  'You can keep collecting while you wait.',
                  style: TextStyle(fontSize: 12.5, color: CaptainTheme.mutedText, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
