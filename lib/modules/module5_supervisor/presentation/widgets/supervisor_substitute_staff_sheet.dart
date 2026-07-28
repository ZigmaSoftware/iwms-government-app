import 'package:flutter/material.dart';

import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_models.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/data/supervisor_repository.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/theme/supervisor_theme.dart';
import 'package:iwms_citizen_app/modules/module5_supervisor/presentation/widgets/supervisor_alt_staff_template_form.dart';

/// "Substitute staff" — pick an existing `AlternativeStaffTemplate` (created
/// under the supervisor's hierarchy) and apply it onto [assignmentId], or
/// create a new one via "Form ALT" first. Pops `true` once a substitution is
/// successfully applied.
class SupervisorSubstituteStaffSheet extends StatefulWidget {
  const SupervisorSubstituteStaffSheet({super.key, required this.assignmentId});

  final String assignmentId;

  static Future<bool?> show(BuildContext context, {required String assignmentId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SupervisorSubstituteStaffSheet(assignmentId: assignmentId),
    );
  }

  @override
  State<SupervisorSubstituteStaffSheet> createState() =>
      _SupervisorSubstituteStaffSheetState();
}

class _SupervisorSubstituteStaffSheetState
    extends State<SupervisorSubstituteStaffSheet> {
  final SupervisorRepository _repo = SupervisorRepository();

  bool _loading = true;
  String? _loadError;
  bool _applying = false;
  String? _applyError;

  List<SupervisorAltStaffTemplate> _templates = const [];
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final templates = await _repo.fetchAlternativeStaffTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        if (_selectedId != null &&
            !templates.any((t) => t.uniqueId == _selectedId)) {
          _selectedId = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createNew() async {
    final created = await SupervisorAltStaffTemplateForm.show(context);
    if (created == true) await _load();
  }

  Future<void> _apply() async {
    if (_selectedId == null) return;
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      await _repo.applyAlternativeStaffTemplate(
        assignmentId: widget.assignmentId,
        altStaffTemplateId: _selectedId!,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applyError = e.toString();
        _applying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: SupervisorTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SupervisorTheme.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Substitute staff',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: SupervisorTheme.strongText,
                ),
              ),
            ),
            Flexible(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(color: SupervisorTheme.accent),
        ),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!,
                style: const TextStyle(color: SupervisorTheme.mutedText)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: SupervisorTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alternative staff templates created under your hierarchy:',
            style: const TextStyle(
              fontSize: 12.5,
              color: SupervisorTheme.mutedText,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedId,
            isExpanded: true,
            style: SupervisorTheme.inputTextStyle,
            dropdownColor: SupervisorTheme.surface,
            decoration: SupervisorTheme.inputDecoration(
              'Alternative staff template',
            ),
            items: _templates
                .map((t) => DropdownMenuItem(
                      value: t.uniqueId,
                      child: Text(t.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _selectedId = v),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _createNew,
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text('Create new'),
              style: TextButton.styleFrom(foregroundColor: SupervisorTheme.accent),
            ),
          ),
          if (_applyError != null) ...[
            const SizedBox(height: 10),
            Text(_applyError!,
                style: const TextStyle(color: SupervisorTheme.danger)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _applying
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_selectedId != null && !_applying) ? _apply : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SupervisorTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: _applying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
