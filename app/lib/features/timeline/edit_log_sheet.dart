import 'package:flutter/material.dart';

import '../../core/data/checkin_repository.dart';
import '../../core/haptics.dart';
import '../../core/sounds.dart';
import '../../core/models/memory_log.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../core/widgets/star_rating.dart';
import '../../core/widgets/state_view.dart';
import '../../core/strings.dart';

/// 自分の記録の★評価とひとことを直すシートを開く。直したら直した後の記録を返し、やめたら null
Future<MemoryLog?> showEditLogSheet(BuildContext context, MemoryLog log) =>
    showModalBottomSheet<MemoryLog>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => EditLogSheet(log: log),
    );

class EditLogSheet extends StatefulWidget {
  const EditLogSheet({super.key, required this.log});

  final MemoryLog log;

  @override
  State<EditLogSheet> createState() => _EditLogSheetState();
}

class _EditLogSheetState extends State<EditLogSheet> {
  late int _rating = widget.log.stars;
  late final TextEditingController _comment = TextEditingController(
    text: widget.log.comment,
  );
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final CheckinRepository checkins = Services.of(context).checkins;
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final MemoryLog edited = await checkins.editLog(
        widget.log,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      Haptics.success();
      Sounds.success();
      navigator.pop(edited);
      messenger.showSnackBar(SnackBar(content: Text(l10n.logEdited)));
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.logEditFailed(describeError(error)))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      // キーボードが出ても入力欄が隠れないようにする
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.editLog, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                widget.log.placeName.isEmpty
                    ? l10n.placeNameUnavailable
                    : widget.log.placeName,
                style: AppTheme.placeName(16),
              ),
              const SizedBox(height: 16),
              StarRatingInput(
                value: _rating,
                onChanged: (int r) => setState(() => _rating = r),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _comment,
                maxLength: 140,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(hintText: l10n.comment),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? l10n.saving : l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
