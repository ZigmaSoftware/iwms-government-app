import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:iwms_citizen_app/core/api_config.dart';
import 'package:iwms_citizen_app/core/ui/app_flash.dart';
import 'package:iwms_citizen_app/data/models/operator_trip_models.dart';
import 'package:iwms_citizen_app/data/repositories/auth_repository.dart';
import 'package:iwms_citizen_app/data/repositories/operator_trip_repository.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/captain_theme.dart';
import 'package:iwms_citizen_app/modules/module2_driver/presentation/theme/waste_type_visuals.dart';
import 'package:iwms_citizen_app/modules/module3_operator/services/bluetoothservices.dart';
import 'package:iwms_citizen_app/modules/module3_operator/services/generateunique_id.dart';

/// In-drawer household collection.
///
/// Replaces the old full-screen `OperatorDataScreen` push for the household
/// "Collect" path: the driver scans a QR, and everything — waste selection,
/// weight, photo, submit — happens inside the same bottom sheet. No navigation.
///
/// Flow:
///   1. Customer name + ID at the top.
///   2. A 2x2 grid of the waste types registered against this customer.
///   3. Tapping a card expands it in place into a weight field with a camera
///      button; entering a weight and capturing a photo enables "Add".
///   4. An added card collapses back showing its recorded weight.
///   5. "Submit" finalizes the visit.
///
/// Backend contract is unchanged from the old screen — one
/// `waste/insert-waste-sub/` (or `update-waste-sub/`) multipart per waste type,
/// then a single `waste/finalize-waste/` keyed on the same `screen_unique_id`.
/// That matters: `finalize-waste` aggregates the sub-rows it finds for that
/// screen id, and the backend signal on the resulting WasteCollection is what
/// marks the household stop collected.
///
/// Returns `true` when a finalize succeeded, so the caller refreshes its list.
class HouseholdCollectSheet extends StatefulWidget {
  const HouseholdCollectSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.latitude,
    required this.longitude,
    this.assignmentId,
    this.onSecondaryAction,
  });

  final String customerId;
  final String customerName;
  final String latitude;
  final String longitude;
  final String? assignmentId;

  /// Called with `'collect_later'` or `'not_available'` when the driver picks
  /// one of the bottom exception options. The caller closes this sheet and
  /// runs the reason capture + status POST. Omit to hide those options.
  final void Function(String action)? onSecondaryAction;

  @override
  State<HouseholdCollectSheet> createState() => _HouseholdCollectSheetState();
}

/// Per-waste-stream capture state. Kept as a small mutable object rather than
/// the old screen's `Map<String, dynamic>` bag so the fields are typed and a
/// typo is a compile error.
class _WasteEntry {
  _WasteEntry({required this.id, required this.name});

  final String id;
  final String name;

  final TextEditingController weight = TextEditingController();
  File? photo;

  /// Set once the row has been POSTed. Holds the backend's `unique_id` so a
  /// re-edit becomes an update instead of a duplicate insert.
  String? remoteUniqueId;

  /// The weight as accepted by the server, shown on the collapsed card.
  double? addedWeight;

  bool get isAdded => addedWeight != null;

  double? get parsedWeight {
    final raw = weight.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return value;
  }

  bool get canAdd => parsedWeight != null && photo != null;

  void dispose() => weight.dispose();
}

class _HouseholdCollectSheetState extends State<HouseholdCollectSheet>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final BluetoothService _bluetooth = BluetoothService();

  late final String _screenUniqueId;

  List<_WasteEntry> _entries = const [];
  bool _loadingTypes = true;
  bool _loadError = false;

  /// Which card is currently expanded for entry. Null = all collapsed.
  String? _activeId;

  bool _submitting = false;
  String? _addingId;

  // ── Bluetooth scale ──────────────────────────────────────────────────────
  // Classic SPP is Android-only (the HC-05 / AEBT scale modules are not
  // Apple-MFi), so on iOS the scale UI is hidden and entry is manual.
  bool get _scaleSupported => Platform.isAndroid;
  BluetoothConnection? _connection;
  bool _connected = false;
  bool _connecting = false;
  String? _deviceName;
  String _liveWeight = '--';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _screenUniqueId = UniqueIdService.generateScreenUniqueId();
    _loadWasteTypes();
    if (_scaleSupported) _initScale();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      _connection?.dispose();
    } catch (_) {}
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scaleSupported && state == AppLifecycleState.resumed && !_connected) {
      _initScale();
    }
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<void> _loadWasteTypes() async {
    try {
      final types = await GetIt.instance<OperatorTripRepository>()
          .fetchCustomerWasteTypes(widget.customerId);
      if (!mounted) return;
      setState(() {
        _entries = _prioritize(types)
            .map((t) => _WasteEntry(id: t.id, name: t.name))
            .toList();
        _loadingTypes = false;
      });
    } catch (e, st) {
      // Don't swallow silently — an empty grid used to be indistinguishable
      // from "this customer genuinely has no waste types registered".
      debugPrint('household waste-type load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loadingTypes = false;
        _loadError = true;
      });
    }
  }

  /// Wet first, then Dry, then everything else in API order — the two primary
  /// segregated streams are what the driver reaches for most.
  List<CustomerWasteType> _prioritize(List<CustomerWasteType> types) {
    int rank(CustomerWasteType t) {
      final k = t.name.toLowerCase();
      if (k.contains('wet')) return 0;
      if (k.contains('dry')) return 1;
      return 2;
    }

    final indexed = types.asMap().entries.toList()
      ..sort((a, b) {
        final byRank = rank(a.value).compareTo(rank(b.value));
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Future<Map<String, String>> _authHeaders() async {
    try {
      final user = await GetIt.instance<AuthRepository>()
          .getAuthenticatedUser();
      final token = user?.authToken?.trim();
      if (token != null && token.isNotEmpty) {
        return {'Authorization': 'Bearer $token'};
      }
    } catch (_) {}
    return const {};
  }

  // ── Bluetooth ────────────────────────────────────────────────────────────

  Future<void> _initScale() async {
    if (!_scaleSupported || _connected || _connecting) return;
    setState(() => _connecting = true);
    try {
      final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) {
        await FlutterBluetoothSerial.instance.requestEnable();
      }
      await _bluetooth.connect();
      _bluetooth.weightStream.listen(_onScaleReading);
      if (!mounted) return;
      setState(() {
        _connected = _bluetooth.connected;
        _deviceName = 'Weighing scale';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _connected = false);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// A reading only auto-fills the card the driver is currently on, and only
  /// while it hasn't been added yet — otherwise a chattering scale would
  /// silently rewrite a weight the driver already committed.
  void _onScaleReading(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    if (!mounted) return;
    setState(() => _liveWeight = cleaned.isEmpty ? '--' : cleaned);

    final activeId = _activeId;
    if (activeId == null || cleaned.isEmpty) return;
    final entry = _entryFor(activeId);
    if (entry == null || entry.isAdded) return;
    entry.weight.text = cleaned;
    setState(() {});
  }

  _WasteEntry? _entryFor(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _toggleCard(_WasteEntry entry) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_activeId == entry.id) {
        _activeId = null;
      } else {
        _activeId = entry.id;
        // Seed from the live scale so the driver usually just taps Add.
        if (!entry.isAdded &&
            entry.weight.text.trim().isEmpty &&
            _liveWeight != '--') {
          entry.weight.text = _liveWeight;
        }
      }
    });
  }

  Future<void> _capturePhoto(_WasteEntry entry) async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (shot == null || !mounted) return;
      setState(() => entry.photo = File(shot.path));
    } catch (e) {
      if (mounted) AppFlash.error(context, 'Could not open camera: $e');
    }
  }

  /// POSTs one waste row. Insert the first time, update on re-edit — the old
  /// screen's behaviour, so editing a weight never leaves a duplicate row
  /// behind for `finalize-waste` to double-count.
  Future<void> _add(_WasteEntry entry) async {
    final weight = entry.parsedWeight;
    if (weight == null) {
      AppFlash.warning(context, 'Enter a weight for ${entry.name}');
      return;
    }
    if (entry.photo == null) {
      AppFlash.warning(context, 'Capture a photo for ${entry.name}');
      return;
    }

    setState(() => _addingId = entry.id);
    try {
      final isUpdate = entry.remoteUniqueId != null;
      final uri = Uri.parse(
        isUpdate
            ? '${ApiConfig.desktopBase}waste/update-waste-sub/'
            : '${ApiConfig.desktopBase}waste/insert-waste-sub/',
      );

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = _screenUniqueId
        ..fields['customer_id'] = widget.customerId
        // Both keys are sent because the backend has read each at different
        // times; harmless and keeps older deployments working.
        ..fields['waste_type'] = entry.id
        ..fields['waste_type_id'] = entry.id
        ..fields['weight'] = weight.toString()
        ..fields['latitude'] = widget.latitude
        ..fields['longitude'] = widget.longitude;

      if (isUpdate) request.fields['unique_id'] = entry.remoteUniqueId!;
      request.files.add(
        await http.MultipartFile.fromPath('image', entry.photo!.path),
      );

      final streamed = await request.send();
      if (streamed.statusCode >= 400) {
        throw Exception('Server error ${streamed.statusCode}');
      }
      final body = json.decode(
        (await http.Response.fromStream(streamed)).body,
      );
      if (body['status'] != 'success') {
        throw Exception(body['message'] ?? 'Could not save ${entry.name}');
      }

      if (!mounted) return;
      setState(() {
        entry.remoteUniqueId =
            body['unique_id']?.toString() ?? entry.remoteUniqueId;
        entry.addedWeight = weight;
        _activeId = null;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        AppFlash.error(context, 'Could not add ${entry.name}: $e');
      }
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  double get _total => _entries.fold(
        0.0,
        (sum, e) => sum + (e.addedWeight ?? 0),
      );

  int get _addedCount => _entries.where((e) => e.isAdded).length;

  Future<void> _submit() async {
    if (_addedCount == 0) {
      AppFlash.warning(context, 'Add at least one waste weight first');
      return;
    }
    setState(() => _submitting = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.desktopBase}waste/finalize-waste/'),
      )
        ..headers.addAll(await _authHeaders())
        ..fields['screen_unique_id'] = _screenUniqueId
        ..fields['customer_id'] = widget.customerId
        ..fields['entry_type'] = 'app'
        // Scopes the collection to this trip, so the backend marks the right
        // household stop (a driver can hold a bin AND a household trip).
        ..fields['assignment_id'] = widget.assignmentId ?? ''
        ..fields['total_waste_collected'] = _total.toString();

      final response = await http.Response.fromStream(
        await request.send(),
      );
      final result = json.decode(response.body);

      if (result['status'] != 'success') {
        // A refusal the server actually answered (e.g. the trip isn't
        // started). Surface it and leave the visit open rather than pretending
        // the household was collected.
        if (mounted) {
          AppFlash.warning(
            context,
            result['message']?.toString() ?? 'Could not submit this collection',
          );
        }
        return;
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) AppFlash.error(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 14),
            if (_scaleSupported) ...[
              _scaleBar(),
              const SizedBox(height: 14),
            ],
            if (_loadingTypes)
              _loadingBlock()
            else if (_entries.isEmpty)
              _emptyBlock()
            else
              _wasteGrid(),
            if (_addedCount > 0) ...[
              const SizedBox(height: 16),
              _totalBar(),
            ],
            const SizedBox(height: 16),
            _submitButton(),
            // Secondary outcomes live at the bottom of this same drawer, behind
            // a divider — collecting is the common case, these are exceptions.
            // Hidden once a weight has been added, since "not available" would
            // then contradict data already sent to the server.
            if (_addedCount == 0 && widget.onSecondaryAction != null) ...[
              const SizedBox(height: 18),
              Divider(color: CaptainTheme.hairline, height: 1),
              const SizedBox(height: 14),
              Text(
                "Can't collect right now?",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: CaptainTheme.mutedText,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CaptainTheme.strongText,
                        side: BorderSide(color: CaptainTheme.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => widget.onSecondaryAction!('collect_later'),
                      child: const Text('Collect later'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CaptainTheme.strongText,
                        side: BorderSide(color: CaptainTheme.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _submitting
                          ? null
                          : () => widget.onSecondaryAction!('not_available'),
                      child: const Text('Not available'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.customerName.trim().isEmpty
              ? 'Household'
              : widget.customerName,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: CaptainTheme.strongText,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'ID: ${widget.customerId}',
          style: TextStyle(
            color: CaptainTheme.mutedText,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _scaleBar() {
    final connected = _connected;
    final color = connected ? CaptainTheme.success : CaptainTheme.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected
                      ? (_deviceName ?? 'Scale connected')
                      : 'Scale not connected',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
                if (connected)
                  Text(
                    'Live: $_liveWeight kg',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: CaptainTheme.mutedText,
                    ),
                  )
                else
                  Text(
                    'You can still type weights manually',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: CaptainTheme.mutedText,
                    ),
                  ),
              ],
            ),
          ),
          if (_connecting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!connected)
            TextButton(
              onPressed: _initScale,
              child: const Text('Connect'),
            ),
        ],
      ),
    );
  }

  Widget _loadingBlock() {
    return Container(
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      ),
    );
  }

  Widget _emptyBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CaptainTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CaptainTheme.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _loadError
                ? "Couldn't load this customer's waste types. Check your "
                    'connection and try again.'
                : 'No waste types are registered for this customer. Ask your '
                    'supervisor to set them in Customer Creation.',
            style: TextStyle(
              color: CaptainTheme.mutedText,
              fontWeight: FontWeight.w600,
              height: 1.4,
              fontSize: 12.5,
            ),
          ),
          if (_loadError) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _loadingTypes = true;
                  _loadError = false;
                });
                _loadWasteTypes();
              },
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  /// 2-up grid of collapsed cards, but the expanded card takes the full width
  /// so the weight field and camera button have room to breathe. Laid out
  /// manually (rows of two) rather than with GridView so one card can span.
  Widget _wasteGrid() {
    final rows = <Widget>[];
    var i = 0;
    while (i < _entries.length) {
      final entry = _entries[i];
      if (entry.id == _activeId) {
        rows.add(_expandedCard(entry));
        i += 1;
        continue;
      }
      // Pair this card with the next one, unless the next is the expanded one.
      final next = (i + 1 < _entries.length) ? _entries[i + 1] : null;
      if (next != null && next.id != _activeId) {
        // IntrinsicHeight (not CrossAxisAlignment.stretch) so the two cards
        // match heights: stretch hands children an unbounded height, which
        // throws "BoxConstraints forces an infinite height".
        rows.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _collapsedCard(entry)),
              const SizedBox(width: 10),
              Expanded(child: _collapsedCard(next)),
            ],
          ),
        ));
        i += 2;
      } else {
        // Odd one out — half width, so it still reads as part of the grid
        // instead of stretching across the whole row.
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _collapsedCard(entry)),
            const SizedBox(width: 10),
            const Expanded(child: SizedBox.shrink()),
          ],
        ));
        i += 1;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          rows[r],
        ],
      ],
    );
  }

  Widget _collapsedCard(_WasteEntry entry) {
    final visual = WasteTypeVisual.forName(entry.name);
    final added = entry.isAdded;
    // Each stream keeps its own hue whether or not it's been collected — the
    // grid should read as colour-coded waste types at a glance, with a check
    // mark (not a colour change) signalling "done", so the driver can still
    // find "the green one" after adding it.
    final accent = visual.color;

    return _AnimatedCardShell(
      onTap: () => _toggleCard(entry),
      accent: accent,
      filled: true,
      strongFill: added,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Solid icon plate — the main source of colour in the card.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(visual.icon, size: 19, color: Colors.white),
              ),
              const Spacer(),
              if (added)
                Icon(Icons.check_circle_rounded, size: 19, color: accent)
              else
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 19,
                  color: accent.withValues(alpha: 0.55),
                ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            entry.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: CaptainTheme.strongText,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            added ? '${_fmt(entry.addedWeight!)} kg' : 'Tap to add weight',
            style: TextStyle(
              fontSize: added ? 16 : 11.5,
              fontWeight: added ? FontWeight.w900 : FontWeight.w600,
              color: added ? accent : CaptainTheme.mutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expandedCard(_WasteEntry entry) {
    final visual = WasteTypeVisual.forName(entry.name);
    final busy = _addingId == entry.id;

    return _AnimatedCardShell(
      accent: visual.color,
      expanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(visual.icon, size: 19, color: visual.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: CaptainTheme.strongText,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => _toggleCard(entry),
                icon: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: CaptainTheme.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: entry.weight,
            autofocus: true,
            enabled: !busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: CaptainTheme.strongText,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              suffixText: 'kg',
              filled: true,
              fillColor: CaptainTheme.surfaceMuted,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: CaptainTheme.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: CaptainTheme.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: visual.color, width: 1.5),
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _cameraButton(entry, visual.color, busy),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed:
                  (!busy && entry.canAdd) ? () => _add(entry) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: visual.color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: CaptainTheme.surfaceMuted,
                disabledForegroundColor: CaptainTheme.mutedText,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      entry.photo == null
                          ? 'Capture photo to add'
                          : (entry.parsedWeight == null
                              ? 'Enter weight to add'
                              : 'Add'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Camera affordance inside the weight field's suffix. Shows a thumbnail once
  /// a photo exists, so the driver can see at a glance that it's captured.
  Widget _cameraButton(_WasteEntry entry, Color accent, bool busy) {
    final hasPhoto = entry.photo != null;
    return GestureDetector(
      onTap: busy ? null : () => _capturePhoto(entry),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasPhoto
              ? accent.withValues(alpha: 0.14)
              : CaptainTheme.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: hasPhoto ? accent : CaptainTheme.hairline,
          ),
          image: hasPhoto
              ? DecorationImage(
                  image: FileImage(entry.photo!),
                  fit: BoxFit.cover,
                  opacity: 0.55,
                )
              : null,
        ),
        child: Icon(
          hasPhoto ? Icons.check_rounded : Icons.photo_camera_rounded,
          size: 19,
          color: hasPhoto ? accent : CaptainTheme.mutedText,
        ),
      ),
    );
  }

  Widget _totalBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CaptainTheme.accentSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CaptainTheme.accent.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.scale_rounded, size: 18, color: CaptainTheme.accentDeep),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$_addedCount of ${_entries.length} added',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: CaptainTheme.strongText,
              ),
            ),
          ),
          Text(
            '${_fmt(_total)} kg',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: CaptainTheme.accentDeep,
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    final enabled = _addedCount > 0 && !_submitting;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: CaptainTheme.accentDeep,
          foregroundColor: Colors.white,
          disabledBackgroundColor: CaptainTheme.surfaceMuted,
          disabledForegroundColor: CaptainTheme.mutedText,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _addedCount == 0 ? 'Add a weight to submit' : 'Submit',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }

  static String _fmt(double v) =>
      v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// Shared card chrome with the expand/collapse animation.
///
/// The size change is driven by `AnimatedSize` on the real content rather than
/// a hard-coded height, so a long waste-type name or a large text scale can't
/// clip — and the spring curve is what gives it the settled, iOS-like feel.
class _AnimatedCardShell extends StatelessWidget {
  const _AnimatedCardShell({
    required this.child,
    required this.accent,
    this.onTap,
    this.filled = false,
    this.strongFill = false,
    this.expanded = false,
  });

  final Widget child;
  final Color accent;
  final VoidCallback? onTap;

  /// Tints the card with [accent] instead of the neutral surface.
  final bool filled;

  /// Deepens that tint and the border — used once a weight is recorded, so a
  /// completed card is obvious without losing its stream colour.
  final bool strongFill;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(expanded ? 18 : 16);

    // NOTE: deliberately no AnimatedSize here. It measures its child against
    // unbounded height, which blows up ("BoxConstraints forces an infinite
    // height") the moment a card sits inside a Row — the 2-up grid. The
    // expand/collapse still animates: the whole card is swapped between the
    // collapsed and expanded layouts, and AnimatedContainer tweens the padding,
    // fill, border and radius across that swap.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: expanded
            ? CaptainTheme.surface
            : (filled
                ? accent.withValues(alpha: strongFill ? 0.18 : 0.10)
                : CaptainTheme.surfaceMuted),
        borderRadius: radius,
        border: Border.all(
          color: (filled || expanded)
              ? accent.withValues(
                  alpha: expanded ? 0.55 : (strongFill ? 0.7 : 0.32),
                )
              : CaptainTheme.hairline,
          width: expanded ? 1.5 : (strongFill ? 1.5 : 1),
        ),
        boxShadow: expanded ? CaptainTheme.softShadow : const [],
      ),
      // Material+InkWell inside the decorated box so the ripple is clipped to
      // the same rounded rect, without a Material fill painting over the tint.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(expanded ? 14 : 13),
            child: child,
          ),
        ),
      ),
    );
  }
}
