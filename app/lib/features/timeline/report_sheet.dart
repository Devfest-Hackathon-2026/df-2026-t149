import 'package:flutter/material.dart';

import '../../core/models/timeline_entry.dart';
import '../../core/strings.dart';

/// 報告の理由とひとこと
@immutable
class ReportChoice {
  const ReportChoice(this.reason, this.note);

  final ReportReason reason;
  final String note;
}

extension ReportReasonLabel on ReportReason {
  String get label => switch (this) {
    ReportReason.inappropriate => l10n.reportReasonInappropriate,
    ReportReason.unrelated => l10n.reportReasonUnrelated,
    ReportReason.personal => l10n.reportReasonPersonal,
    ReportReason.spam => l10n.reportReasonSpam,
    ReportReason.other => l10n.reportReasonOther,
  };
}

/// 報告の理由を選ぶ画面を下から開く。やめたときは null
Future<ReportChoice?> showReportSheet(BuildContext context) =>
    showModalBottomSheet<ReportChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ReportSheet(),
    );

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReportReason? reason = _reason;
    return Padding(
      // キーボードを出しても、ひとことの欄と送るボタンが隠れないようにする
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  l10n.reportSheetTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  l10n.reportSheetHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              RadioGroup<ReportReason>(
                groupValue: reason,
                onChanged: (ReportReason? r) => setState(() => _reason = r),
                child: Column(
                  children: <Widget>[
                    for (final ReportReason r in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: r,
                        title: Text(r.label),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _note,
                  maxLength: 200,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: l10n.reportNoteHint),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: reason == null
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(ReportChoice(reason, _note.text.trim())),
                  icon: const Icon(Icons.flag_outlined),
                  label: Text(l10n.reportSend),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
