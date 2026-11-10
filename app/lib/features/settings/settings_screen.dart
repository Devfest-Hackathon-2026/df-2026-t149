import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/notifications.dart';
import '../../core/widgets/google_maps_notice.dart';

import '../../core/auth/account_controller.dart';
import '../../core/models/profile.dart';
import '../../core/haptics.dart';
import '../../core/services.dart';
import '../../core/settings.dart';
import '../../core/sounds.dart';
import '../../core/theme.dart';
import '../../core/widgets/profile_avatar.dart';
import '../account/profile_form_screen.dart';
import '../../core/strings.dart';

/// 見出しの右端に置く、設定の画面を開くボタン。自分のアイコンで表示し、ログインしているアカウントを示す
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final AccountController account = Services.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (BuildContext context, Widget? _) {
        final AccountState state = account.state;
        return IconButton(
          tooltip: l10n.settings,
          icon: state is AccountReady
              ? ProfileAvatar(
                  icon: ProfileIcon.of(state.profile.icon),
                  size: 32,
                )
              : const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) => const SettingsScreen(),
            ),
          ),
        );
      },
    );
  }
}

/// プロフィール、見た目、動き、データの設定とログアウト
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Services services = Services.of(context);
    final AppSettings settings = services.settings;
    final ThemeData theme = Theme.of(context);
    // 3ボタンのナビゲーションバーの下にログアウトが隠れないよう、端末の下の余白を足す
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (BuildContext context, Widget? _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset),
              children: <Widget>[
                _ProfileTile(account: services.account),
                _SectionTitle(l10n.settingsAppearance),
                _SectionCard(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        l10n.settingsTheme,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: <ButtonSegment<ThemeMode>>[
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text(l10n.themeSystem),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text(l10n.themeLight),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text(l10n.themeDark),
                          ),
                        ],
                        selected: <ThemeMode>{settings.themeMode},
                        onSelectionChanged: (Set<ThemeMode> s) =>
                            settings.themeMode = s.first,
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Text(
                        l10n.settingsKeyColor,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _KeyColorPicker(settings: settings),
                    ),
                  ],
                ),
                _SectionTitle(l10n.settingsMotionSound),
                _SectionCard(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.vibration),
                      title: Text(l10n.settingsHaptics),
                      subtitle: Text(l10n.settingsHapticsDescription),
                      value: settings.hapticsEnabled,
                      onChanged: (bool on) {
                        settings.hapticsEnabled = on;
                        // オンにしたときに、どのくらい振動するかを試せるようにする
                        Haptics.success();
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.volume_up_outlined),
                      title: Text(l10n.settingsSound),
                      subtitle: Text(l10n.settingsSoundDescription),
                      value: settings.soundEnabled,
                      onChanged: (bool on) {
                        settings.soundEnabled = on;
                        // オンにしたときに、どんな音かを試せるようにする
                        Sounds.success();
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.notifications_outlined),
                      title: Text(l10n.settingsNotifications),
                      subtitle: Text(
                        AppNotifications.supported
                            ? l10n.settingsNotificationsDescription
                            : l10n.settingsNotificationsWeb,
                      ),
                      value: settings.notificationsEnabled,
                      onChanged: (bool on) async {
                        settings.notificationsEnabled = on;
                        // オンにしたときに、端末の通知の許可を聞く
                        if (on && AppNotifications.supported) {
                          final ScaffoldMessengerState messenger =
                              ScaffoldMessenger.of(context);
                          if (!await AppNotifications.requestPermission()) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(l10n.notificationsDenied)),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                _SectionTitle(l10n.settingsData),
                _SectionCard(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.science_outlined),
                      title: Text(l10n.settingsDemoData),
                      subtitle: Text(l10n.settingsDemoDataDescription),
                      value: settings.demoMode,
                      onChanged: (bool on) => settings.demoMode = on,
                    ),
                    // 接続先は開発中に確かめるための表示で、利用者が使う情報ではないため、配布用のビルドでは表示しない
                    if (!kReleaseMode)
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: Text(l10n.settingsEndpoint),
                        subtitle: Text(switch (services.api.baseUrl) {
                          null => l10n.none,
                          '' => Uri.base.origin,
                          final String url => url,
                        }),
                      ),
                  ],
                ),
                _SectionTitle(l10n.settingsAbout),
                const _SectionCard(
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: GoogleMapsTermsNotice(),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: () {
                    // ログインの画面はアプリの最初の画面に表示されるため、設定の画面を閉じてからログアウトする
                    Navigator.of(
                      context,
                    ).popUntil((Route<void> r) => r.isFirst);
                    services.account.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.logout),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withValues(alpha: 0.5),
                    ),
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

/// 設定のまとまりの見出し
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 設定のまとまりを1枚のカードにする
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// ログインしているアカウントのニックネームとアイコン。押すと変更の画面を開く
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.account});

  final AccountController account;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: account,
      builder: (BuildContext context, Widget? _) {
        final AccountState state = account.state;
        if (state is! AccountReady) {
          return const SizedBox.shrink();
        }
        final String? email = state.user.email;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: ProfileAvatar(
              icon: ProfileIcon.of(state.profile.icon),
              size: 56,
            ),
            title: Text(
              state.profile.nickname,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: email == null
                ? null
                : Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => ProfileFormScreen(
                  initial: state.profile,
                  submitLabel: l10n.save,
                  onSubmit: (Profile profile) async {
                    await account.saveProfile(profile);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// キーカラーの候補を丸い見本で並べる。選択中の見本に印を付ける
class _KeyColorPicker extends StatelessWidget {
  const _KeyColorPicker({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final KeyColorChoice choice = settings.keyColor;
    final Color? wallpaper = settings.wallpaperColor;
    final CustomKeyColor? custom = switch (choice) {
      CustomKeyColor() => choice,
      AppKeyColor() || WallpaperKeyColor() => null,
    };
    final bool customIsPreset =
        custom != null &&
        AppSettings.presets.any(
          (Color c) => c.toARGB32() == custom.color.toARGB32(),
        );

    return Wrap(
      spacing: 12,
      runSpacing: 16,
      children: <Widget>[
        if (wallpaper != null)
          _Swatch(
            label: l10n.colorWallpaper,
            color: wallpaper,
            icon: Icons.wallpaper,
            selected: choice is WallpaperKeyColor,
            onTap: () => settings.keyColor = const WallpaperKeyColor(),
          ),
        _Swatch(
          label: l10n.appTitle,
          color: AppTheme.keyColor,
          selected:
              choice is AppKeyColor ||
              (choice is WallpaperKeyColor && wallpaper == null),
          onTap: () => settings.keyColor = const AppKeyColor(),
        ),
        for (final Color color in AppSettings.presets)
          _Swatch(
            color: color,
            selected: custom?.color.toARGB32() == color.toARGB32(),
            onTap: () => settings.keyColor = CustomKeyColor(color),
          ),
        _Swatch(
          label: l10n.colorOther,
          color: custom != null && !customIsPreset ? custom.color : null,
          icon: Icons.colorize,
          selected: custom != null && !customIsPreset,
          onTap: () async {
            final Color? picked = await showColorPickerSheet(
              context,
              initial: settings.resolveKeyColor(),
            );
            if (picked != null) {
              settings.keyColor = CustomKeyColor(picked);
            }
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  });

  /// null のときは色相の環で表示する（まだ色を選んでいない「ほかの色」）
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final IconData? icon;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color? color = this.color;
    final String? label = this.label;
    final IconData? icon = this.icon;
    final Color onColor = color != null && color.computeLuminance() > 0.45
        ? const Color(0xFF1A1A22)
        : const Color(0xFFFFFFFF);

    return Semantics(
      button: true,
      selected: selected,
      label: label ?? _hex(color),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 56,
          child: Column(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: _size + 8,
                height: _size + 8,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.onSurface
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    gradient: color == null ? _hueRing : null,
                  ),
                  child: Center(
                    child: selected
                        ? Icon(Icons.check, color: onColor, size: 22)
                        : (icon == null
                              ? null
                              : Icon(icon, color: onColor, size: 20)),
                  ),
                ),
              ),
              if (label != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _hex(Color? c) => c == null
      ? ''
      : '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static const SweepGradient _hueRing = SweepGradient(
    colors: <Color>[
      Color(0xFFFF0000),
      Color(0xFFFFFF00),
      Color(0xFF00FF00),
      Color(0xFF00FFFF),
      Color(0xFF0000FF),
      Color(0xFFFF00FF),
      Color(0xFFFF0000),
    ],
  );
}

/// 色相と明るさの2本のスライダーで色を選ぶシート。選んだ色を返し、閉じたときは null を返す
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
}) => showModalBottomSheet<Color>(
  context: context,
  showDragHandle: true,
  builder: (BuildContext context) => _ColorPickerSheet(initial: initial),
);

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  /// 鮮やかさは、キーカラーとして使いやすい値に固定する
  static const double _saturation = 0.72;

  late double _hue = HSVColor.fromColor(widget.initial).hue;
  late double _value = HSVColor.fromColor(
    widget.initial,
  ).value.clamp(0.35, 0.95).toDouble();

  Color get _color => HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _GradientSlider(
              label: l10n.hue,
              value: _hue,
              max: 360,
              colors: <Color>[
                for (int h = 0; h <= 360; h += 60)
                  HSVColor.fromAHSV(
                    1,
                    h.toDouble(),
                    _saturation,
                    _value,
                  ).toColor(),
              ],
              onChanged: (double v) => setState(() => _hue = v),
            ),
            _GradientSlider(
              label: l10n.brightness,
              value: _value,
              min: 0.35,
              max: 0.95,
              colors: <Color>[
                HSVColor.fromAHSV(1, _hue, _saturation, 0.35).toColor(),
                HSVColor.fromAHSV(1, _hue, _saturation, 0.95).toColor(),
              ],
              onChanged: (double v) => setState(() => _value = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
              ),
              onPressed: () => Navigator.of(context).pop(_color),
              child: Text(l10n.useThisColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 地に色の変化を描いたスライダー
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.colors,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.white,
                overlayColor: Colors.black12,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
