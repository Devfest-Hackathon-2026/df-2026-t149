import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uramichi/core/models/achievement_stats.dart';
import 'package:uramichi/core/models/memory_log.dart';
import 'package:uramichi/core/theme.dart';
import 'package:uramichi/features/achievements/achievement_widgets.dart';
import 'package:uramichi/features/achievements/achievements.dart';
import 'package:uramichi/features/achievements/achievements_screen.dart';

MemoryLog _log(
  String placeId,
  DateTime at, {
  int? order,
  int? rating,
  String comment = '',
}) => MemoryLog(
  id: '$placeId-${at.toIso8601String()}',
  placeId: placeId,
  placeName: '場所$placeId',
  verdict: rating == null ? Verdict.hit : Verdict.fromStars(rating),
  createdAt: at,
  order: order,
  rating: rating,
  comment: comment,
);

Map<String, AchievementProgress> _byId(List<MemoryLog> logs) =>
    <String, AchievementProgress>{
      for (final AchievementProgress a in computeAchievements(logs))
        a.definition.id: a,
    };

void main() {
  test('実績の id は重ならない', () {
    final Set<String> ids = <String>{
      for (final AchievementDefinition d in achievementDefinitions) d.id,
    };
    expect(ids, hasLength(achievementDefinitions.length));
  });

  test('シークレット実績にはヒントがあり、解除するまで隠す', () {
    final List<AchievementDefinition> secrets = <AchievementDefinition>[
      for (final AchievementDefinition d in achievementDefinitions)
        if (d.secret) d,
    ];
    expect(secrets.length, greaterThanOrEqualTo(5));
    for (final AchievementDefinition d in secrets) {
      expect(d.hint, isNotEmpty, reason: d.id);
    }
    final AchievementProgress runnerUp = _byId(<MemoryLog>[])['runner_up']!;
    expect(runnerUp.hidden, isTrue);

    final AchievementProgress got = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 8, 12), order: 2),
    ])['runner_up']!;
    expect(got.unlocked, isTrue);
    expect(got.hidden, isFalse);
    expect(got.unlockedBy?.placeId, 'a');
  });

  test('★評価で数える実績', () {
    final Map<String, AchievementProgress> got = _byId(<MemoryLog>[
      for (int i = 0; i < 3; i++)
        _log('p$i', DateTime(2026, 11, 8, 12, i), rating: 5),
      _log('x', DateTime(2026, 11, 8, 13), rating: 1),
    ]);
    expect(got['full_marks']!.unlocked, isTrue);
    expect(got['honor_miss']!.unlocked, isTrue);
    expect(got['honor_miss']!.unlocked, isTrue);
    expect(got['connoisseur']!.progress, 3);
  });

  test('日付ごとに1回だけ数える実績と、同じ場所で数える実績', () {
    final Map<String, AchievementProgress> got = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 1, 12)),
      _log('a', DateTime(2026, 11, 1, 15)),
      _log('a', DateTime(2026, 11, 2, 12)),
      _log('b', DateTime(2026, 11, 3, 12)),
    ]);
    expect(got['three_days']!.unlocked, isTrue);
    expect(got['three_days']!.unlockedAt, DateTime(2026, 11, 3, 12));
    expect(got['regular_spot']!.unlocked, isTrue);
    expect(got['regular_spot']!.unlockedAt, DateTime(2026, 11, 2, 12));
  });

  test('はしご旅は、1日に別の場所を3か所記録すると解除する', () {
    final Map<String, AchievementProgress> notYet = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 1, 10)),
      _log('a', DateTime(2026, 11, 1, 11)), // 同じ場所は数えない
      _log('b', DateTime(2026, 11, 1, 12)),
      _log('c', DateTime(2026, 11, 2, 12)), // 別の日
    ]);
    expect(notYet['hashigo']!.unlocked, isFalse);
    expect(notYet['hashigo']!.progress, 2);

    final AchievementProgress got = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 1, 10)),
      _log('b', DateTime(2026, 11, 1, 12)),
      _log('c', DateTime(2026, 11, 1, 15)),
    ])['hashigo']!;
    expect(got.unlocked, isTrue);
    expect(got.unlockedAt, DateTime(2026, 11, 1, 15));
  });

  test('★1を付けることを勧める実績はない', () {
    for (final AchievementDefinition d in achievementDefinitions) {
      expect(d.id, isNot('harsh_critic'));
    }
  });

  test('キリ番と時刻の実績', () {
    final Map<String, AchievementProgress> got = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 8, 2), order: 20),
      _log('b', DateTime(2026, 11, 8, 6), order: 11),
    ]);
    expect(got['kiriban']!.unlocked, isTrue);
    expect(got['night_owl']!.unlocked, isTrue);
    expect(got['early_bird']!.unlocked, isTrue);
  });

  test('新しく解除した実績だけを返す', () {
    final List<MemoryLog> before = <MemoryLog>[
      _log('a', DateTime(2026, 11, 8, 12), order: 5),
    ];
    final List<MemoryLog> after = <MemoryLog>[
      ...before,
      _log('b', DateTime(2026, 11, 8, 13), order: 1, rating: 2),
    ];
    final List<String> ids = <String>[
      for (final AchievementProgress a in newlyUnlocked(before, after))
        a.definition.id,
    ];
    expect(ids, containsAll(<String>['pioneer', 'honor_miss']));
    expect(ids, isNot(contains('first_log')));
  });

  testWidgets('解除の画面はメダルを見せ、閉じられる', (WidgetTester tester) async {
    final AchievementProgress a = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 8, 12), order: 1),
    ])['pioneer']!;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () =>
                showUnlockedAchievements(context, <AchievementProgress>[a]),
            child: const Text('開く'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pump();
    expect(find.text('実績を解除！'), findsOneWidget);
    expect(find.text('開拓者'), findsOneWidget);
    expect(find.byType(MedalReveal), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('やったね'));
    await tester.pumpAndSettle();
    expect(find.byType(AchievementUnlockedDialog), findsNothing);
  });

  test('段階のある実績は、ブロンズ・シルバー・ゴールドの順に上がる', () {
    List<MemoryLog> places(int n) => <MemoryLog>[
      for (int i = 0; i < n; i++)
        _log('p$i', DateTime(2026, 11, 1).add(Duration(hours: i))),
    ];
    AchievementProgress wanderer(int n) => _byId(places(n))['wanderer']!;

    expect(wanderer(4).tier, 0);
    expect(wanderer(4).nextGoal, 5);
    expect(wanderer(4).currentDescription, contains('5か所'));
    expect(wanderer(5).tierLevel, AchievementTier.bronze);
    expect(wanderer(5).nextGoal, 20);
    expect(wanderer(5).currentDescription, contains('20か所'));
    expect(wanderer(20).tierLevel, AchievementTier.silver);
    final AchievementProgress gold = wanderer(60);
    expect(gold.tierLevel, AchievementTier.gold);
    expect(gold.completed, isTrue);
    expect(gold.nextGoal, isNull);
    expect(gold.progress, 50);
    // はじめて解除した日時と、今の段階に達した日時
    expect(gold.unlockedAt, DateTime(2026, 11, 1, 4));
    expect(
      gold.tierReachedAt,
      DateTime(2026, 11, 1).add(const Duration(hours: 49)),
    );
  });

  test('段階が上がったら、昇格として返す', () {
    final List<MemoryLog> before = <MemoryLog>[
      for (int i = 0; i < 19; i++)
        _log('p$i', DateTime(2026, 11, 1).add(Duration(hours: i))),
    ];
    final List<MemoryLog> after = <MemoryLog>[
      ...before,
      _log('p19', DateTime(2026, 11, 2, 12)),
    ];
    final AchievementProgress up = newlyUnlocked(
      before,
      after,
    ).firstWhere((AchievementProgress a) => a.definition.id == 'wanderer');
    expect(up.previousTier, 1);
    expect(up.promoted, isTrue);
    expect(unlockHeadline(up), 'シルバーに昇格！');

    final AchievementProgress first = newlyUnlocked(
      const <MemoryLog>[],
      <MemoryLog>[_log('a', DateTime(2026, 11, 1), order: 1)],
    ).firstWhere((AchievementProgress a) => a.definition.id == 'pioneer');
    expect(first.promoted, isFalse);
    expect(unlockHeadline(first), 'ブロンズを獲得！');
  });

  test('実績の色はテーマと別の決まった色で、段階ごとに違う', () {
    final Set<Color> tiers = <Color>{
      for (final (Color _, Color dark) in AppTheme.tierColors) dark,
    };
    expect(tiers, hasLength(3));
    expect(tiers, isNot(contains(AppTheme.keyColor)));
    expect(AppTheme.rarityColors.toSet(), hasLength(4));
  });

  test('利用者全体の集計から、段階ごとに解除した人の割合を出す', () {
    final AchievementStats stats = AchievementStats.fromJson(<String, dynamic>{
      'users': 200,
      'achievements': <String, dynamic>{
        'wanderer': <int>[50, 10, 1],
      },
    });
    expect(stats.rate('wanderer', 1), 0.25);
    expect(AchievementStats.percent(stats.rate('wanderer', 2)!), '5%');
    expect(AchievementStats.percent(stats.rate('wanderer', 3)!), '1%未満');
    expect(stats.rate('pioneer', 1), 0);
    expect(
      const AchievementStats(
        users: 0,
        counts: <String, List<int>>{},
      ).rate('wanderer', 1),
      isNull,
    );

    final AchievementProgress silver = _byId(<MemoryLog>[
      for (int i = 0; i < 20; i++)
        _log('p$i', DateTime(2026, 11, 1).add(Duration(hours: i))),
    ])['wanderer']!;
    expect(unlockRateLabel(stats, silver), 'シルバーは全体の 5%');
    expect(unlockedTiers(<AchievementProgress>[silver]), <String, int>{
      'wanderer': 2,
    });
  });

  testWidgets('実績の詳細に、段階ごとの全体の割合を出す', (WidgetTester tester) async {
    final AchievementProgress a = _byId(<MemoryLog>[
      _log('a', DateTime(2026, 11, 8, 12)),
    ])['wanderer']!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AchievementDetailSheet(
            achievement: a,
            stats: const AchievementStats(
              users: 10,
              counts: <String, List<int>>{
                'wanderer': <int>[5, 2, 0],
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('全体の 50%'), findsOneWidget);
    expect(find.text('全体の 20%'), findsOneWidget);
    expect(find.text('全体の 0%'), findsOneWidget);
  });

  group('もう少しで解除', () {
    test('進んでいる実績を、次の段階に近い順に出し、隠れた実績と進んでいない実績は出さない', () {
      final DateTime day = DateTime(2026, 11, 2, 12);
      // 4か所を記録：ウラミチ散歩は 4/5、古参の風格（10人目まで）は 2/3
      final List<MemoryLog> logs = <MemoryLog>[
        for (int i = 0; i < 4; i++)
          _log('p$i', day.add(Duration(days: i)), order: i < 2 ? 5 : 50),
      ];
      final List<AchievementProgress> almost = almostThere(
        computeAchievements(logs),
      );
      final List<String> ids = <String>[
        for (final AchievementProgress a in almost) a.definition.id,
      ];
      expect(ids, contains('wanderer'));
      final List<double> ratios = <double>[
        for (final AchievementProgress a in almost) a.progress / a.nextGoal!,
      ];
      for (int i = 1; i < ratios.length; i++) {
        expect(ratios[i], lessThanOrEqualTo(ratios[i - 1]));
      }
      expect(almost.length, lessThanOrEqualTo(3));
      for (final AchievementProgress a in almost) {
        expect(a.hidden, isFalse);
        expect(a.progress, greaterThan(0));
        expect(a.progress, lessThan(a.nextGoal!));
      }
    });

    test('記録がなければ出さない', () {
      expect(almostThere(computeAchievements(<MemoryLog>[])), isEmpty);
    });
  });

  test('絞り込みで、解除済みと未解除を分ける', () {
    final List<AchievementProgress> list = computeAchievements(<MemoryLog>[
      _log('a', DateTime(2026, 11, 2, 12), order: 1),
    ]);
    final List<AchievementProgress> on = <AchievementProgress>[
      for (final AchievementProgress a in list)
        if (AchievementFilter.unlocked.matches(a)) a,
    ];
    final List<AchievementProgress> off = <AchievementProgress>[
      for (final AchievementProgress a in list)
        if (AchievementFilter.locked.matches(a)) a,
    ];
    expect(on, isNotEmpty);
    expect(on.every((AchievementProgress a) => a.unlocked), isTrue);
    expect(off.every((AchievementProgress a) => !a.unlocked), isTrue);
    expect(on.length + off.length, list.length);
  });
}
