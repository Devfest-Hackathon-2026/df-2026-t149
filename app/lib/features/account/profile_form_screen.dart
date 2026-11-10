import 'package:flutter/material.dart';

import '../../core/api/uramichi_api.dart';
import '../../core/models/profile.dart';
import '../../core/widgets/profile_avatar.dart';
import '../../core/strings.dart';

/// ニックネームとアイコンを決める画面。初めてログインしたときと、設定から変更するときに使う
class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({
    super.key,
    this.initial,
    required this.submitLabel,
    required this.onSubmit,
    this.onSignOut,
  });

  /// 変更するときの今のプロフィール。初めてのときは null
  final Profile? initial;
  final String submitLabel;

  /// 保存する。失敗したら例外を投げ、画面に理由を表示する
  final Future<void> Function(Profile profile) onSubmit;

  /// 初めてのときに、別のアカウントでログインし直すための操作
  final VoidCallback? onSignOut;

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  late final TextEditingController _nickname = TextEditingController(
    text: widget.initial?.nickname ?? '',
  );
  late ProfileIcon _icon = widget.initial == null
      ? ProfileIcon.values.first
      : ProfileIcon.of(widget.initial!.icon);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  String? get _validNickname => Profile.normalizeNickname(_nickname.text);

  Future<void> _submit() async {
    final String? nickname = _validNickname;
    if (nickname == null || _saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(Profile(nickname: nickname, icon: _icon.id));
    } on ApiException catch (error) {
      // 保存している間にログアウトすると、この画面はもうない
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.errorProfileSave);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? error = _error;
    final VoidCallback? onSignOut = widget.onSignOut;
    final bool isFirstTime = widget.initial == null;

    return Scaffold(
      appBar: isFirstTime
          ? AppBar(
              automaticallyImplyLeading: false,
              actions: <Widget>[
                if (onSignOut != null)
                  // 保存している間はログアウトさせない（保存の後にログインした状態へ戻ってしまうため）
                  TextButton(
                    onPressed: _saving ? null : onSignOut,
                    child: Text(l10n.logout),
                  ),
              ],
            )
          : AppBar(title: Text(l10n.profile)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: <Widget>[
                Center(child: ProfileAvatar(icon: _icon, size: 96)),
                const SizedBox(height: 12),
                ListenableBuilder(
                  listenable: _nickname,
                  builder: (BuildContext context, Widget? _) => Text(
                    _nickname.text.trim(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: _nickname,
                  builder: (BuildContext context, Widget? _) => TextField(
                    controller: _nickname,
                    autofocus: isFirstTime,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.nickname,
                      hintText: l10n.nicknameHint,
                      helperText: l10n.nicknameHelper,
                      counterText:
                          '${Profile.nicknameLength(_nickname.text)}/${Profile.nicknameMaxLength}',
                      errorText:
                          Profile.nicknameLength(_nickname.text) >
                              Profile.nicknameMaxLength
                          ? l10n.nicknameTooLong(Profile.nicknameMaxLength)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(l10n.icon, style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                _IconGrid(
                  selected: _icon,
                  onSelected: (ProfileIcon icon) =>
                      setState(() => _icon = icon),
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: _nickname,
                  builder: (BuildContext context, Widget? _) => FilledButton(
                    onPressed: _validNickname == null || _saving
                        ? null
                        : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(widget.submitLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 選べるアイコンを並べ、選んだものを枠で示す
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.selected, required this.onSelected});

  final ProfileIcon selected;
  final ValueChanged<ProfileIcon> onSelected;

  /// 12種類を2行に収める列の数
  static const int _columns = 6;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cell =
            ((constraints.maxWidth - _gap * (_columns - 1)) / _columns).clamp(
              48,
              64,
            );
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: <Widget>[
            for (final ProfileIcon icon in ProfileIcon.values)
              Tooltip(
                message: icon.label,
                child: Semantics(
                  selected: icon == selected,
                  button: true,
                  label: icon.label,
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: () => onSelected(icon),
                    radius: cell / 2,
                    child: Container(
                      width: cell,
                      height: cell,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: icon == selected
                              ? scheme.onSurface
                              : Colors.transparent,
                        ),
                      ),
                      child: ProfileAvatar(icon: icon, size: cell - 12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
