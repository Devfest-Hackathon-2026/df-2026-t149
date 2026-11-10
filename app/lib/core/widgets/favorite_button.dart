import 'package:flutter/material.dart';

import '../data/favorites.dart';
import '../haptics.dart';
import '../sounds.dart';
import '../models/place.dart';
import '../services.dart';
import '../strings.dart';

/// お気に入りに入れる・外すボタン。
///
/// ★は場所の★評価で使っているため、Material の標準の「お気に入り」のハートで表す。
/// [Services.favorites] がないときは何も表示しない
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({super.key, required this.place, this.compact = false});

  final Place place;

  /// 一覧の行の中で使う小さな表示
  final bool compact;

  Future<void> _toggle(
    BuildContext context,
    FavoritesController favorites,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool adding = !favorites.isFavorite(place.id);
    if (adding) {
      Haptics.success();
      Sounds.favorite();
    } else {
      Haptics.select();
    }
    try {
      await favorites.toggle(place);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              !adding
                  ? l10n.favoriteRemoved
                  : place.name.isEmpty
                  ? l10n.favoriteAdded
                  : l10n.favoriteAddedNamed(place.name),
            ),
          ),
        );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final FavoritesController? favorites = Services.maybeOf(context)?.favorites;
    if (favorites == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: favorites,
      builder: (BuildContext context, Widget? _) {
        final bool on = favorites.isFavorite(place.id);
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return IconButton(
          tooltip: on ? l10n.favoriteRemoveTooltip : l10n.favoriteAddTooltip,
          isSelected: on,
          visualDensity: compact ? VisualDensity.compact : null,
          onPressed: favorites.isChanging(place.id)
              ? null
              : () => _toggle(context, favorites),
          icon: Icon(Icons.favorite_border, color: scheme.onSurfaceVariant),
          selectedIcon: Icon(Icons.favorite, color: scheme.error),
        );
      },
    );
  }
}
