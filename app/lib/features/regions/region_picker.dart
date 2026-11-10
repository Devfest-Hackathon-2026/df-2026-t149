import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/haptics.dart';
import 'regions.dart';
import '../../core/strings.dart';

/// 遠くの地域を選んだ結果。[region] か [query]（地名）のどちらか
class RegionChoice {
  const RegionChoice.region(Region this.region) : query = null;
  const RegionChoice.query(String this.query) : region = null;

  final Region? region;
  final String? query;
}

/// 遠くの地域を選ぶシートを開く。閉じたら null
Future<RegionChoice?> showRegionPicker(BuildContext context) =>
    showModalBottomSheet<RegionChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext context) => const RegionPickerSheet(),
    );

class RegionPickerSheet extends StatefulWidget {
  const RegionPickerSheet({super.key});

  @override
  State<RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<RegionPickerSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(Region r) {
    Haptics.tap();
    Navigator.of(context).pop(RegionChoice.region(r));
  }

  void _submit() {
    final String q = _query.text.trim();
    if (q.isNotEmpty) {
      Navigator.of(context).pop(RegionChoice.query(q));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Map<RegionArea, List<Region>> byArea = hiddenRegionsByArea();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: <Widget>[
          Text(l10n.exploreFar, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.explore_outlined, color: scheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.regionPickerLead,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (String _) => _submit(),
            decoration: InputDecoration(
              hintText: l10n.regionSearchHint,
              prefixIcon: const Icon(Icons.travel_explore),
              suffixIcon: IconButton(
                tooltip: l10n.regionSearch,
                icon: const Icon(Icons.arrow_forward),
                onPressed: _submit,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(l10n.regionPairsHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final RegionPair pair in regionPairs) ...<Widget>[
            _PairCard(pair: pair, onPick: _pick),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Text(l10n.regionAreasHeading, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final MapEntry<RegionArea, List<Region>> e in byArea.entries)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(e.key.label),
              children: <Widget>[
                for (final Region r in e.value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(r.label),
                    subtitle: Text(r.reason),
                    onTap: () => _pick(r),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.pair, required this.onPick});

  final RegionPair pair;
  final ValueChanged<Region> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Region famous = regionById(pair.famous);
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.regionPairLabel(famous.name),
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final String id in pair.instead)
              _AlternativeRow(region: regionById(id), onPick: onPick),
          ],
        ),
      ),
    );
  }
}

class _AlternativeRow extends StatelessWidget {
  const _AlternativeRow({required this.region, required this.onPick});

  final Region region;
  final ValueChanged<Region> onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      onTap: () => onPick(region),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.near_me_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(region.label, style: theme.textTheme.titleSmall),
                  Text(region.reason, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
