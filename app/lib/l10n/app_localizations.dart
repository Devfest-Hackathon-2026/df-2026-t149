import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('ja')];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチ'**
  String get appTitle;

  /// No description provided for @tabCheckin.
  ///
  /// In ja, this message translates to:
  /// **'チェックイン'**
  String get tabCheckin;

  /// No description provided for @syncSentOne.
  ///
  /// In ja, this message translates to:
  /// **'{placeName}は {order} 人目でした'**
  String syncSentOne(Object placeName, Object order);

  /// No description provided for @syncSentMany.
  ///
  /// In ja, this message translates to:
  /// **'{count} 件のチェックインを送信しました'**
  String syncSentMany(Object count);

  /// No description provided for @syncRejected.
  ///
  /// In ja, this message translates to:
  /// **'{rejected} 件の記録を送信できませんでした'**
  String syncRejected(Object rejected);

  /// No description provided for @startupFailedTitle.
  ///
  /// In ja, this message translates to:
  /// **'ログインを準備できませんでした'**
  String get startupFailedTitle;

  /// No description provided for @retry.
  ///
  /// In ja, this message translates to:
  /// **'もう一度試す'**
  String get retry;

  /// No description provided for @shareTextPlace.
  ///
  /// In ja, this message translates to:
  /// **'「{placeName}」に'**
  String shareTextPlace(Object placeName);

  /// No description provided for @shareTextCheckedIn.
  ///
  /// In ja, this message translates to:
  /// **'チェックインしました！'**
  String get shareTextCheckedIn;

  /// No description provided for @shareTextCheckedInOrder.
  ///
  /// In ja, this message translates to:
  /// **'{order}人目の訪問者としてチェックインしました！'**
  String shareTextCheckedInOrder(Object order);

  /// No description provided for @shareTextFirst.
  ///
  /// In ja, this message translates to:
  /// **'一番乗り🚩'**
  String get shareTextFirst;

  /// No description provided for @shareTextComment.
  ///
  /// In ja, this message translates to:
  /// **'\n「{c}」'**
  String shareTextComment(Object c);

  /// No description provided for @shareTextFooter.
  ///
  /// In ja, this message translates to:
  /// **'\nみんなの知らない場所へ #ウラミチ'**
  String get shareTextFooter;

  /// No description provided for @shareTargetX.
  ///
  /// In ja, this message translates to:
  /// **'𝕏 に投稿'**
  String get shareTargetX;

  /// No description provided for @shareTargetLine.
  ///
  /// In ja, this message translates to:
  /// **'LINE で送る'**
  String get shareTargetLine;

  /// No description provided for @errorLogIdUnknown.
  ///
  /// In ja, this message translates to:
  /// **'送信済みの記録の ID がわかりません。一覧を読み直してから直してください'**
  String get errorLogIdUnknown;

  /// No description provided for @errorSaveLocal.
  ///
  /// In ja, this message translates to:
  /// **'記録を端末に保存できませんでした。もう一度やり直してください'**
  String get errorSaveLocal;

  /// No description provided for @errorViewMessage.
  ///
  /// In ja, this message translates to:
  /// **'この部分を表示できませんでした'**
  String get errorViewMessage;

  /// No description provided for @favoriteRemoved.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りから外しました'**
  String get favoriteRemoved;

  /// No description provided for @favoriteAdded.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りに追加しました'**
  String get favoriteAdded;

  /// No description provided for @favoriteAddedNamed.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」をお気に入りに追加しました'**
  String favoriteAddedNamed(Object name);

  /// No description provided for @favoriteRemoveTooltip.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りから外す'**
  String get favoriteRemoveTooltip;

  /// No description provided for @favoriteAddTooltip.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りに入れる'**
  String get favoriteAddTooltip;

  /// No description provided for @zoomIn.
  ///
  /// In ja, this message translates to:
  /// **'拡大'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In ja, this message translates to:
  /// **'縮小'**
  String get zoomOut;

  /// No description provided for @zoomLever.
  ///
  /// In ja, this message translates to:
  /// **'ズームのレバー'**
  String get zoomLever;

  /// No description provided for @zoomLevel.
  ///
  /// In ja, this message translates to:
  /// **'ズーム {value}'**
  String zoomLevel(Object value);

  /// No description provided for @mockData.
  ///
  /// In ja, this message translates to:
  /// **'ダミーデータ'**
  String get mockData;

  /// No description provided for @reviewCountLabel.
  ///
  /// In ja, this message translates to:
  /// **'レビュー {value}件'**
  String reviewCountLabel(Object value);

  /// No description provided for @placeTypeArtGallery.
  ///
  /// In ja, this message translates to:
  /// **'美術館'**
  String get placeTypeArtGallery;

  /// No description provided for @placeTypeBuddhistTemple.
  ///
  /// In ja, this message translates to:
  /// **'寺'**
  String get placeTypeBuddhistTemple;

  /// No description provided for @placeTypeCafe.
  ///
  /// In ja, this message translates to:
  /// **'カフェ'**
  String get placeTypeCafe;

  /// No description provided for @placeTypeCoffeeShop.
  ///
  /// In ja, this message translates to:
  /// **'コーヒー店'**
  String get placeTypeCoffeeShop;

  /// No description provided for @placeTypeCulturalCenter.
  ///
  /// In ja, this message translates to:
  /// **'文化施設'**
  String get placeTypeCulturalCenter;

  /// No description provided for @placeTypeGarden.
  ///
  /// In ja, this message translates to:
  /// **'庭園'**
  String get placeTypeGarden;

  /// No description provided for @placeTypeHikingArea.
  ///
  /// In ja, this message translates to:
  /// **'ハイキングコース'**
  String get placeTypeHikingArea;

  /// No description provided for @placeTypeMarket.
  ///
  /// In ja, this message translates to:
  /// **'市場'**
  String get placeTypeMarket;

  /// No description provided for @placeTypeMuseum.
  ///
  /// In ja, this message translates to:
  /// **'博物館'**
  String get placeTypeMuseum;

  /// No description provided for @placeTypeObservationDeck.
  ///
  /// In ja, this message translates to:
  /// **'展望台'**
  String get placeTypeObservationDeck;

  /// No description provided for @placeTypePark.
  ///
  /// In ja, this message translates to:
  /// **'公園'**
  String get placeTypePark;

  /// No description provided for @placeTypeRestaurant.
  ///
  /// In ja, this message translates to:
  /// **'飲食店'**
  String get placeTypeRestaurant;

  /// No description provided for @placeTypeShrine.
  ///
  /// In ja, this message translates to:
  /// **'神社'**
  String get placeTypeShrine;

  /// No description provided for @placeTypeShoppingMall.
  ///
  /// In ja, this message translates to:
  /// **'ショッピングモール'**
  String get placeTypeShoppingMall;

  /// No description provided for @placeTypeStore.
  ///
  /// In ja, this message translates to:
  /// **'店'**
  String get placeTypeStore;

  /// No description provided for @placeTypeTeaHouse.
  ///
  /// In ja, this message translates to:
  /// **'茶屋'**
  String get placeTypeTeaHouse;

  /// No description provided for @placeTypeTouristAttraction.
  ///
  /// In ja, this message translates to:
  /// **'観光名所'**
  String get placeTypeTouristAttraction;

  /// No description provided for @placePhotosLabel.
  ///
  /// In ja, this message translates to:
  /// **'場所の写真 {count}枚'**
  String placePhotosLabel(Object count);

  /// No description provided for @photoCreditGoogle.
  ///
  /// In ja, this message translates to:
  /// **'写真：Google マップ'**
  String get photoCreditGoogle;

  /// No description provided for @photoCreditAuthor.
  ///
  /// In ja, this message translates to:
  /// **'写真：{name}（Google マップ）'**
  String photoCreditAuthor(Object name);

  /// No description provided for @reviewCountBarLabel.
  ///
  /// In ja, this message translates to:
  /// **'レビュー {value}件、有名スポットは {value2}件'**
  String reviewCountBarLabel(Object value, Object value2);

  /// No description provided for @genreWorship.
  ///
  /// In ja, this message translates to:
  /// **'寺社'**
  String get genreWorship;

  /// No description provided for @genreFood.
  ///
  /// In ja, this message translates to:
  /// **'飲食'**
  String get genreFood;

  /// No description provided for @genreNature.
  ///
  /// In ja, this message translates to:
  /// **'公園'**
  String get genreNature;

  /// No description provided for @genreCulture.
  ///
  /// In ja, this message translates to:
  /// **'美術館'**
  String get genreCulture;

  /// No description provided for @genreView.
  ///
  /// In ja, this message translates to:
  /// **'展望'**
  String get genreView;

  /// No description provided for @genreShopping.
  ///
  /// In ja, this message translates to:
  /// **'買い物'**
  String get genreShopping;

  /// No description provided for @stampLabel.
  ///
  /// In ja, this message translates to:
  /// **'{caption}のチェックインスタンプ、{label}'**
  String stampLabel(Object caption, Object label);

  /// No description provided for @stampFirst.
  ///
  /// In ja, this message translates to:
  /// **'一番乗り'**
  String get stampFirst;

  /// No description provided for @starRatingLabel.
  ///
  /// In ja, this message translates to:
  /// **'★{value}'**
  String starRatingLabel(Object value);

  /// No description provided for @starInputLabel.
  ///
  /// In ja, this message translates to:
  /// **'★{i}、{value}'**
  String starInputLabel(Object i, Object value);

  /// No description provided for @starInputPrompt.
  ///
  /// In ja, this message translates to:
  /// **'★で評価してください'**
  String get starInputPrompt;

  /// No description provided for @errorServerTimeout.
  ///
  /// In ja, this message translates to:
  /// **'サーバーから応答がありませんでした'**
  String get errorServerTimeout;

  /// No description provided for @errorServerUnreachable.
  ///
  /// In ja, this message translates to:
  /// **'サーバーに接続できませんでした'**
  String get errorServerUnreachable;

  /// No description provided for @percentUnderOne.
  ///
  /// In ja, this message translates to:
  /// **'1%未満'**
  String get percentUnderOne;

  /// No description provided for @verdictHit.
  ///
  /// In ja, this message translates to:
  /// **'当たり'**
  String get verdictHit;

  /// No description provided for @verdictMiss.
  ///
  /// In ja, this message translates to:
  /// **'ハズレ'**
  String get verdictMiss;

  /// No description provided for @stars5.
  ///
  /// In ja, this message translates to:
  /// **'最高！'**
  String get stars5;

  /// No description provided for @stars4.
  ///
  /// In ja, this message translates to:
  /// **'よかった'**
  String get stars4;

  /// No description provided for @stars3.
  ///
  /// In ja, this message translates to:
  /// **'ふつう'**
  String get stars3;

  /// No description provided for @stars2.
  ///
  /// In ja, this message translates to:
  /// **'まあまあ'**
  String get stars2;

  /// No description provided for @stars1.
  ///
  /// In ja, this message translates to:
  /// **'自分には合わなかった'**
  String get stars1;

  /// No description provided for @titleUntrodden.
  ///
  /// In ja, this message translates to:
  /// **'未踏'**
  String get titleUntrodden;

  /// No description provided for @titleHidden.
  ///
  /// In ja, this message translates to:
  /// **'穴場'**
  String get titleHidden;

  /// No description provided for @titleKnown.
  ///
  /// In ja, this message translates to:
  /// **'定番'**
  String get titleKnown;

  /// No description provided for @titleFamous.
  ///
  /// In ja, this message translates to:
  /// **'超有名'**
  String get titleFamous;

  /// No description provided for @genreOther.
  ///
  /// In ja, this message translates to:
  /// **'その他'**
  String get genreOther;

  /// No description provided for @iconHiking.
  ///
  /// In ja, this message translates to:
  /// **'歩く人'**
  String get iconHiking;

  /// No description provided for @iconPets.
  ///
  /// In ja, this message translates to:
  /// **'足あと'**
  String get iconPets;

  /// No description provided for @iconCafe.
  ///
  /// In ja, this message translates to:
  /// **'コーヒー'**
  String get iconCafe;

  /// No description provided for @iconRamen.
  ///
  /// In ja, this message translates to:
  /// **'ラーメン'**
  String get iconRamen;

  /// No description provided for @iconCamera.
  ///
  /// In ja, this message translates to:
  /// **'カメラ'**
  String get iconCamera;

  /// No description provided for @iconBike.
  ///
  /// In ja, this message translates to:
  /// **'自転車'**
  String get iconBike;

  /// No description provided for @iconTrain.
  ///
  /// In ja, this message translates to:
  /// **'電車'**
  String get iconTrain;

  /// No description provided for @iconLeaf.
  ///
  /// In ja, this message translates to:
  /// **'葉っぱ'**
  String get iconLeaf;

  /// No description provided for @iconMountain.
  ///
  /// In ja, this message translates to:
  /// **'山'**
  String get iconMountain;

  /// No description provided for @iconWaves.
  ///
  /// In ja, this message translates to:
  /// **'波'**
  String get iconWaves;

  /// No description provided for @iconTemple.
  ///
  /// In ja, this message translates to:
  /// **'お寺'**
  String get iconTemple;

  /// No description provided for @iconTree.
  ///
  /// In ja, this message translates to:
  /// **'木'**
  String get iconTree;

  /// No description provided for @errorProfileLoad.
  ///
  /// In ja, this message translates to:
  /// **'プロフィールを読み込めませんでした。通信状況を確認して、もう一度お試しください'**
  String get errorProfileLoad;

  /// No description provided for @errorLoginPopup.
  ///
  /// In ja, this message translates to:
  /// **'ログインの画面を開けませんでした。ブラウザでポップアップを許可して、もう一度お試しください'**
  String get errorLoginPopup;

  /// No description provided for @errorLoginNetwork.
  ///
  /// In ja, this message translates to:
  /// **'ログインできませんでした。通信状況を確認して、もう一度お試しください'**
  String get errorLoginNetwork;

  /// No description provided for @errorLoginCode.
  ///
  /// In ja, this message translates to:
  /// **'ログインできませんでした（{code}）。もう一度お試しください'**
  String errorLoginCode(Object code);

  /// No description provided for @errorGeneric.
  ///
  /// In ja, this message translates to:
  /// **'エラーが起きました'**
  String get errorGeneric;

  /// No description provided for @errorLoginRequired.
  ///
  /// In ja, this message translates to:
  /// **'ログインしてからやり直してください'**
  String get errorLoginRequired;

  /// No description provided for @shareOpenFailed.
  ///
  /// In ja, this message translates to:
  /// **'{label}画面を開けませんでした'**
  String shareOpenFailed(Object label);

  /// No description provided for @shareImageFailed.
  ///
  /// In ja, this message translates to:
  /// **'画像を作れませんでした'**
  String get shareImageFailed;

  /// No description provided for @shareInstagramHint.
  ///
  /// In ja, this message translates to:
  /// **'共有の画面で Instagram を選んでください。文はコピーしたので、投稿で貼り付けられます'**
  String get shareInstagramHint;

  /// No description provided for @shareSheetFailed.
  ///
  /// In ja, this message translates to:
  /// **'共有の画面を開けませんでした'**
  String get shareSheetFailed;

  /// No description provided for @shareTextCopied.
  ///
  /// In ja, this message translates to:
  /// **'シェアする文をコピーしました'**
  String get shareTextCopied;

  /// No description provided for @celebrationTitle.
  ///
  /// In ja, this message translates to:
  /// **'チェックイン完了'**
  String get celebrationTitle;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @stampRecorded.
  ///
  /// In ja, this message translates to:
  /// **'記録'**
  String get stampRecorded;

  /// No description provided for @orderLabel.
  ///
  /// In ja, this message translates to:
  /// **'{order}人目'**
  String orderLabel(Object order);

  /// No description provided for @stampRevisit.
  ///
  /// In ja, this message translates to:
  /// **'また来た'**
  String get stampRevisit;

  /// No description provided for @stampFirstVisit.
  ///
  /// In ja, this message translates to:
  /// **'はじめて'**
  String get stampFirstVisit;

  /// No description provided for @hashtag.
  ///
  /// In ja, this message translates to:
  /// **'#ウラミチ'**
  String get hashtag;

  /// No description provided for @checkinPendingOrder.
  ///
  /// In ja, this message translates to:
  /// **'通信できるようになってから、データを照合して何人目かが決定されます'**
  String get checkinPendingOrder;

  /// No description provided for @quotedComment.
  ///
  /// In ja, this message translates to:
  /// **'「{comment}」'**
  String quotedComment(Object comment);

  /// No description provided for @secretAchievementUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'シークレット実績を解除！'**
  String get secretAchievementUnlocked;

  /// No description provided for @achievementUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'実績を解除！'**
  String get achievementUnlocked;

  /// No description provided for @shareHeading.
  ///
  /// In ja, this message translates to:
  /// **'みんなに教える'**
  String get shareHeading;

  /// No description provided for @shareInstagram.
  ///
  /// In ja, this message translates to:
  /// **'Instagram で共有'**
  String get shareInstagram;

  /// No description provided for @shareCopyText.
  ///
  /// In ja, this message translates to:
  /// **'テキストをコピー'**
  String get shareCopyText;

  /// No description provided for @findNextPlace.
  ///
  /// In ja, this message translates to:
  /// **'次の場所を探す'**
  String get findNextPlace;

  /// No description provided for @conditionPending.
  ///
  /// In ja, this message translates to:
  /// **'{label}、まだ探していません'**
  String conditionPending(Object label);

  /// No description provided for @logEdited.
  ///
  /// In ja, this message translates to:
  /// **'記録を修正しました'**
  String get logEdited;

  /// No description provided for @logEditFailed.
  ///
  /// In ja, this message translates to:
  /// **'修正できませんでした：{value}'**
  String logEditFailed(Object value);

  /// No description provided for @editLog.
  ///
  /// In ja, this message translates to:
  /// **'記録を修正'**
  String get editLog;

  /// No description provided for @placeNameUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'場所の名前を表示できません'**
  String get placeNameUnavailable;

  /// No description provided for @comment.
  ///
  /// In ja, this message translates to:
  /// **'ひとこと'**
  String get comment;

  /// No description provided for @saving.
  ///
  /// In ja, this message translates to:
  /// **'保存しています…'**
  String get saving;

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @place.
  ///
  /// In ja, this message translates to:
  /// **'場所'**
  String get place;

  /// No description provided for @openMapsFailed.
  ///
  /// In ja, this message translates to:
  /// **'Google マップを開けませんでした'**
  String get openMapsFailed;

  /// No description provided for @dateTimeFull.
  ///
  /// In ja, this message translates to:
  /// **'{year}年{month}月{day}日 {hour}:{value}'**
  String dateTimeFull(
    Object year,
    Object month,
    Object day,
    Object hour,
    Object value,
  );

  /// No description provided for @placeNameLimitReached.
  ///
  /// In ja, this message translates to:
  /// **'今日の名前の読み込みの上限に達したため、名前を出せませんでした。Google マップでは開けます'**
  String get placeNameLimitReached;

  /// No description provided for @noComment.
  ///
  /// In ja, this message translates to:
  /// **'ひとことはありません'**
  String get noComment;

  /// No description provided for @myLog.
  ///
  /// In ja, this message translates to:
  /// **'自分の記録'**
  String get myLog;

  /// No description provided for @anonymousTraveler.
  ///
  /// In ja, this message translates to:
  /// **'名前のない旅人'**
  String get anonymousTraveler;

  /// No description provided for @visitorOrder.
  ///
  /// In ja, this message translates to:
  /// **'{n} 人目の訪問者'**
  String visitorOrder(Object n);

  /// No description provided for @openInGoogleMaps.
  ///
  /// In ja, this message translates to:
  /// **'Google マップで開く'**
  String get openInGoogleMaps;

  /// No description provided for @findAlternatives.
  ///
  /// In ja, this message translates to:
  /// **'代わりを探す'**
  String get findAlternatives;

  /// No description provided for @idleTitle.
  ///
  /// In ja, this message translates to:
  /// **'このあたりの穴場を探す'**
  String get idleTitle;

  /// No description provided for @idleMessage.
  ///
  /// In ja, this message translates to:
  /// **'地図を動かして、探す場所を決めましょう'**
  String get idleMessage;

  /// No description provided for @findAlternativesFor.
  ///
  /// In ja, this message translates to:
  /// **'「{query}」の代わりを探す'**
  String findAlternativesFor(Object query);

  /// No description provided for @searchThisArea.
  ///
  /// In ja, this message translates to:
  /// **'このエリアを探す'**
  String get searchThisArea;

  /// No description provided for @searchNearby.
  ///
  /// In ja, this message translates to:
  /// **'近くを探す'**
  String get searchNearby;

  /// No description provided for @exploreFar.
  ///
  /// In ja, this message translates to:
  /// **'遠くを調べる'**
  String get exploreFar;

  /// No description provided for @farRegion.
  ///
  /// In ja, this message translates to:
  /// **'遠くの地域'**
  String get farRegion;

  /// No description provided for @nearCurrentLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地の近く'**
  String get nearCurrentLocation;

  /// No description provided for @nearMapCenter.
  ///
  /// In ja, this message translates to:
  /// **'地図の中心の近く'**
  String get nearMapCenter;

  /// No description provided for @searchNearbyNoLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地が分からないため、地図の中心の近くを探します'**
  String get searchNearbyNoLocation;

  /// No description provided for @searchNearbyLocationFailed.
  ///
  /// In ja, this message translates to:
  /// **'現在地を測定できなかったため、地図の中心の近くを探します'**
  String get searchNearbyLocationFailed;

  /// No description provided for @movedToMockPlace.
  ///
  /// In ja, this message translates to:
  /// **'ダミーデータの地点へ移動しました'**
  String get movedToMockPlace;

  /// No description provided for @resultCount.
  ///
  /// In ja, this message translates to:
  /// **'穴場 {count} 件'**
  String resultCount(Object count);

  /// No description provided for @searching.
  ///
  /// In ja, this message translates to:
  /// **'探しています'**
  String get searching;

  /// No description provided for @results.
  ///
  /// In ja, this message translates to:
  /// **'結果'**
  String get results;

  /// No description provided for @collapseList.
  ///
  /// In ja, this message translates to:
  /// **'一覧を畳む'**
  String get collapseList;

  /// No description provided for @expandList.
  ///
  /// In ja, this message translates to:
  /// **'一覧を開く'**
  String get expandList;

  /// No description provided for @searchWithConditions.
  ///
  /// In ja, this message translates to:
  /// **'この条件で探す'**
  String get searchWithConditions;

  /// No description provided for @assistantName.
  ///
  /// In ja, this message translates to:
  /// **'Geminiちゃん'**
  String get assistantName;

  /// No description provided for @locationServiceOff.
  ///
  /// In ja, this message translates to:
  /// **'端末の位置情報がオフです'**
  String get locationServiceOff;

  /// No description provided for @locationDenied.
  ///
  /// In ja, this message translates to:
  /// **'位置情報が許可されていません'**
  String get locationDenied;

  /// No description provided for @openSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定を開く'**
  String get openSettings;

  /// No description provided for @locationFailed.
  ///
  /// In ja, this message translates to:
  /// **'現在地を測定できませんでした'**
  String get locationFailed;

  /// No description provided for @locationDeniedBrowser.
  ///
  /// In ja, this message translates to:
  /// **'ブラウザで位置情報が許可されていません。アドレスバーの左のマークから許可できます'**
  String get locationDeniedBrowser;

  /// No description provided for @goToMyLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地へ移動'**
  String get goToMyLocation;

  /// No description provided for @searchPlaceHint.
  ///
  /// In ja, this message translates to:
  /// **'場所を検索'**
  String get searchPlaceHint;

  /// No description provided for @search.
  ///
  /// In ja, this message translates to:
  /// **'検索'**
  String get search;

  /// No description provided for @clearSearch.
  ///
  /// In ja, this message translates to:
  /// **'検索を消す'**
  String get clearSearch;

  /// No description provided for @sortBalanced.
  ///
  /// In ja, this message translates to:
  /// **'おすすめ順'**
  String get sortBalanced;

  /// No description provided for @sortBalancedDescription.
  ///
  /// In ja, this message translates to:
  /// **'知られていなさ・近さ・評判のよさで並べる'**
  String get sortBalancedDescription;

  /// No description provided for @sortObscure.
  ///
  /// In ja, this message translates to:
  /// **'穴場順'**
  String get sortObscure;

  /// No description provided for @sortObscureDescription.
  ///
  /// In ja, this message translates to:
  /// **'口コミの少ない、知られていない場所から'**
  String get sortObscureDescription;

  /// No description provided for @sortNear.
  ///
  /// In ja, this message translates to:
  /// **'近い順'**
  String get sortNear;

  /// No description provided for @sortNearDescription.
  ///
  /// In ja, this message translates to:
  /// **'今いる場所（探した地点）から近い順'**
  String get sortNearDescription;

  /// No description provided for @currentLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地'**
  String get currentLocation;

  /// No description provided for @mapCenter.
  ///
  /// In ja, this message translates to:
  /// **'地図の中心'**
  String get mapCenter;

  /// No description provided for @searchingNearby.
  ///
  /// In ja, this message translates to:
  /// **'周辺の場所を探しています'**
  String get searchingNearby;

  /// No description provided for @notFound.
  ///
  /// In ja, this message translates to:
  /// **'見つかりませんでした'**
  String get notFound;

  /// No description provided for @widenRange.
  ///
  /// In ja, this message translates to:
  /// **'範囲を広げる'**
  String get widenRange;

  /// No description provided for @noPlacesForPopularity.
  ///
  /// In ja, this message translates to:
  /// **'この人気度の場所はありません'**
  String get noPlacesForPopularity;

  /// No description provided for @showFamousPlaces.
  ///
  /// In ja, this message translates to:
  /// **'有名な場所も見る'**
  String get showFamousPlaces;

  /// No description provided for @staleConditions.
  ///
  /// In ja, this message translates to:
  /// **'条件を変更しました。前の条件の結果を表示しています'**
  String get staleConditions;

  /// No description provided for @staleMoved.
  ///
  /// In ja, this message translates to:
  /// **'地図を動かしました。前の条件の結果を表示しています'**
  String get staleMoved;

  /// No description provided for @searchAgain.
  ///
  /// In ja, this message translates to:
  /// **'再検索する'**
  String get searchAgain;

  /// No description provided for @popularityHelp.
  ///
  /// In ja, this message translates to:
  /// **'左ほど知られていない場所、右ほど有名な場所です'**
  String get popularityHelp;

  /// No description provided for @radiusWide.
  ///
  /// In ja, this message translates to:
  /// **'{value}（広い範囲）'**
  String radiusWide(Object value);

  /// No description provided for @radiusLabel.
  ///
  /// In ja, this message translates to:
  /// **'半径 {value}'**
  String radiusLabel(Object value);

  /// No description provided for @popularity.
  ///
  /// In ja, this message translates to:
  /// **'人気度'**
  String get popularity;

  /// No description provided for @popularityLabel.
  ///
  /// In ja, this message translates to:
  /// **'人気度：{value}'**
  String popularityLabel(Object value);

  /// No description provided for @favorites.
  ///
  /// In ja, this message translates to:
  /// **'お気に入り'**
  String get favorites;

  /// No description provided for @popularityRange.
  ///
  /// In ja, this message translates to:
  /// **'{lo}〜{hi}'**
  String popularityRange(Object lo, Object hi);

  /// No description provided for @appliedOnSearch.
  ///
  /// In ja, this message translates to:
  /// **'再検索して反映'**
  String get appliedOnSearch;

  /// No description provided for @tabTimeline.
  ///
  /// In ja, this message translates to:
  /// **'タイムライン'**
  String get tabTimeline;

  /// No description provided for @nearby.
  ///
  /// In ja, this message translates to:
  /// **'みんな'**
  String get nearby;

  /// No description provided for @noLogsYet.
  ///
  /// In ja, this message translates to:
  /// **'まだ記録がありません'**
  String get noLogsYet;

  /// No description provided for @publicToggleToPrivate.
  ///
  /// In ja, this message translates to:
  /// **'公開中です。押すと非公開に'**
  String get publicToggleToPrivate;

  /// No description provided for @publicToggleToPublic.
  ///
  /// In ja, this message translates to:
  /// **'非公開です。押すと公開されます'**
  String get publicToggleToPublic;

  /// No description provided for @unsent.
  ///
  /// In ja, this message translates to:
  /// **'未送信'**
  String get unsent;

  /// No description provided for @reported.
  ///
  /// In ja, this message translates to:
  /// **'報告しました'**
  String get reported;

  /// No description provided for @timelineAreaNearby.
  ///
  /// In ja, this message translates to:
  /// **'周辺'**
  String get timelineAreaNearby;

  /// No description provided for @timelineAreaNationwide.
  ///
  /// In ja, this message translates to:
  /// **'全国の新着'**
  String get timelineAreaNationwide;

  /// No description provided for @timelineNationwideNote.
  ///
  /// In ja, this message translates to:
  /// **'全国で公開された口コミを、新しい順に見ています'**
  String get timelineNationwideNote;

  /// No description provided for @timelineToday.
  ///
  /// In ja, this message translates to:
  /// **'今日'**
  String get timelineToday;

  /// No description provided for @timelineYesterday.
  ///
  /// In ja, this message translates to:
  /// **'昨日'**
  String get timelineYesterday;

  /// No description provided for @timelineDate.
  ///
  /// In ja, this message translates to:
  /// **'{month}月{day}日（{weekday, select, 1{月} 2{火} 3{水} 4{木} 5{金} 6{土} other{日}}）'**
  String timelineDate(int month, int day, String weekday);

  /// No description provided for @timelineDateWithYear.
  ///
  /// In ja, this message translates to:
  /// **'{year}年{month}月{day}日（{weekday, select, 1{月} 2{火} 3{水} 4{木} 5{金} 6{土} other{日}}）'**
  String timelineDateWithYear(int year, int month, int day, String weekday);

  /// No description provided for @noNearbyLogs.
  ///
  /// In ja, this message translates to:
  /// **'この辺りで公開された記録はまだありません'**
  String get noNearbyLogs;

  /// No description provided for @reportLog.
  ///
  /// In ja, this message translates to:
  /// **'この記録を報告'**
  String get reportLog;

  /// No description provided for @author.
  ///
  /// In ja, this message translates to:
  /// **'投稿者'**
  String get author;

  /// No description provided for @visitorOrderShort.
  ///
  /// In ja, this message translates to:
  /// **'{order} 人目'**
  String visitorOrderShort(Object order);

  /// No description provided for @howWasIt.
  ///
  /// In ja, this message translates to:
  /// **'行ってみてどうでしたか？'**
  String get howWasIt;

  /// No description provided for @visibilityPrivate.
  ///
  /// In ja, this message translates to:
  /// **'非公開'**
  String get visibilityPrivate;

  /// No description provided for @visibilityPublic.
  ///
  /// In ja, this message translates to:
  /// **'一般公開'**
  String get visibilityPublic;

  /// No description provided for @record.
  ///
  /// In ja, this message translates to:
  /// **'記録する'**
  String get record;

  /// No description provided for @stampPending.
  ///
  /// In ja, this message translates to:
  /// **'送信待ち'**
  String get stampPending;

  /// No description provided for @tabMap.
  ///
  /// In ja, this message translates to:
  /// **'地図'**
  String get tabMap;

  /// No description provided for @tabAchievements.
  ///
  /// In ja, this message translates to:
  /// **'実績'**
  String get tabAchievements;

  /// No description provided for @ratingSummaryLabel.
  ///
  /// In ja, this message translates to:
  /// **'★{value}、{count}件の評価'**
  String ratingSummaryLabel(Object value, Object count);

  /// No description provided for @ratingCount.
  ///
  /// In ja, this message translates to:
  /// **'（{count}件）'**
  String ratingCount(Object count);

  /// No description provided for @noFavoritesYet.
  ///
  /// In ja, this message translates to:
  /// **'お気に入りはまだありません'**
  String get noFavoritesYet;

  /// No description provided for @noFavoritesMessage.
  ///
  /// In ja, this message translates to:
  /// **'場所の詳細や一覧のハートを押すとここにまとまります。'**
  String get noFavoritesMessage;

  /// No description provided for @placeNameLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'場所の名前を読み込めません'**
  String get placeNameLoadFailed;

  /// No description provided for @placeMaybeClosed.
  ///
  /// In ja, this message translates to:
  /// **'閉業したか、通信できなかった可能性があります'**
  String get placeMaybeClosed;

  /// No description provided for @assistantPromptQuiet.
  ///
  /// In ja, this message translates to:
  /// **'近くの静かな穴場を教えて'**
  String get assistantPromptQuiet;

  /// No description provided for @assistantPromptCafe.
  ///
  /// In ja, this message translates to:
  /// **'落ち着けるカフェはある？'**
  String get assistantPromptCafe;

  /// No description provided for @assistantPromptView.
  ///
  /// In ja, this message translates to:
  /// **'景色のいい穴場'**
  String get assistantPromptView;

  /// No description provided for @assistantPromptNightView.
  ///
  /// In ja, this message translates to:
  /// **'夜景がきれいなところ'**
  String get assistantPromptNightView;

  /// No description provided for @assistantPromptOtherGenre.
  ///
  /// In ja, this message translates to:
  /// **'ほかのジャンルだと？'**
  String get assistantPromptOtherGenre;

  /// No description provided for @assistantPromptWorship.
  ///
  /// In ja, this message translates to:
  /// **'寺社に絞って'**
  String get assistantPromptWorship;

  /// No description provided for @assistantPromptPark.
  ///
  /// In ja, this message translates to:
  /// **'公園でのんびりしたい'**
  String get assistantPromptPark;

  /// No description provided for @assistantGreeting.
  ///
  /// In ja, this message translates to:
  /// **'どんな場所を探しますか？地図の中心のまわりから、まだあまり知られていない場所を選びます。'**
  String get assistantGreeting;

  /// No description provided for @assistantSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'Gemini が穴場探しをお手伝いします'**
  String get assistantSubtitle;

  /// No description provided for @assistantSimpleMode.
  ///
  /// In ja, this message translates to:
  /// **'デモモードで答えています'**
  String get assistantSimpleMode;

  /// No description provided for @assistantRestart.
  ///
  /// In ja, this message translates to:
  /// **'最初から'**
  String get assistantRestart;

  /// No description provided for @assistantThinking.
  ///
  /// In ja, this message translates to:
  /// **'考えています'**
  String get assistantThinking;

  /// No description provided for @assistantThinkingEllipsis.
  ///
  /// In ja, this message translates to:
  /// **'考えています…'**
  String get assistantThinkingEllipsis;

  /// No description provided for @assistantShowOnMap.
  ///
  /// In ja, this message translates to:
  /// **'おすすめを地図に出す'**
  String get assistantShowOnMap;

  /// No description provided for @assistantTargetsTitle.
  ///
  /// In ja, this message translates to:
  /// **'見つかった場所'**
  String get assistantTargetsTitle;

  /// No description provided for @assistantHiddenNearbyTitle.
  ///
  /// In ja, this message translates to:
  /// **'そばの穴場'**
  String get assistantHiddenNearbyTitle;

  /// No description provided for @assistantTargetReason.
  ///
  /// In ja, this message translates to:
  /// **'探していた場所です'**
  String get assistantTargetReason;

  /// No description provided for @assistantMoveTo.
  ///
  /// In ja, this message translates to:
  /// **'{name}へ移動'**
  String assistantMoveTo(Object name);

  /// No description provided for @assistantSearchHere.
  ///
  /// In ja, this message translates to:
  /// **'地図でこのあたりを探す'**
  String get assistantSearchHere;

  /// No description provided for @assistantExploreWide.
  ///
  /// In ja, this message translates to:
  /// **'{name}を広い範囲で探す'**
  String assistantExploreWide(Object name);

  /// No description provided for @assistantMoreAlternatives.
  ///
  /// In ja, this message translates to:
  /// **'代わりをもっと見る'**
  String get assistantMoreAlternatives;

  /// No description provided for @assistantInputHint.
  ///
  /// In ja, this message translates to:
  /// **'Geminiちゃんに話しかける'**
  String get assistantInputHint;

  /// No description provided for @send.
  ///
  /// In ja, this message translates to:
  /// **'送る'**
  String get send;

  /// No description provided for @achievementUnlockedShort.
  ///
  /// In ja, this message translates to:
  /// **'解除！'**
  String get achievementUnlockedShort;

  /// No description provided for @achievementPromoted.
  ///
  /// In ja, this message translates to:
  /// **'{label}に昇格！'**
  String achievementPromoted(Object label);

  /// No description provided for @achievementTierEarned.
  ///
  /// In ja, this message translates to:
  /// **'{label}を獲得！'**
  String achievementTierEarned(Object label);

  /// No description provided for @achievementTierShare.
  ///
  /// In ja, this message translates to:
  /// **'{value}は全体の {p}'**
  String achievementTierShare(Object value, Object p);

  /// No description provided for @achievementShare.
  ///
  /// In ja, this message translates to:
  /// **'全体の {p} が解除'**
  String achievementShare(Object p);

  /// No description provided for @hiddenTitle.
  ///
  /// In ja, this message translates to:
  /// **'？？？'**
  String get hiddenTitle;

  /// No description provided for @secret.
  ///
  /// In ja, this message translates to:
  /// **'シークレット'**
  String get secret;

  /// No description provided for @achievementHint.
  ///
  /// In ja, this message translates to:
  /// **'ヒント：{hint}'**
  String achievementHint(Object hint);

  /// No description provided for @achievementUnlockedOn.
  ///
  /// In ja, this message translates to:
  /// **'{value} に解除'**
  String achievementUnlockedOn(Object value);

  /// No description provided for @achievementUnlockedAt.
  ///
  /// In ja, this message translates to:
  /// **'{value} に「{place}」で解除'**
  String achievementUnlockedAt(Object value, Object place);

  /// No description provided for @achievementSharePercent.
  ///
  /// In ja, this message translates to:
  /// **'全体の {value}'**
  String achievementSharePercent(Object value);

  /// No description provided for @achievementNextTier.
  ///
  /// In ja, this message translates to:
  /// **'{value}まであと {value2}'**
  String achievementNextTier(Object value, Object value2);

  /// No description provided for @achievementRemaining.
  ///
  /// In ja, this message translates to:
  /// **'あと {value}'**
  String achievementRemaining(Object value);

  /// No description provided for @achievementCongrats.
  ///
  /// In ja, this message translates to:
  /// **'やったね'**
  String get achievementCongrats;

  /// No description provided for @tierBronze.
  ///
  /// In ja, this message translates to:
  /// **'ブロンズ'**
  String get tierBronze;

  /// No description provided for @tierSilver.
  ///
  /// In ja, this message translates to:
  /// **'シルバー'**
  String get tierSilver;

  /// No description provided for @tierGold.
  ///
  /// In ja, this message translates to:
  /// **'ゴールド'**
  String get tierGold;

  /// No description provided for @rarityCommon.
  ///
  /// In ja, this message translates to:
  /// **'ふつう'**
  String get rarityCommon;

  /// No description provided for @rarityRare.
  ///
  /// In ja, this message translates to:
  /// **'レア'**
  String get rarityRare;

  /// No description provided for @rarityEpic.
  ///
  /// In ja, this message translates to:
  /// **'すごくレア'**
  String get rarityEpic;

  /// No description provided for @rarityLegend.
  ///
  /// In ja, this message translates to:
  /// **'伝説'**
  String get rarityLegend;

  /// No description provided for @achFirstStepTitle.
  ///
  /// In ja, this message translates to:
  /// **'はじめの一歩'**
  String get achFirstStepTitle;

  /// No description provided for @achFirstStepDescription.
  ///
  /// In ja, this message translates to:
  /// **'思い出ログを1件残す'**
  String get achFirstStepDescription;

  /// No description provided for @achFirstStepDetail.
  ///
  /// In ja, this message translates to:
  /// **'すべてはここから。知られていない場所へ行き、思い出を1件残しましょう。'**
  String get achFirstStepDetail;

  /// No description provided for @achPioneerTitle.
  ///
  /// In ja, this message translates to:
  /// **'開拓者'**
  String get achPioneerTitle;

  /// No description provided for @achPioneerDescription.
  ///
  /// In ja, this message translates to:
  /// **'\'{\'n\'}\'か所で1人目の訪問者になる'**
  String get achPioneerDescription;

  /// No description provided for @achPioneerDetail.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチで誰もチェックインしていない場所に、最初に足跡を残しました。'**
  String get achPioneerDetail;

  /// No description provided for @achVeteranTitle.
  ///
  /// In ja, this message translates to:
  /// **'古参の風格'**
  String get achVeteranTitle;

  /// No description provided for @achVeteranDescription.
  ///
  /// In ja, this message translates to:
  /// **'10人目までの訪問者として\'{\'n\'}\'か所を記録する'**
  String get achVeteranDescription;

  /// No description provided for @achVeteranDetail.
  ///
  /// In ja, this message translates to:
  /// **'流行る前から知っていた。そう言える場所を持っています。'**
  String get achVeteranDetail;

  /// No description provided for @achHonorableMissTitle.
  ///
  /// In ja, this message translates to:
  /// **'名誉のハズレ'**
  String get achHonorableMissTitle;

  /// No description provided for @achHonorableMissDescription.
  ///
  /// In ja, this message translates to:
  /// **'★1か★2の記録を1件残す'**
  String get achHonorableMissDescription;

  /// No description provided for @achHonorableMissDetail.
  ///
  /// In ja, this message translates to:
  /// **'ハズレも立派な開拓です。誰かが同じ道で迷わずに済みます。'**
  String get achHonorableMissDetail;

  /// No description provided for @achConnoisseurTitle.
  ///
  /// In ja, this message translates to:
  /// **'目利き'**
  String get achConnoisseurTitle;

  /// No description provided for @achConnoisseurDescription.
  ///
  /// In ja, this message translates to:
  /// **'★4以上の記録を\'{\'n\'}\'件残す'**
  String get achConnoisseurDescription;

  /// No description provided for @achConnoisseurDetail.
  ///
  /// In ja, this message translates to:
  /// **'良い場所を見つける目を持っています。'**
  String get achConnoisseurDetail;

  /// No description provided for @achPerfectViewTitle.
  ///
  /// In ja, this message translates to:
  /// **'満点の景色'**
  String get achPerfectViewTitle;

  /// No description provided for @achPerfectViewDescription.
  ///
  /// In ja, this message translates to:
  /// **'★5の記録を\'{\'n\'}\'件残す'**
  String get achPerfectViewDescription;

  /// No description provided for @achPerfectViewDetail.
  ///
  /// In ja, this message translates to:
  /// **'心から「最高！」と言える場所に何度も出会いました。'**
  String get achPerfectViewDetail;

  /// No description provided for @achWalkTitle.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチ散歩'**
  String get achWalkTitle;

  /// No description provided for @achWalkDescription.
  ///
  /// In ja, this message translates to:
  /// **'\'{\'n\'}\'か所を記録する（同じ場所は1回）'**
  String get achWalkDescription;

  /// No description provided for @achWalkDetail.
  ///
  /// In ja, this message translates to:
  /// **'気の向くままに歩いて、地図の余白をあなたの記録が埋めていきます。'**
  String get achWalkDetail;

  /// No description provided for @achRegularTitle.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチ常連'**
  String get achRegularTitle;

  /// No description provided for @achRegularDescription.
  ///
  /// In ja, this message translates to:
  /// **'思い出ログを\'{\'n\'}\'件残す'**
  String get achRegularDescription;

  /// No description provided for @achRegularDetail.
  ///
  /// In ja, this message translates to:
  /// **'記録を重ねるほど、街の見え方が変わってきます。ゴールドまで来れば、あなた自身がウラミチです。'**
  String get achRegularDetail;

  /// No description provided for @achConsistentTitle.
  ///
  /// In ja, this message translates to:
  /// **'三日坊主じゃない'**
  String get achConsistentTitle;

  /// No description provided for @achConsistentDescription.
  ///
  /// In ja, this message translates to:
  /// **'\'{\'n\'}\'日に分けて記録する'**
  String get achConsistentDescription;

  /// No description provided for @achConsistentDetail.
  ///
  /// In ja, this message translates to:
  /// **'1日だけの思いつきではありません。続けて歩いています。'**
  String get achConsistentDetail;

  /// No description provided for @achCommenterTitle.
  ///
  /// In ja, this message translates to:
  /// **'ひとこと名人'**
  String get achCommenterTitle;

  /// No description provided for @achCommenterDescription.
  ///
  /// In ja, this message translates to:
  /// **'ひとことを添えて\'{\'n\'}\'件記録する'**
  String get achCommenterDescription;

  /// No description provided for @achCommenterDetail.
  ///
  /// In ja, this message translates to:
  /// **'短い言葉が、次に行く誰かの道しるべになります。'**
  String get achCommenterDetail;

  /// No description provided for @achStorytellerTitle.
  ///
  /// In ja, this message translates to:
  /// **'語り部'**
  String get achStorytellerTitle;

  /// No description provided for @achStorytellerDescription.
  ///
  /// In ja, this message translates to:
  /// **'記録を\'{\'n\'}\'件タイムラインに公開する'**
  String get achStorytellerDescription;

  /// No description provided for @achStorytellerDetail.
  ///
  /// In ja, this message translates to:
  /// **'あなたの発見が、周りのみんなのタイムラインに届いています。'**
  String get achStorytellerDetail;

  /// No description provided for @achSoCloseTitle.
  ///
  /// In ja, this message translates to:
  /// **'惜しい！'**
  String get achSoCloseTitle;

  /// No description provided for @achSoCloseDescription.
  ///
  /// In ja, this message translates to:
  /// **'その場所の2人目の訪問者になる'**
  String get achSoCloseDescription;

  /// No description provided for @achSoCloseDetail.
  ///
  /// In ja, this message translates to:
  /// **'あと一歩で開拓者でした。でも2人目も十分に古参です。'**
  String get achSoCloseDetail;

  /// No description provided for @achSoCloseHint.
  ///
  /// In ja, this message translates to:
  /// **'あと少しで一番乗り……'**
  String get achSoCloseHint;

  /// No description provided for @achRoundNumberTitle.
  ///
  /// In ja, this message translates to:
  /// **'キリ番ゲッター'**
  String get achRoundNumberTitle;

  /// No description provided for @achRoundNumberDescription.
  ///
  /// In ja, this message translates to:
  /// **'10の倍数の番目の訪問者になる'**
  String get achRoundNumberDescription;

  /// No description provided for @achRoundNumberDetail.
  ///
  /// In ja, this message translates to:
  /// **'10人目、20人目……ちょうどの数字を踏みました。'**
  String get achRoundNumberDetail;

  /// No description provided for @achRoundNumberHint.
  ///
  /// In ja, this message translates to:
  /// **'何人目かの数字に注目'**
  String get achRoundNumberHint;

  /// No description provided for @achNightOwlTitle.
  ///
  /// In ja, this message translates to:
  /// **'夜ふかし探検家'**
  String get achNightOwlTitle;

  /// No description provided for @achNightOwlDescription.
  ///
  /// In ja, this message translates to:
  /// **'0時から4時の間に記録する'**
  String get achNightOwlDescription;

  /// No description provided for @achNightOwlDetail.
  ///
  /// In ja, this message translates to:
  /// **'みんなが眠っている時間にも、ウラミチは開いています。'**
  String get achNightOwlDetail;

  /// No description provided for @achNightOwlHint.
  ///
  /// In ja, this message translates to:
  /// **'月が見ている時間に'**
  String get achNightOwlHint;

  /// No description provided for @achEarlyBirdTitle.
  ///
  /// In ja, this message translates to:
  /// **'朝活の達人'**
  String get achEarlyBirdTitle;

  /// No description provided for @achEarlyBirdDescription.
  ///
  /// In ja, this message translates to:
  /// **'5時から7時の間に記録する'**
  String get achEarlyBirdDescription;

  /// No description provided for @achEarlyBirdDetail.
  ///
  /// In ja, this message translates to:
  /// **'人の少ない朝の街は、いつもと違う顔を見せます。'**
  String get achEarlyBirdDetail;

  /// No description provided for @achEarlyBirdHint.
  ///
  /// In ja, this message translates to:
  /// **'早起きは三文の徳'**
  String get achEarlyBirdHint;

  /// No description provided for @achHopperTitle.
  ///
  /// In ja, this message translates to:
  /// **'はしご旅'**
  String get achHopperTitle;

  /// No description provided for @achHopperDescription.
  ///
  /// In ja, this message translates to:
  /// **'1日に3か所を記録する'**
  String get achHopperDescription;

  /// No description provided for @achHopperDetail.
  ///
  /// In ja, this message translates to:
  /// **'次から次へ。今日は寄り道の多い一日でした。'**
  String get achHopperDetail;

  /// No description provided for @achHopperHint.
  ///
  /// In ja, this message translates to:
  /// **'一日に、いくつ回れる？'**
  String get achHopperHint;

  /// No description provided for @achWeekendTitle.
  ///
  /// In ja, this message translates to:
  /// **'週末冒険家'**
  String get achWeekendTitle;

  /// No description provided for @achWeekendDescription.
  ///
  /// In ja, this message translates to:
  /// **'土日に5件記録する'**
  String get achWeekendDescription;

  /// No description provided for @achWeekendDetail.
  ///
  /// In ja, this message translates to:
  /// **'休みの日は、知らない場所へ。'**
  String get achWeekendDetail;

  /// No description provided for @achWeekendHint.
  ///
  /// In ja, this message translates to:
  /// **'休みの日の過ごし方'**
  String get achWeekendHint;

  /// No description provided for @achTalkativeTitle.
  ///
  /// In ja, this message translates to:
  /// **'語りすぎ'**
  String get achTalkativeTitle;

  /// No description provided for @achTalkativeDescription.
  ///
  /// In ja, this message translates to:
  /// **'100文字以上のひとことを残す'**
  String get achTalkativeDescription;

  /// No description provided for @achTalkativeDetail.
  ///
  /// In ja, this message translates to:
  /// **'ひとことのはずが、ひとことでは収まりませんでした。'**
  String get achTalkativeDetail;

  /// No description provided for @achTalkativeHint.
  ///
  /// In ja, this message translates to:
  /// **'ひとこと、とは'**
  String get achTalkativeHint;

  /// No description provided for @achRevisitTitle.
  ///
  /// In ja, this message translates to:
  /// **'また来ちゃった'**
  String get achRevisitTitle;

  /// No description provided for @achRevisitDescription.
  ///
  /// In ja, this message translates to:
  /// **'同じ場所を3回記録する'**
  String get achRevisitDescription;

  /// No description provided for @achRevisitDetail.
  ///
  /// In ja, this message translates to:
  /// **'ここはもう、あなたの行きつけです。'**
  String get achRevisitDetail;

  /// No description provided for @achRevisitHint.
  ///
  /// In ja, this message translates to:
  /// **'気に入った場所はありますか'**
  String get achRevisitHint;

  /// No description provided for @almostUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'もう少しで解除'**
  String get almostUnlocked;

  /// No description provided for @noUnlockedAchievements.
  ///
  /// In ja, this message translates to:
  /// **'まだ解除した実績はありません。チェックインして思い出ログを残してみましょう'**
  String get noUnlockedAchievements;

  /// No description provided for @allAchievementsUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'すべての実績を解除しました！'**
  String get allAchievementsUnlocked;

  /// No description provided for @secretAchievementCount.
  ///
  /// In ja, this message translates to:
  /// **'シークレット実績　{secretUnlocked} / {secretTotal}'**
  String secretAchievementCount(Object secretUnlocked, Object secretTotal);

  /// No description provided for @secretAchievementHelp.
  ///
  /// In ja, this message translates to:
  /// **'条件は解除するまでわかりません。タップするとヒントが見られます。'**
  String get secretAchievementHelp;

  /// No description provided for @filterAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて'**
  String get filterAll;

  /// No description provided for @filterUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'解除済み'**
  String get filterUnlocked;

  /// No description provided for @filterLocked.
  ///
  /// In ja, this message translates to:
  /// **'未解除'**
  String get filterLocked;

  /// No description provided for @almostTileLabel.
  ///
  /// In ja, this message translates to:
  /// **'{title}、あと{left}'**
  String almostTileLabel(Object title, Object left);

  /// No description provided for @unlockedOfTotal.
  ///
  /// In ja, this message translates to:
  /// **'/ {total} 解除'**
  String unlockedOfTotal(Object total);

  /// No description provided for @achievementsEmptyHelp.
  ///
  /// In ja, this message translates to:
  /// **'チェックインして思い出ログを残すと、実績が増えていきます。'**
  String get achievementsEmptyHelp;

  /// No description provided for @achievementTileUnlocked.
  ///
  /// In ja, this message translates to:
  /// **'{title}、解除済み'**
  String achievementTileUnlocked(Object title);

  /// No description provided for @achievementTileUnlockedTier.
  ///
  /// In ja, this message translates to:
  /// **'{title}、解除済み、{tier}'**
  String achievementTileUnlockedTier(Object title, Object tier);

  /// No description provided for @achievementTileLocked.
  ///
  /// In ja, this message translates to:
  /// **'{title}、未解除'**
  String achievementTileLocked(Object title);

  /// No description provided for @achievementAllTiersOn.
  ///
  /// In ja, this message translates to:
  /// **'{year}/{month}/{day} にすべての段階を達成'**
  String achievementAllTiersOn(Object year, Object month, Object day);

  /// No description provided for @achievementUnlockedOnDate.
  ///
  /// In ja, this message translates to:
  /// **'{year}/{month}/{day} に解除'**
  String achievementUnlockedOnDate(Object year, Object month, Object day);

  /// No description provided for @directions.
  ///
  /// In ja, this message translates to:
  /// **'道順'**
  String get directions;

  /// No description provided for @reviews.
  ///
  /// In ja, this message translates to:
  /// **'レビュー'**
  String get reviews;

  /// No description provided for @uramichiVisitors.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチで来た人'**
  String get uramichiVisitors;

  /// No description provided for @distance.
  ///
  /// In ja, this message translates to:
  /// **'距離'**
  String get distance;

  /// No description provided for @distanceFrom.
  ///
  /// In ja, this message translates to:
  /// **'{name}から'**
  String distanceFrom(Object name);

  /// No description provided for @iWasHere.
  ///
  /// In ja, this message translates to:
  /// **'ここに来た！'**
  String get iWasHere;

  /// No description provided for @start.
  ///
  /// In ja, this message translates to:
  /// **'はじめる'**
  String get start;

  /// No description provided for @reload.
  ///
  /// In ja, this message translates to:
  /// **'もう一度読み込む'**
  String get reload;

  /// No description provided for @logout.
  ///
  /// In ja, this message translates to:
  /// **'ログアウト'**
  String get logout;

  /// No description provided for @loginPrivacy.
  ///
  /// In ja, this message translates to:
  /// **'他のユーザーには、アプリ内で設定したニックネームとアイコン、一般公開に設定した記録のみが表示されます'**
  String get loginPrivacy;

  /// No description provided for @appTagline.
  ///
  /// In ja, this message translates to:
  /// **'逆張り観光アプリ'**
  String get appTagline;

  /// No description provided for @appLead.
  ///
  /// In ja, this message translates to:
  /// **'有名スポットの代わりに、まだ知られていない場所へ。'**
  String get appLead;

  /// No description provided for @loginFeatureSearch.
  ///
  /// In ja, this message translates to:
  /// **'口コミの少ない穴場を地図から探す'**
  String get loginFeatureSearch;

  /// No description provided for @loginFeatureStamp.
  ///
  /// In ja, this message translates to:
  /// **'行った場所でチェックインスタンプを集める'**
  String get loginFeatureStamp;

  /// No description provided for @loginFeatureBadge.
  ///
  /// In ja, this message translates to:
  /// **'歩いた記録が実績のバッジに'**
  String get loginFeatureBadge;

  /// No description provided for @loggingIn.
  ///
  /// In ja, this message translates to:
  /// **'ログインしています'**
  String get loggingIn;

  /// No description provided for @loginWithGoogle.
  ///
  /// In ja, this message translates to:
  /// **'Google でログイン'**
  String get loginWithGoogle;

  /// No description provided for @errorProfileSave.
  ///
  /// In ja, this message translates to:
  /// **'プロフィールを保存できませんでした。通信状況を確認して、もう一度お試しください'**
  String get errorProfileSave;

  /// No description provided for @profile.
  ///
  /// In ja, this message translates to:
  /// **'プロフィール'**
  String get profile;

  /// No description provided for @nickname.
  ///
  /// In ja, this message translates to:
  /// **'ニックネーム'**
  String get nickname;

  /// No description provided for @nicknameHint.
  ///
  /// In ja, this message translates to:
  /// **'例：路地裏の旅人'**
  String get nicknameHint;

  /// No description provided for @nicknameHelper.
  ///
  /// In ja, this message translates to:
  /// **'タイムラインに表示されます'**
  String get nicknameHelper;

  /// No description provided for @nicknameTooLong.
  ///
  /// In ja, this message translates to:
  /// **'{nicknameMaxLength}文字までです'**
  String nicknameTooLong(Object nicknameMaxLength);

  /// No description provided for @icon.
  ///
  /// In ja, this message translates to:
  /// **'アイコン'**
  String get icon;

  /// No description provided for @regionPickerLead.
  ///
  /// In ja, this message translates to:
  /// **'まだあまり知られていない地域を、のんびり歩いてみませんか？'**
  String get regionPickerLead;

  /// No description provided for @regionSearchHint.
  ///
  /// In ja, this message translates to:
  /// **'地名で調べる（例：飛騨高山）'**
  String get regionSearchHint;

  /// No description provided for @regionSearch.
  ///
  /// In ja, this message translates to:
  /// **'調べる'**
  String get regionSearch;

  /// No description provided for @regionPairsHeading.
  ///
  /// In ja, this message translates to:
  /// **'次の旅の候補に'**
  String get regionPairsHeading;

  /// No description provided for @regionAreasHeading.
  ///
  /// In ja, this message translates to:
  /// **'地方から選ぶ'**
  String get regionAreasHeading;

  /// No description provided for @regionPairLabel.
  ///
  /// In ja, this message translates to:
  /// **'{name}に行ったことがあるなら'**
  String regionPairLabel(Object name);

  /// No description provided for @settings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @settingsAppearance.
  ///
  /// In ja, this message translates to:
  /// **'見た目'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In ja, this message translates to:
  /// **'テーマ'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In ja, this message translates to:
  /// **'自動'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In ja, this message translates to:
  /// **'ライト'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In ja, this message translates to:
  /// **'ダーク'**
  String get themeDark;

  /// No description provided for @settingsKeyColor.
  ///
  /// In ja, this message translates to:
  /// **'キーカラー'**
  String get settingsKeyColor;

  /// No description provided for @settingsMotionSound.
  ///
  /// In ja, this message translates to:
  /// **'動きと音'**
  String get settingsMotionSound;

  /// No description provided for @settingsHaptics.
  ///
  /// In ja, this message translates to:
  /// **'振動（ハプティクス）'**
  String get settingsHaptics;

  /// No description provided for @settingsHapticsDescription.
  ///
  /// In ja, this message translates to:
  /// **'★を付けたときやチェックインしたときなどに、端末を振動させる'**
  String get settingsHapticsDescription;

  /// No description provided for @settingsSound.
  ///
  /// In ja, this message translates to:
  /// **'効果音'**
  String get settingsSound;

  /// No description provided for @settingsSoundDescription.
  ///
  /// In ja, this message translates to:
  /// **'チェックインや実績の解除のときに音を鳴らす。マナーモードのときは鳴らさない'**
  String get settingsSoundDescription;

  /// No description provided for @settingsData.
  ///
  /// In ja, this message translates to:
  /// **'データ'**
  String get settingsData;

  /// No description provided for @settingsDemoData.
  ///
  /// In ja, this message translates to:
  /// **'デモデータで動かす'**
  String get settingsDemoData;

  /// No description provided for @settingsEndpoint.
  ///
  /// In ja, this message translates to:
  /// **'接続先'**
  String get settingsEndpoint;

  /// No description provided for @none.
  ///
  /// In ja, this message translates to:
  /// **'なし'**
  String get none;

  /// No description provided for @colorWallpaper.
  ///
  /// In ja, this message translates to:
  /// **'壁紙から自動設定'**
  String get colorWallpaper;

  /// No description provided for @colorOther.
  ///
  /// In ja, this message translates to:
  /// **'ほかの色'**
  String get colorOther;

  /// No description provided for @hue.
  ///
  /// In ja, this message translates to:
  /// **'色相'**
  String get hue;

  /// No description provided for @brightness.
  ///
  /// In ja, this message translates to:
  /// **'明るさ'**
  String get brightness;

  /// No description provided for @useThisColor.
  ///
  /// In ja, this message translates to:
  /// **'この色にする'**
  String get useThisColor;

  /// No description provided for @searchingAlternatives.
  ///
  /// In ja, this message translates to:
  /// **'「{query}」の代わりを探しています'**
  String searchingAlternatives(Object query);

  /// No description provided for @originNotFound.
  ///
  /// In ja, this message translates to:
  /// **'「{query}」が見つかりませんでした'**
  String originNotFound(Object query);

  /// No description provided for @searchAnotherName.
  ///
  /// In ja, this message translates to:
  /// **'別の名前で探す'**
  String get searchAnotherName;

  /// No description provided for @alternativesLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'候補を読み込めませんでした'**
  String get alternativesLoadFailed;

  /// No description provided for @noAlternativesNearby.
  ///
  /// In ja, this message translates to:
  /// **'近くに代わりの場所が見つかりませんでした'**
  String get noAlternativesNearby;

  /// No description provided for @alternativesTitle.
  ///
  /// In ja, this message translates to:
  /// **'代わりに行くなら\nここ'**
  String get alternativesTitle;

  /// No description provided for @famousSpotHint.
  ///
  /// In ja, this message translates to:
  /// **'有名スポットの名前'**
  String get famousSpotHint;

  /// No description provided for @clearInput.
  ///
  /// In ja, this message translates to:
  /// **'入力を消す'**
  String get clearInput;

  /// No description provided for @sameGenre.
  ///
  /// In ja, this message translates to:
  /// **'同じ{label}'**
  String sameGenre(Object label);

  /// No description provided for @reviewRatio.
  ///
  /// In ja, this message translates to:
  /// **'レビュー 1/{value}'**
  String reviewRatio(Object value);

  /// No description provided for @onlyZeroReviews.
  ///
  /// In ja, this message translates to:
  /// **'レビュー 0件の場所だけ'**
  String get onlyZeroReviews;

  /// No description provided for @reviewRatioOrLess.
  ///
  /// In ja, this message translates to:
  /// **'レビュー 1/{value} 以下'**
  String reviewRatioOrLess(Object value);

  /// No description provided for @otherCandidates.
  ///
  /// In ja, this message translates to:
  /// **'ほかの候補'**
  String get otherCandidates;

  /// No description provided for @candidateCount.
  ///
  /// In ja, this message translates to:
  /// **'  {count}件'**
  String candidateCount(Object count);

  /// No description provided for @here.
  ///
  /// In ja, this message translates to:
  /// **'ここ'**
  String get here;

  /// No description provided for @countLabel.
  ///
  /// In ja, this message translates to:
  /// **'{value}件'**
  String countLabel(Object value);

  /// No description provided for @badgePioneer.
  ///
  /// In ja, this message translates to:
  /// **'開拓者バッジ（最初の訪問者）'**
  String get badgePioneer;

  /// No description provided for @badgeVeteran.
  ///
  /// In ja, this message translates to:
  /// **'古参バッジ（{order} 人目）'**
  String badgeVeteran(Object order);

  /// No description provided for @badgePioneerShort.
  ///
  /// In ja, this message translates to:
  /// **'開拓者'**
  String get badgePioneerShort;

  /// No description provided for @badgeHonorableMiss.
  ///
  /// In ja, this message translates to:
  /// **'名誉のハズレ'**
  String get badgeHonorableMiss;

  /// No description provided for @badgeRegular.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチ常連'**
  String get badgeRegular;

  /// No description provided for @reloadLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地を読み直す'**
  String get reloadLocation;

  /// No description provided for @unsentCount.
  ///
  /// In ja, this message translates to:
  /// **'未送信 {pending} 件'**
  String unsentCount(Object pending);

  /// No description provided for @checkingLocation.
  ///
  /// In ja, this message translates to:
  /// **'現在地を確認しています'**
  String get checkingLocation;

  /// No description provided for @searchingSpots.
  ///
  /// In ja, this message translates to:
  /// **'近くのスポットを探しています'**
  String get searchingSpots;

  /// No description provided for @locationCheckFailed.
  ///
  /// In ja, this message translates to:
  /// **'現在地を確認できませんでした'**
  String get locationCheckFailed;

  /// No description provided for @findOnMap.
  ///
  /// In ja, this message translates to:
  /// **'地図で探す'**
  String get findOnMap;

  /// No description provided for @noSpotsNearby.
  ///
  /// In ja, this message translates to:
  /// **'近くにスポットがありません'**
  String get noSpotsNearby;

  /// No description provided for @searchAgainShort.
  ///
  /// In ja, this message translates to:
  /// **'もう一度探す'**
  String get searchAgainShort;

  /// No description provided for @offline.
  ///
  /// In ja, this message translates to:
  /// **'通信できません'**
  String get offline;

  /// No description provided for @offlineRecordHelp.
  ///
  /// In ja, this message translates to:
  /// **'今の場所を記録すると、通信できるようになってからスポットを選択できます'**
  String get offlineRecordHelp;

  /// No description provided for @recordHere.
  ///
  /// In ja, this message translates to:
  /// **'今の場所を記録'**
  String get recordHere;

  /// No description provided for @spotLimitReached.
  ///
  /// In ja, this message translates to:
  /// **'今日はこれ以上、近くのスポットを探せません'**
  String get spotLimitReached;

  /// No description provided for @spotLimitHelp.
  ///
  /// In ja, this message translates to:
  /// **'地図で場所を探して、詳細の画面からチェックインできます。明日になると、また近くを探せます'**
  String get spotLimitHelp;

  /// No description provided for @recordedHere.
  ///
  /// In ja, this message translates to:
  /// **'今の場所を記録しました'**
  String get recordedHere;

  /// No description provided for @allowLocation.
  ///
  /// In ja, this message translates to:
  /// **'位置情報を許可'**
  String get allowLocation;

  /// No description provided for @distanceOffline.
  ///
  /// In ja, this message translates to:
  /// **'{value} m・オフライン'**
  String distanceOffline(Object value);

  /// No description provided for @details.
  ///
  /// In ja, this message translates to:
  /// **'詳細'**
  String get details;

  /// No description provided for @placeDetailsTooltip.
  ///
  /// In ja, this message translates to:
  /// **'{name}の詳細'**
  String placeDetailsTooltip(Object name);

  /// No description provided for @possibleVisits.
  ///
  /// In ja, this message translates to:
  /// **'行ったかもしれない場所'**
  String get possibleVisits;

  /// No description provided for @skipThisTime.
  ///
  /// In ja, this message translates to:
  /// **'今回はチェックインしない'**
  String get skipThisTime;

  /// No description provided for @neverSuggestPlace.
  ///
  /// In ja, this message translates to:
  /// **'この場所を今後提案しない'**
  String get neverSuggestPlace;

  /// No description provided for @positionRecorded.
  ///
  /// In ja, this message translates to:
  /// **'位置を記録しました'**
  String get positionRecorded;

  /// No description provided for @searchingSpotsShort.
  ///
  /// In ja, this message translates to:
  /// **'スポットを探しています…'**
  String get searchingSpotsShort;

  /// No description provided for @spotsLoadFailed.
  ///
  /// In ja, this message translates to:
  /// **'スポットを読み込めませんでした'**
  String get spotsLoadFailed;

  /// No description provided for @skipCheckin.
  ///
  /// In ja, this message translates to:
  /// **'チェックインしない'**
  String get skipCheckin;

  /// No description provided for @findSpots.
  ///
  /// In ja, this message translates to:
  /// **'スポットを探す'**
  String get findSpots;

  /// No description provided for @changePlace.
  ///
  /// In ja, this message translates to:
  /// **'場所を変更'**
  String get changePlace;

  /// No description provided for @timeRange.
  ///
  /// In ja, this message translates to:
  /// **'{start}〜{value}'**
  String timeRange(Object start, Object value);

  /// No description provided for @recordStaysTitle.
  ///
  /// In ja, this message translates to:
  /// **'滞在した場所を記録しますか？'**
  String get recordStaysTitle;

  /// No description provided for @doNotRecord.
  ///
  /// In ja, this message translates to:
  /// **'記録しない'**
  String get doNotRecord;

  /// No description provided for @recordStays.
  ///
  /// In ja, this message translates to:
  /// **'滞在した場所を記録'**
  String get recordStays;

  /// No description provided for @mapPinLabel.
  ///
  /// In ja, this message translates to:
  /// **'{name}、{value}、レビュー {value2}件'**
  String mapPinLabel(Object name, Object value, Object value2);

  /// No description provided for @mapPinLabelNoReviews.
  ///
  /// In ja, this message translates to:
  /// **'{name}、{value}'**
  String mapPinLabelNoReviews(Object name, Object value);

  /// No description provided for @recentUnlock.
  ///
  /// In ja, this message translates to:
  /// **'最近の解除：{title}（{month}/{day}）'**
  String recentUnlock(Object title, Object month, Object day);

  /// No description provided for @recordStaysMessage.
  ///
  /// In ja, this message translates to:
  /// **'同じ場所に {inMinutes} 分以上いる場合に、この端末に位置と時刻を記録し、あとからチェックインすることができます。アプリを閉じていても記録するために、アプリの位置情報の権限では「常に許可」を選んでください。スポットを探すときのみ、位置をサーバーに送信します。'**
  String recordStaysMessage(Object inMinutes);

  /// No description provided for @distanceToPlace.
  ///
  /// In ja, this message translates to:
  /// **'この場所まで {value} あります。{value2} 以内でチェックインできます'**
  String distanceToPlace(Object value, Object value2);

  /// No description provided for @settingsDemoDataDescription.
  ///
  /// In ja, this message translates to:
  /// **'オンのあいだは架空の場所だけを使い、サーバーにも Google にも問い合わせません。オフのときはデモデータを使いません'**
  String get settingsDemoDataDescription;

  /// No description provided for @photoLabel.
  ///
  /// In ja, this message translates to:
  /// **'記録の写真'**
  String get photoLabel;

  /// No description provided for @photoUnavailable.
  ///
  /// In ja, this message translates to:
  /// **'写真を読み込めません'**
  String get photoUnavailable;

  /// No description provided for @photoUnsupported.
  ///
  /// In ja, this message translates to:
  /// **'JPEG、PNG、WebP の写真を選んでください'**
  String get photoUnsupported;

  /// No description provided for @photoTooLarge.
  ///
  /// In ja, this message translates to:
  /// **'写真が大きすぎます。ほかの写真を選んでください'**
  String get photoTooLarge;

  /// No description provided for @photoPickFailed.
  ///
  /// In ja, this message translates to:
  /// **'写真を選べませんでした'**
  String get photoPickFailed;

  /// No description provided for @photoTake.
  ///
  /// In ja, this message translates to:
  /// **'写真を撮る'**
  String get photoTake;

  /// No description provided for @photoChoose.
  ///
  /// In ja, this message translates to:
  /// **'写真を選ぶ'**
  String get photoChoose;

  /// No description provided for @photoAdd.
  ///
  /// In ja, this message translates to:
  /// **'写真を添える'**
  String get photoAdd;

  /// No description provided for @photoRemove.
  ///
  /// In ja, this message translates to:
  /// **'写真を外す'**
  String get photoRemove;

  /// No description provided for @photoUploadFailed.
  ///
  /// In ja, this message translates to:
  /// **'写真を送れなかったので、写真なしで残しました'**
  String get photoUploadFailed;

  /// No description provided for @reactionWant.
  ///
  /// In ja, this message translates to:
  /// **'行ってみたい'**
  String get reactionWant;

  /// No description provided for @reactionHelpful.
  ///
  /// In ja, this message translates to:
  /// **'参考になった'**
  String get reactionHelpful;

  /// No description provided for @reactionFailed.
  ///
  /// In ja, this message translates to:
  /// **'反応を送れませんでした。もう一度お試しください'**
  String get reactionFailed;

  /// No description provided for @reactionCount.
  ///
  /// In ja, this message translates to:
  /// **'{label} {count}件'**
  String reactionCount(String label, int count);

  /// No description provided for @stampBookTitle.
  ///
  /// In ja, this message translates to:
  /// **'スタンプ帳（{count}個）'**
  String stampBookTitle(int count);

  /// No description provided for @stampBookAll.
  ///
  /// In ja, this message translates to:
  /// **'すべて見る'**
  String get stampBookAll;

  /// No description provided for @stampBookEmpty.
  ///
  /// In ja, this message translates to:
  /// **'チェックインすると、場所の種類ごとのスタンプがここにたまります'**
  String get stampBookEmpty;

  /// No description provided for @stampBookDate.
  ///
  /// In ja, this message translates to:
  /// **'{month}/{day}'**
  String stampBookDate(int month, int day);

  /// No description provided for @stampBookMonth.
  ///
  /// In ja, this message translates to:
  /// **'{year}年{month}月'**
  String stampBookMonth(int year, int month);

  /// No description provided for @stampBookKindCount.
  ///
  /// In ja, this message translates to:
  /// **'{kind} {count}'**
  String stampBookKindCount(String kind, int count);

  /// No description provided for @stampBookStampLabel.
  ///
  /// In ja, this message translates to:
  /// **'{place}のスタンプ（{month}月{day}日）'**
  String stampBookStampLabel(String place, int month, int day);

  /// No description provided for @notifyStayTitle.
  ///
  /// In ja, this message translates to:
  /// **'ここで少しゆっくりしましたか？'**
  String get notifyStayTitle;

  /// No description provided for @notifyStayBody.
  ///
  /// In ja, this message translates to:
  /// **'アプリを開くと、いまいる場所にチェックインしてスタンプを押せます'**
  String get notifyStayBody;

  /// No description provided for @notifyStayChannel.
  ///
  /// In ja, this message translates to:
  /// **'滞在の知らせ'**
  String get notifyStayChannel;

  /// No description provided for @notifyReactionsBody.
  ///
  /// In ja, this message translates to:
  /// **'あなたの口コミに新しい反応が{count}件あります'**
  String notifyReactionsBody(int count);

  /// No description provided for @notifyReactionsOpen.
  ///
  /// In ja, this message translates to:
  /// **'見る'**
  String get notifyReactionsOpen;

  /// No description provided for @settingsNotifications.
  ///
  /// In ja, this message translates to:
  /// **'通知'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsDescription.
  ///
  /// In ja, this message translates to:
  /// **'同じ場所にしばらくいたときと、口コミに反応があったときに知らせます'**
  String get settingsNotificationsDescription;

  /// No description provided for @settingsNotificationsWeb.
  ///
  /// In ja, this message translates to:
  /// **'Web 版では、口コミへの反応をアプリを開いたときに画面の中で知らせます'**
  String get settingsNotificationsWeb;

  /// No description provided for @notificationsDenied.
  ///
  /// In ja, this message translates to:
  /// **'通知が許可されていません。端末の設定から許可できます'**
  String get notificationsDenied;

  /// No description provided for @pressToStamp.
  ///
  /// In ja, this message translates to:
  /// **'押してスタンプ'**
  String get pressToStamp;

  /// No description provided for @pressToStampAt.
  ///
  /// In ja, this message translates to:
  /// **'{place}で押してスタンプ'**
  String pressToStampAt(String place);

  /// No description provided for @pressStampShort.
  ///
  /// In ja, this message translates to:
  /// **'押す'**
  String get pressStampShort;

  /// No description provided for @pressLater.
  ///
  /// In ja, this message translates to:
  /// **'後から押す'**
  String get pressLater;

  /// No description provided for @hereQuestion.
  ///
  /// In ja, this message translates to:
  /// **'いま、ここにいますか？'**
  String get hereQuestion;

  /// No description provided for @whereAreYou.
  ///
  /// In ja, this message translates to:
  /// **'いまいる場所を選んでください'**
  String get whereAreYou;

  /// No description provided for @otherPlaces.
  ///
  /// In ja, this message translates to:
  /// **'ちがう場所？（近くにあと{count}か所）'**
  String otherPlaces(int count);

  /// No description provided for @findAroundOnMap.
  ///
  /// In ja, this message translates to:
  /// **'地図で周りを探す'**
  String get findAroundOnMap;

  /// No description provided for @journeyTitle.
  ///
  /// In ja, this message translates to:
  /// **'今日の旅'**
  String get journeyTitle;

  /// No description provided for @journeySummary.
  ///
  /// In ja, this message translates to:
  /// **'スタンプ {count} 個'**
  String journeySummary(int count);

  /// No description provided for @journeyEmpty.
  ///
  /// In ja, this message translates to:
  /// **'今日はまだスタンプがありません。着いた場所で、上のスタンプを押してみましょう'**
  String get journeyEmpty;

  /// No description provided for @journeyStay.
  ///
  /// In ja, this message translates to:
  /// **'押し忘れ？ ここに{minutes}分いました'**
  String journeyStay(int minutes);

  /// No description provided for @journeyStayShort.
  ///
  /// In ja, this message translates to:
  /// **'押し忘れ？ ここにいました'**
  String get journeyStayShort;

  /// No description provided for @mapHereTitle.
  ///
  /// In ja, this message translates to:
  /// **'いま「{place}」の近くにいます'**
  String mapHereTitle(String place);

  /// No description provided for @mapHereSubtitle.
  ///
  /// In ja, this message translates to:
  /// **'押すとスタンプを押して記録できます'**
  String get mapHereSubtitle;

  /// No description provided for @detailStampTitle.
  ///
  /// In ja, this message translates to:
  /// **'ここで押してスタンプ'**
  String get detailStampTitle;

  /// No description provided for @detailStampHelp.
  ///
  /// In ja, this message translates to:
  /// **'{range}以内に着いたら押せます'**
  String detailStampHelp(String range);

  /// No description provided for @typeAndDistance.
  ///
  /// In ja, this message translates to:
  /// **'{type}・{distance}'**
  String typeAndDistance(String type, String distance);

  /// No description provided for @alreadyStampedToday.
  ///
  /// In ja, this message translates to:
  /// **'今日はここでスタンプを押しました'**
  String get alreadyStampedToday;

  /// No description provided for @googleMapsAttributionLabel.
  ///
  /// In ja, this message translates to:
  /// **'場所の情報の出典：Google マップ'**
  String get googleMapsAttributionLabel;

  /// No description provided for @googleMapsNoticeLead.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチは Google マップの機能と内容を使っています。使うと、'**
  String get googleMapsNoticeLead;

  /// No description provided for @googleMapsTermsLink.
  ///
  /// In ja, this message translates to:
  /// **'Google マップ／Google Earth 追加利用規約'**
  String get googleMapsTermsLink;

  /// No description provided for @googleMapsNoticeAnd.
  ///
  /// In ja, this message translates to:
  /// **'と'**
  String get googleMapsNoticeAnd;

  /// No description provided for @googlePrivacyLink.
  ///
  /// In ja, this message translates to:
  /// **'Google プライバシー ポリシー'**
  String get googlePrivacyLink;

  /// No description provided for @googleMapsNoticeTail.
  ///
  /// In ja, this message translates to:
  /// **'に同意したものとみなされます。'**
  String get googleMapsNoticeTail;

  /// No description provided for @settingsAbout.
  ///
  /// In ja, this message translates to:
  /// **'このアプリについて'**
  String get settingsAbout;

  /// No description provided for @shareEntryMine.
  ///
  /// In ja, this message translates to:
  /// **'「{placeName}」に行きました！'**
  String shareEntryMine(String placeName);

  /// No description provided for @shareEntryOthers.
  ///
  /// In ja, this message translates to:
  /// **'ウラミチで見つけた「{placeName}」の口コミ'**
  String shareEntryOthers(String placeName);

  /// No description provided for @shareOtherApps.
  ///
  /// In ja, this message translates to:
  /// **'ほかのアプリ'**
  String get shareOtherApps;

  /// No description provided for @shareAction.
  ///
  /// In ja, this message translates to:
  /// **'シェア'**
  String get shareAction;

  /// No description provided for @shareSheetTitle.
  ///
  /// In ja, this message translates to:
  /// **'この記録をシェア'**
  String get shareSheetTitle;

  /// No description provided for @shareSheetTitleOthers.
  ///
  /// In ja, this message translates to:
  /// **'この口コミをシェア'**
  String get shareSheetTitleOthers;

  /// No description provided for @shareCardFooter.
  ///
  /// In ja, this message translates to:
  /// **'#ウラミチ'**
  String get shareCardFooter;

  /// No description provided for @reportSheetTitle.
  ///
  /// In ja, this message translates to:
  /// **'この口コミを報告'**
  String get reportSheetTitle;

  /// No description provided for @reportSheetHelp.
  ///
  /// In ja, this message translates to:
  /// **'報告したことは投稿した人に伝わりません。報告した口コミは、あなたのタイムラインからすぐに消えます。3人から報告されると、みんなのタイムラインからも見えなくなり、運営が内容を確かめます。'**
  String get reportSheetHelp;

  /// No description provided for @reportReasonInappropriate.
  ///
  /// In ja, this message translates to:
  /// **'不快な・攻撃的な内容'**
  String get reportReasonInappropriate;

  /// No description provided for @reportReasonUnrelated.
  ///
  /// In ja, this message translates to:
  /// **'場所と関係のない内容'**
  String get reportReasonUnrelated;

  /// No description provided for @reportReasonPersonal.
  ///
  /// In ja, this message translates to:
  /// **'個人情報が書かれている'**
  String get reportReasonPersonal;

  /// No description provided for @reportReasonSpam.
  ///
  /// In ja, this message translates to:
  /// **'宣伝・スパム'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonOther.
  ///
  /// In ja, this message translates to:
  /// **'そのほか'**
  String get reportReasonOther;

  /// No description provided for @reportNoteHint.
  ///
  /// In ja, this message translates to:
  /// **'くわしく（任意）'**
  String get reportNoteHint;

  /// No description provided for @reportSend.
  ///
  /// In ja, this message translates to:
  /// **'報告する'**
  String get reportSend;

  /// No description provided for @stampBookTotalUnit.
  ///
  /// In ja, this message translates to:
  /// **'個のスタンプ'**
  String get stampBookTotalUnit;

  /// No description provided for @stampBookKinds.
  ///
  /// In ja, this message translates to:
  /// **'集めた種類 {got} / {all}'**
  String stampBookKinds(int got, int all);

  /// No description provided for @stampBookMonthCount.
  ///
  /// In ja, this message translates to:
  /// **'{count}個'**
  String stampBookMonthCount(int count);

  /// No description provided for @achievementsViewAchievements.
  ///
  /// In ja, this message translates to:
  /// **'実績'**
  String get achievementsViewAchievements;

  /// No description provided for @achievementsViewStamps.
  ///
  /// In ja, this message translates to:
  /// **'スタンプ帳'**
  String get achievementsViewStamps;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
