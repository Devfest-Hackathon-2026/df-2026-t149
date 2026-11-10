import 'package:flutter/material.dart';
import '../strings.dart';

/// 件数を3桁ごとにカンマで区切る（例：15,400）
String formatCount(int count) {
  final String digits = count.abs().toString();
  final StringBuffer buffer = StringBuffer(count < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 地図のピンのように狭い場所に書く件数。1,000件以上は k を付けて短くする（例：1.5k、15k）
String formatCompactCount(int count) {
  if (count < 1000) {
    return count.toString();
  }
  if (count < 10000) {
    final String k = (count / 1000).toStringAsFixed(1);
    return '${k.endsWith('.0') ? k.substring(0, k.length - 2) : k}k';
  }
  return '${count ~/ 1000}k';
}

/// 距離を 1km 未満は m、1km 以上は km で表す。km は小数1桁までで、末尾の .0 は付けない
String formatDistance(int meters) {
  if (meters < 1000) {
    return '$meters m';
  }
  final String km = (meters / 1000).toStringAsFixed(1);
  return '${km.endsWith('.0') ? km.substring(0, km.length - 2) : km} km';
}

/// Places API (New) の種類を日本語で表す。表にない種類は null を返し、画面では種類を表示しない
String? placeTypeLabel(String? primaryType) => _typeLabels[primaryType];

final Map<String, String> _typeLabels = {
  'art_gallery': l10n.placeTypeArtGallery,
  'buddhist_temple': l10n.placeTypeBuddhistTemple,
  'cafe': l10n.placeTypeCafe,
  'coffee_shop': l10n.placeTypeCoffeeShop,
  'cultural_center': l10n.placeTypeCulturalCenter,
  'garden': l10n.placeTypeGarden,
  'hiking_area': l10n.placeTypeHikingArea,
  'market': l10n.placeTypeMarket,
  'museum': l10n.placeTypeMuseum,
  'observation_deck': l10n.placeTypeObservationDeck,
  'park': l10n.placeTypePark,
  'restaurant': l10n.placeTypeRestaurant,
  'shinto_shrine': l10n.placeTypeShrine,
  'shopping_mall': l10n.placeTypeShoppingMall,
  'store': l10n.placeTypeStore,
  'tea_house': l10n.placeTypeTeaHouse,
  'tourist_attraction': l10n.placeTypeTouristAttraction,
};

/// 場所の種類を表すアイコン。表にない種類は一般的な場所のアイコンにする
IconData placeTypeIcon(String? primaryType) =>
    _typeIcons[primaryType] ?? Icons.place_outlined;

const Map<String, IconData> _typeIcons = <String, IconData>{
  'art_gallery': Icons.palette_outlined,
  'buddhist_temple': Icons.temple_buddhist_outlined,
  'cafe': Icons.local_cafe_outlined,
  'coffee_shop': Icons.local_cafe_outlined,
  'cultural_center': Icons.account_balance_outlined,
  'garden': Icons.local_florist_outlined,
  'hiking_area': Icons.hiking,
  'market': Icons.storefront_outlined,
  'museum': Icons.museum_outlined,
  'observation_deck': Icons.landscape_outlined,
  'park': Icons.park_outlined,
  'restaurant': Icons.restaurant_outlined,
  'shinto_shrine': Icons.temple_buddhist_outlined,
  'shopping_mall': Icons.local_mall_outlined,
  'store': Icons.storefront_outlined,
  'tea_house': Icons.emoji_food_beverage_outlined,
  'tourist_attraction': Icons.photo_camera_outlined,
};
