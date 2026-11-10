/// 遠くの地域を調べるときの地域の一覧。
///
/// Places API を呼ばずに選べるよう、アプリに持つ。位置は市町村の中心のおおよその値で、
/// 選ぶと地図をそこへ動かし、広い範囲（[Region.radiusMeters]）で穴場を探す。
/// 「定番の地域」には、次の旅に勧める「まだ知られていない地域」を [RegionPair] で結び付ける。
/// どの地域も紹介する相手なので、比べて下げる言い方（〇〇より、〇〇は混む など）は使わない
class Region {
  const Region({
    required this.id,
    required this.name,
    required this.prefecture,
    required this.area,
    required this.lat,
    required this.lng,
    required this.reason,
    this.famous = false,
    this.radiusMeters = 20000,
  });

  final String id;

  /// 地域の呼び名（例：松本・安曇野）
  final String name;
  final String prefecture;
  final RegionArea area;
  final double lat;
  final double lng;

  /// 地域の紹介（一覧に出す短い文）。ほかの地域と比べたり、下げたりする言い方はしない
  final String reason;

  /// 人が集まる定番の地域か
  final bool famous;

  /// 選んだときに探す半径（m）
  final int radiusMeters;

  String get label => '$prefecture・$name';
}

/// 地方。一覧をまとめる単位
enum RegionArea {
  hokkaidoTohoku('北海道・東北'),
  kanto('関東'),
  chubu('中部'),
  kinki('近畿'),
  chugokuShikoku('中国・四国'),
  kyushuOkinawa('九州・沖縄');

  const RegionArea(this.label);
  final String label;
}

/// 定番の地域と、そこに行ったことがある人に次に勧める地域
class RegionPair {
  const RegionPair({required this.famous, required this.instead});

  final String famous;
  final List<String> instead;
}

const List<Region> regions = <Region>[
  // 定番の地域
  Region(
    id: 'tokyo',
    name: '東京',
    prefecture: '東京都',
    area: RegionArea.kanto,
    lat: 35.681,
    lng: 139.767,
    reason: '見どころの多い首都',
    famous: true,
  ),
  Region(
    id: 'osaka',
    name: '大阪',
    prefecture: '大阪府',
    area: RegionArea.kinki,
    lat: 34.702,
    lng: 135.496,
    reason: '食べ歩きの町',
    famous: true,
  ),
  Region(
    id: 'kyoto',
    name: '京都',
    prefecture: '京都府',
    area: RegionArea.kinki,
    lat: 35.011,
    lng: 135.768,
    reason: '寺社と町家の古都',
    famous: true,
  ),
  Region(
    id: 'sapporo',
    name: '札幌',
    prefecture: '北海道',
    area: RegionArea.hokkaidoTohoku,
    lat: 43.062,
    lng: 141.354,
    reason: '北海道の玄関口',
    famous: true,
  ),
  Region(
    id: 'fukuoka',
    name: '福岡',
    prefecture: '福岡県',
    area: RegionArea.kyushuOkinawa,
    lat: 33.590,
    lng: 130.402,
    reason: '屋台とグルメの町',
    famous: true,
  ),
  Region(
    id: 'naha',
    name: '那覇',
    prefecture: '沖縄県',
    area: RegionArea.kyushuOkinawa,
    lat: 26.212,
    lng: 127.681,
    reason: '南国の島の玄関口',
    famous: true,
  ),
  Region(
    id: 'kanazawa',
    name: '金沢',
    prefecture: '石川県',
    area: RegionArea.chubu,
    lat: 36.578,
    lng: 136.648,
    reason: '北陸の城下町',
    famous: true,
  ),
  Region(
    id: 'hiroshima',
    name: '広島',
    prefecture: '広島県',
    area: RegionArea.chugokuShikoku,
    lat: 34.397,
    lng: 132.475,
    reason: '宮島と瀬戸内の町',
    famous: true,
  ),
  // 穴場の地域
  Region(
    id: 'matsumoto',
    name: '松本・安曇野',
    prefecture: '長野県',
    area: RegionArea.chubu,
    lat: 36.238,
    lng: 137.972,
    reason: '北アルプスを望む城下町。湧き水の町をのんびり歩ける',
  ),
  Region(
    id: 'sado',
    name: '佐渡',
    prefecture: '新潟県',
    area: RegionArea.chubu,
    lat: 38.020,
    lng: 138.370,
    reason: '金山の歴史と棚田と海。島をゆっくりめぐる旅',
  ),
  Region(
    id: 'joetsu',
    name: '上越・高田',
    prefecture: '新潟県',
    area: RegionArea.chubu,
    lat: 37.148,
    lng: 138.236,
    reason: '雁木の町並みと日本海の幸。酒蔵めぐりも',
  ),
  Region(
    id: 'hokuto',
    name: '北杜',
    prefecture: '山梨県',
    area: RegionArea.chubu,
    lat: 35.776,
    lng: 138.424,
    reason: '八ヶ岳のふもとの高原。東京から行きやすい',
  ),
  Region(
    id: 'kasama',
    name: '笠間',
    prefecture: '茨城県',
    area: RegionArea.kanto,
    lat: 36.385,
    lng: 140.247,
    reason: '焼き物の町。工房と栗のお菓子をめぐる',
  ),
  Region(
    id: 'kumano',
    name: '熊野本宮',
    prefecture: '和歌山県',
    area: RegionArea.kinki,
    lat: 33.840,
    lng: 135.770,
    reason: '古道と温泉の山あい。大阪から足をのばせる',
  ),
  Region(
    id: 'omihachiman',
    name: '近江八幡',
    prefecture: '滋賀県',
    area: RegionArea.kinki,
    lat: 35.128,
    lng: 136.098,
    reason: '水郷と商人の町並み。京都から電車で行ける',
  ),
  Region(
    id: 'iga',
    name: '伊賀',
    prefecture: '三重県',
    area: RegionArea.kinki,
    lat: 34.768,
    lng: 136.130,
    reason: '忍者と城下町。大阪・奈良から行きやすい',
  ),
  Region(
    id: 'mikuni',
    name: '越前・三国',
    prefecture: '福井県',
    area: RegionArea.chubu,
    lat: 36.220,
    lng: 136.150,
    reason: '港町の古い町並みと海の景色',
  ),
  Region(
    id: 'sasayama',
    name: '丹波篠山',
    prefecture: '兵庫県',
    area: RegionArea.kinki,
    lat: 35.075,
    lng: 135.218,
    reason: '城下町と黒豆。京都・大阪から日帰りで行ける',
  ),
  Region(
    id: 'obihiro',
    name: '帯広・十勝',
    prefecture: '北海道',
    area: RegionArea.hokkaidoTohoku,
    lat: 42.923,
    lng: 143.196,
    reason: '広い空と畑。スイーツと温泉の町',
  ),
  Region(
    id: 'kushiro',
    name: '釧路',
    prefecture: '北海道',
    area: RegionArea.hokkaidoTohoku,
    lat: 42.985,
    lng: 144.381,
    reason: '湿原と霧の港町。道東の旅の入り口',
  ),
  Region(
    id: 'tono',
    name: '遠野',
    prefecture: '岩手県',
    area: RegionArea.hokkaidoTohoku,
    lat: 39.328,
    lng: 141.533,
    reason: '民話のふるさと。里山の風景が残る',
  ),
  Region(
    id: 'hirosaki',
    name: '弘前',
    prefecture: '青森県',
    area: RegionArea.hokkaidoTohoku,
    lat: 40.603,
    lng: 140.464,
    reason: '城とりんごと洋館の町',
  ),
  Region(
    id: 'takaoka',
    name: '高岡・氷見',
    prefecture: '富山県',
    area: RegionArea.chubu,
    lat: 36.800,
    lng: 137.000,
    reason: '鋳物の町と、海越しの立山連峰',
  ),
  Region(
    id: 'gujo',
    name: '郡上八幡',
    prefecture: '岐阜県',
    area: RegionArea.chubu,
    lat: 35.749,
    lng: 136.962,
    reason: '水の流れる城下町。名古屋から足をのばせる',
  ),
  Region(
    id: 'tsuwano',
    name: '津和野',
    prefecture: '島根県',
    area: RegionArea.chugokuShikoku,
    lat: 34.467,
    lng: 131.772,
    reason: '山あいの小京都。白壁と鯉の泳ぐ水路',
  ),
  Region(
    id: 'uchiko',
    name: '内子',
    prefecture: '愛媛県',
    area: RegionArea.chugokuShikoku,
    lat: 33.533,
    lng: 132.658,
    reason: '木蝋で栄えた町並みと芝居小屋',
  ),
  Region(
    id: 'iya',
    name: '祖谷',
    prefecture: '徳島県',
    area: RegionArea.chugokuShikoku,
    lat: 33.880,
    lng: 133.840,
    reason: '深い谷とかずら橋。秘境の山里',
  ),
  Region(
    id: 'shimanto',
    name: '四万十',
    prefecture: '高知県',
    area: RegionArea.chugokuShikoku,
    lat: 32.990,
    lng: 132.930,
    reason: '清流と沈下橋。川沿いでのんびり',
  ),
  Region(
    id: 'karatsu',
    name: '唐津',
    prefecture: '佐賀県',
    area: RegionArea.kyushuOkinawa,
    lat: 33.450,
    lng: 129.968,
    reason: '城と松原と焼き物。福岡から電車ですぐ',
  ),
  Region(
    id: 'taketa',
    name: '竹田',
    prefecture: '大分県',
    area: RegionArea.kyushuOkinawa,
    lat: 32.974,
    lng: 131.396,
    reason: '石垣の城跡と湧き水、静かな温泉',
  ),
  Region(
    id: 'goto',
    name: '五島',
    prefecture: '長崎県',
    area: RegionArea.kyushuOkinawa,
    lat: 32.696,
    lng: 128.840,
    reason: '教会と透きとおる海の島々',
  ),
  Region(
    id: 'amami',
    name: '奄美大島',
    prefecture: '鹿児島県',
    area: RegionArea.kyushuOkinawa,
    lat: 28.377,
    lng: 129.494,
    reason: 'マングローブと森と海の島',
  ),
];

/// 定番の地域と、そこに行ったことがある人に次に勧める地域
const List<RegionPair> regionPairs = <RegionPair>[
  RegionPair(
    famous: 'tokyo',
    instead: <String>['matsumoto', 'sado', 'hokuto', 'kasama'],
  ),
  RegionPair(famous: 'osaka', instead: <String>['kumano', 'iga', 'sasayama']),
  RegionPair(
    famous: 'kyoto',
    instead: <String>['omihachiman', 'mikuni', 'sasayama'],
  ),
  RegionPair(famous: 'sapporo', instead: <String>['obihiro', 'kushiro']),
  RegionPair(famous: 'fukuoka', instead: <String>['karatsu', 'taketa', 'goto']),
  RegionPair(famous: 'naha', instead: <String>['amami', 'goto']),
  RegionPair(famous: 'kanazawa', instead: <String>['takaoka', 'mikuni']),
  RegionPair(famous: 'hiroshima', instead: <String>['tsuwano', 'uchiko']),
];

Region regionById(String id) => regions.firstWhere((Region r) => r.id == id);

/// 穴場の地域（定番ではない地域）を地方ごとに返す
Map<RegionArea, List<Region>> hiddenRegionsByArea() =>
    <RegionArea, List<Region>>{
      for (final RegionArea a in RegionArea.values)
        a: <Region>[
          for (final Region r in regions)
            if (!r.famous && r.area == a) r,
        ],
    }..removeWhere((RegionArea _, List<Region> v) => v.isEmpty);
