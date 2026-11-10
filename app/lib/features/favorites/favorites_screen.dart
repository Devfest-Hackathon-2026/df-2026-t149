import '../../core/widgets/google_maps_notice.dart';
import 'package:flutter/material.dart';

import '../../core/data/favorites.dart';
import '../../core/models/place.dart';
import '../../core/services.dart';
import '../../core/widgets/place_card.dart';
import '../../core/widgets/state_view.dart';
import '../place/place_detail_screen.dart';
import '../../core/strings.dart';

/// お気に入りの場所の画面（地図の「お気に入り」から開く）
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(l10n.favorites)),
    body: const FavoritesList(),
  );
}

/// お気に入りの場所の一覧。押すと場所の詳細を開く。タイムラインの「お気に入り」でも使う
class FavoritesList extends StatefulWidget {
  const FavoritesList({super.key, this.bottomPadding = 32});

  /// 一覧の下に空ける幅（下のタブと重ならないように）
  final double bottomPadding;

  @override
  State<FavoritesList> createState() => _FavoritesListState();
}

class _FavoritesListState extends State<FavoritesList> {
  Future<List<FavoriteEntry>>? _entries;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries ??= _load();
  }

  Future<List<FavoriteEntry>> _load() =>
      Services.of(context).favorites?.list() ??
      Future<List<FavoriteEntry>>.value(const <FavoriteEntry>[]);

  void _reload() => setState(() => _entries = _load());

  void _open(Place place) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext _) =>
          PlaceDetailScreen(place: place, isMock: place.isMock),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final FavoritesController? favorites = Services.of(context).favorites;
    return FutureBuilder<List<FavoriteEntry>>(
      future: _entries,
      builder: (BuildContext context, AsyncSnapshot<List<FavoriteEntry>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return StateView(
            icon: Icons.cloud_off_outlined,
            title: describeError(snap.error!),
            primary: StateViewAction(l10n.retry, _reload, icon: Icons.refresh),
          );
        }
        final List<FavoriteEntry> entries = snap.data!;
        return ListenableBuilder(
          listenable: favorites ?? ChangeNotifier(),
          builder: (BuildContext context, Widget? _) {
            // 外した場所は、一覧を読み直さずにすぐ消す
            final List<FavoriteEntry> shown = <FavoriteEntry>[
              for (final FavoriteEntry e in entries)
                if (favorites?.isFavorite(e.placeId) ?? true) e,
            ];
            // 読み込んだ件数ではなく表示する件数で決め、最後の1件を外したときも案内を出す
            if (shown.isEmpty) {
              return StateView(
                icon: Icons.favorite_border,
                title: l10n.noFavoritesYet,
                message: l10n.noFavoritesMessage,
              );
            }
            return ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, widget.bottomPadding),
              children: <Widget>[
                PlaceList(
                  rows: <Widget>[
                    for (final FavoriteEntry e in shown)
                      if (e.place case final Place place)
                        PlaceRow(place: place, onTap: () => _open(place))
                      else
                        ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: Text(l10n.placeNameLoadFailed),
                          subtitle: Text(l10n.placeMaybeClosed),
                        ),
                  ],
                ),
                const GoogleMapsAttribution(),
              ],
            );
          },
        );
      },
    );
  }
}
