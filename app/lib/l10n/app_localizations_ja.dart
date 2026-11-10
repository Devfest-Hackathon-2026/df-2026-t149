// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'ウラミチ';

  @override
  String get tabCheckin => 'チェックイン';

  @override
  String syncSentOne(Object placeName, Object order) {
    return '$placeNameは $order 人目でした';
  }

  @override
  String syncSentMany(Object count) {
    return '$count 件のチェックインを送信しました';
  }

  @override
  String syncRejected(Object rejected) {
    return '$rejected 件の記録を送信できませんでした';
  }

  @override
  String get startupFailedTitle => 'ログインを準備できませんでした';

  @override
  String get retry => 'もう一度試す';

  @override
  String shareTextPlace(Object placeName) {
    return '「$placeName」に';
  }

  @override
  String get shareTextCheckedIn => 'チェックインしました！';

  @override
  String shareTextCheckedInOrder(Object order) {
    return '$order人目の訪問者としてチェックインしました！';
  }

  @override
  String get shareTextFirst => '一番乗り🚩';

  @override
  String shareTextComment(Object c) {
    return '\n「$c」';
  }

  @override
  String get shareTextFooter => '\nみんなの知らない場所へ #ウラミチ';

  @override
  String get shareTargetX => '𝕏 に投稿';

  @override
  String get shareTargetLine => 'LINE で送る';

  @override
  String get errorLogIdUnknown => '送信済みの記録の ID がわかりません。一覧を読み直してから直してください';

  @override
  String get errorSaveLocal => '記録を端末に保存できませんでした。もう一度やり直してください';

  @override
  String get errorViewMessage => 'この部分を表示できませんでした';

  @override
  String get favoriteRemoved => 'お気に入りから外しました';

  @override
  String get favoriteAdded => 'お気に入りに追加しました';

  @override
  String favoriteAddedNamed(Object name) {
    return '「$name」をお気に入りに追加しました';
  }

  @override
  String get favoriteRemoveTooltip => 'お気に入りから外す';

  @override
  String get favoriteAddTooltip => 'お気に入りに入れる';

  @override
  String get zoomIn => '拡大';

  @override
  String get zoomOut => '縮小';

  @override
  String get zoomLever => 'ズームのレバー';

  @override
  String zoomLevel(Object value) {
    return 'ズーム $value';
  }

  @override
  String get mockData => 'ダミーデータ';

  @override
  String reviewCountLabel(Object value) {
    return 'レビュー $value件';
  }

  @override
  String get placeTypeArtGallery => '美術館';

  @override
  String get placeTypeBuddhistTemple => '寺';

  @override
  String get placeTypeCafe => 'カフェ';

  @override
  String get placeTypeCoffeeShop => 'コーヒー店';

  @override
  String get placeTypeCulturalCenter => '文化施設';

  @override
  String get placeTypeGarden => '庭園';

  @override
  String get placeTypeHikingArea => 'ハイキングコース';

  @override
  String get placeTypeMarket => '市場';

  @override
  String get placeTypeMuseum => '博物館';

  @override
  String get placeTypeObservationDeck => '展望台';

  @override
  String get placeTypePark => '公園';

  @override
  String get placeTypeRestaurant => '飲食店';

  @override
  String get placeTypeShrine => '神社';

  @override
  String get placeTypeShoppingMall => 'ショッピングモール';

  @override
  String get placeTypeStore => '店';

  @override
  String get placeTypeTeaHouse => '茶屋';

  @override
  String get placeTypeTouristAttraction => '観光名所';

  @override
  String placePhotosLabel(Object count) {
    return '場所の写真 $count枚';
  }

  @override
  String get photoCreditGoogle => '写真：Google マップ';

  @override
  String photoCreditAuthor(Object name) {
    return '写真：$name（Google マップ）';
  }

  @override
  String reviewCountBarLabel(Object value, Object value2) {
    return 'レビュー $value件、有名スポットは $value2件';
  }

  @override
  String get genreWorship => '寺社';

  @override
  String get genreFood => '飲食';

  @override
  String get genreNature => '公園';

  @override
  String get genreCulture => '美術館';

  @override
  String get genreView => '展望';

  @override
  String get genreShopping => '買い物';

  @override
  String stampLabel(Object caption, Object label) {
    return '$captionのチェックインスタンプ、$label';
  }

  @override
  String get stampFirst => '一番乗り';

  @override
  String starRatingLabel(Object value) {
    return '★$value';
  }

  @override
  String starInputLabel(Object i, Object value) {
    return '★$i、$value';
  }

  @override
  String get starInputPrompt => '★で評価してください';

  @override
  String get errorServerTimeout => 'サーバーから応答がありませんでした';

  @override
  String get errorServerUnreachable => 'サーバーに接続できませんでした';

  @override
  String get percentUnderOne => '1%未満';

  @override
  String get verdictHit => '当たり';

  @override
  String get verdictMiss => 'ハズレ';

  @override
  String get stars5 => '最高！';

  @override
  String get stars4 => 'よかった';

  @override
  String get stars3 => 'ふつう';

  @override
  String get stars2 => 'まあまあ';

  @override
  String get stars1 => '自分には合わなかった';

  @override
  String get titleUntrodden => '未踏';

  @override
  String get titleHidden => '穴場';

  @override
  String get titleKnown => '定番';

  @override
  String get titleFamous => '超有名';

  @override
  String get genreOther => 'その他';

  @override
  String get iconHiking => '歩く人';

  @override
  String get iconPets => '足あと';

  @override
  String get iconCafe => 'コーヒー';

  @override
  String get iconRamen => 'ラーメン';

  @override
  String get iconCamera => 'カメラ';

  @override
  String get iconBike => '自転車';

  @override
  String get iconTrain => '電車';

  @override
  String get iconLeaf => '葉っぱ';

  @override
  String get iconMountain => '山';

  @override
  String get iconWaves => '波';

  @override
  String get iconTemple => 'お寺';

  @override
  String get iconTree => '木';

  @override
  String get errorProfileLoad => 'プロフィールを読み込めませんでした。通信状況を確認して、もう一度お試しください';

  @override
  String get errorLoginPopup => 'ログインの画面を開けませんでした。ブラウザでポップアップを許可して、もう一度お試しください';

  @override
  String get errorLoginNetwork => 'ログインできませんでした。通信状況を確認して、もう一度お試しください';

  @override
  String errorLoginCode(Object code) {
    return 'ログインできませんでした（$code）。もう一度お試しください';
  }

  @override
  String get errorGeneric => 'エラーが起きました';

  @override
  String get errorLoginRequired => 'ログインしてからやり直してください';

  @override
  String shareOpenFailed(Object label) {
    return '$label画面を開けませんでした';
  }

  @override
  String get shareImageFailed => '画像を作れませんでした';

  @override
  String get shareInstagramHint =>
      '共有の画面で Instagram を選んでください。文はコピーしたので、投稿で貼り付けられます';

  @override
  String get shareSheetFailed => '共有の画面を開けませんでした';

  @override
  String get shareTextCopied => 'シェアする文をコピーしました';

  @override
  String get celebrationTitle => 'チェックイン完了';

  @override
  String get close => '閉じる';

  @override
  String get stampRecorded => '記録';

  @override
  String orderLabel(Object order) {
    return '$order人目';
  }

  @override
  String get stampRevisit => 'また来た';

  @override
  String get stampFirstVisit => 'はじめて';

  @override
  String get hashtag => '#ウラミチ';

  @override
  String get checkinPendingOrder => '通信できるようになってから、データを照合して何人目かが決定されます';

  @override
  String quotedComment(Object comment) {
    return '「$comment」';
  }

  @override
  String get secretAchievementUnlocked => 'シークレット実績を解除！';

  @override
  String get achievementUnlocked => '実績を解除！';

  @override
  String get shareHeading => 'みんなに教える';

  @override
  String get shareInstagram => 'Instagram で共有';

  @override
  String get shareCopyText => 'テキストをコピー';

  @override
  String get findNextPlace => '次の場所を探す';

  @override
  String conditionPending(Object label) {
    return '$label、まだ探していません';
  }

  @override
  String get logEdited => '記録を修正しました';

  @override
  String logEditFailed(Object value) {
    return '修正できませんでした：$value';
  }

  @override
  String get editLog => '記録を修正';

  @override
  String get placeNameUnavailable => '場所の名前を表示できません';

  @override
  String get comment => 'ひとこと';

  @override
  String get saving => '保存しています…';

  @override
  String get save => '保存';

  @override
  String get place => '場所';

  @override
  String get openMapsFailed => 'Google マップを開けませんでした';

  @override
  String dateTimeFull(
    Object year,
    Object month,
    Object day,
    Object hour,
    Object value,
  ) {
    return '$year年$month月$day日 $hour:$value';
  }

  @override
  String get placeNameLimitReached =>
      '今日の名前の読み込みの上限に達したため、名前を出せませんでした。Google マップでは開けます';

  @override
  String get noComment => 'ひとことはありません';

  @override
  String get myLog => '自分の記録';

  @override
  String get anonymousTraveler => '名前のない旅人';

  @override
  String visitorOrder(Object n) {
    return '$n 人目の訪問者';
  }

  @override
  String get openInGoogleMaps => 'Google マップで開く';

  @override
  String get findAlternatives => '代わりを探す';

  @override
  String get idleTitle => 'このあたりの穴場を探す';

  @override
  String get idleMessage => '地図を動かして、探す場所を決めましょう';

  @override
  String findAlternativesFor(Object query) {
    return '「$query」の代わりを探す';
  }

  @override
  String get searchThisArea => 'このエリアを探す';

  @override
  String get searchNearby => '近くを探す';

  @override
  String get exploreFar => '遠くを調べる';

  @override
  String get farRegion => '遠くの地域';

  @override
  String get nearCurrentLocation => '現在地の近く';

  @override
  String get nearMapCenter => '地図の中心の近く';

  @override
  String get searchNearbyNoLocation => '現在地が分からないため、地図の中心の近くを探します';

  @override
  String get searchNearbyLocationFailed => '現在地を測定できなかったため、地図の中心の近くを探します';

  @override
  String get movedToMockPlace => 'ダミーデータの地点へ移動しました';

  @override
  String resultCount(Object count) {
    return '穴場 $count 件';
  }

  @override
  String get searching => '探しています';

  @override
  String get results => '結果';

  @override
  String get collapseList => '一覧を畳む';

  @override
  String get expandList => '一覧を開く';

  @override
  String get searchWithConditions => 'この条件で探す';

  @override
  String get assistantName => 'Geminiちゃん';

  @override
  String get locationServiceOff => '端末の位置情報がオフです';

  @override
  String get locationDenied => '位置情報が許可されていません';

  @override
  String get openSettings => '設定を開く';

  @override
  String get locationFailed => '現在地を測定できませんでした';

  @override
  String get locationDeniedBrowser =>
      'ブラウザで位置情報が許可されていません。アドレスバーの左のマークから許可できます';

  @override
  String get goToMyLocation => '現在地へ移動';

  @override
  String get searchPlaceHint => '場所を検索';

  @override
  String get search => '検索';

  @override
  String get clearSearch => '検索を消す';

  @override
  String get sortBalanced => 'おすすめ順';

  @override
  String get sortBalancedDescription => '知られていなさ・近さ・評判のよさで並べる';

  @override
  String get sortObscure => '穴場順';

  @override
  String get sortObscureDescription => '口コミの少ない、知られていない場所から';

  @override
  String get sortNear => '近い順';

  @override
  String get sortNearDescription => '今いる場所（探した地点）から近い順';

  @override
  String get currentLocation => '現在地';

  @override
  String get mapCenter => '地図の中心';

  @override
  String get searchingNearby => '周辺の場所を探しています';

  @override
  String get notFound => '見つかりませんでした';

  @override
  String get widenRange => '範囲を広げる';

  @override
  String get noPlacesForPopularity => 'この人気度の場所はありません';

  @override
  String get showFamousPlaces => '有名な場所も見る';

  @override
  String get staleConditions => '条件を変更しました。前の条件の結果を表示しています';

  @override
  String get staleMoved => '地図を動かしました。前の条件の結果を表示しています';

  @override
  String get searchAgain => '再検索する';

  @override
  String get popularityHelp => '左ほど知られていない場所、右ほど有名な場所です';

  @override
  String radiusWide(Object value) {
    return '$value（広い範囲）';
  }

  @override
  String radiusLabel(Object value) {
    return '半径 $value';
  }

  @override
  String get popularity => '人気度';

  @override
  String popularityLabel(Object value) {
    return '人気度：$value';
  }

  @override
  String get favorites => 'お気に入り';

  @override
  String popularityRange(Object lo, Object hi) {
    return '$lo〜$hi';
  }

  @override
  String get appliedOnSearch => '再検索して反映';

  @override
  String get tabTimeline => 'タイムライン';

  @override
  String get nearby => 'みんな';

  @override
  String get noLogsYet => 'まだ記録がありません';

  @override
  String get publicToggleToPrivate => '公開中です。押すと非公開に';

  @override
  String get publicToggleToPublic => '非公開です。押すと公開されます';

  @override
  String get unsent => '未送信';

  @override
  String get reported => '報告しました';

  @override
  String get timelineAreaNearby => '周辺';

  @override
  String get timelineAreaNationwide => '全国の新着';

  @override
  String get timelineNationwideNote => '全国で公開された口コミを、新しい順に見ています';

  @override
  String get timelineToday => '今日';

  @override
  String get timelineYesterday => '昨日';

  @override
  String timelineDate(int month, int day, String weekday) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      '1': '月',
      '2': '火',
      '3': '水',
      '4': '木',
      '5': '金',
      '6': '土',
      'other': '日',
    });
    return '$month月$day日（$_temp0）';
  }

  @override
  String timelineDateWithYear(int year, int month, int day, String weekday) {
    String _temp0 = intl.Intl.selectLogic(weekday, {
      '1': '月',
      '2': '火',
      '3': '水',
      '4': '木',
      '5': '金',
      '6': '土',
      'other': '日',
    });
    return '$year年$month月$day日（$_temp0）';
  }

  @override
  String get noNearbyLogs => 'この辺りで公開された記録はまだありません';

  @override
  String get reportLog => 'この記録を報告';

  @override
  String get author => '投稿者';

  @override
  String visitorOrderShort(Object order) {
    return '$order 人目';
  }

  @override
  String get howWasIt => '行ってみてどうでしたか？';

  @override
  String get visibilityPrivate => '非公開';

  @override
  String get visibilityPublic => '一般公開';

  @override
  String get record => '記録する';

  @override
  String get stampPending => '送信待ち';

  @override
  String get tabMap => '地図';

  @override
  String get tabAchievements => '実績';

  @override
  String ratingSummaryLabel(Object value, Object count) {
    return '★$value、$count件の評価';
  }

  @override
  String ratingCount(Object count) {
    return '（$count件）';
  }

  @override
  String get noFavoritesYet => 'お気に入りはまだありません';

  @override
  String get noFavoritesMessage => '場所の詳細や一覧のハートを押すとここにまとまります。';

  @override
  String get placeNameLoadFailed => '場所の名前を読み込めません';

  @override
  String get placeMaybeClosed => '閉業したか、通信できなかった可能性があります';

  @override
  String get assistantPromptQuiet => '近くの静かな穴場を教えて';

  @override
  String get assistantPromptCafe => '落ち着けるカフェはある？';

  @override
  String get assistantPromptView => '景色のいい穴場';

  @override
  String get assistantPromptNightView => '夜景がきれいなところ';

  @override
  String get assistantPromptOtherGenre => 'ほかのジャンルだと？';

  @override
  String get assistantPromptWorship => '寺社に絞って';

  @override
  String get assistantPromptPark => '公園でのんびりしたい';

  @override
  String get assistantGreeting =>
      'どんな場所を探しますか？地図の中心のまわりから、まだあまり知られていない場所を選びます。';

  @override
  String get assistantSubtitle => 'Gemini が穴場探しをお手伝いします';

  @override
  String get assistantSimpleMode => 'デモモードで答えています';

  @override
  String get assistantRestart => '最初から';

  @override
  String get assistantThinking => '考えています';

  @override
  String get assistantThinkingEllipsis => '考えています…';

  @override
  String get assistantShowOnMap => 'おすすめを地図に出す';

  @override
  String get assistantTargetsTitle => '見つかった場所';

  @override
  String get assistantHiddenNearbyTitle => 'そばの穴場';

  @override
  String get assistantTargetReason => '探していた場所です';

  @override
  String assistantMoveTo(Object name) {
    return '$nameへ移動';
  }

  @override
  String get assistantSearchHere => '地図でこのあたりを探す';

  @override
  String assistantExploreWide(Object name) {
    return '$nameを広い範囲で探す';
  }

  @override
  String get assistantMoreAlternatives => '代わりをもっと見る';

  @override
  String get assistantInputHint => 'Geminiちゃんに話しかける';

  @override
  String get send => '送る';

  @override
  String get achievementUnlockedShort => '解除！';

  @override
  String achievementPromoted(Object label) {
    return '$labelに昇格！';
  }

  @override
  String achievementTierEarned(Object label) {
    return '$labelを獲得！';
  }

  @override
  String achievementTierShare(Object value, Object p) {
    return '$valueは全体の $p';
  }

  @override
  String achievementShare(Object p) {
    return '全体の $p が解除';
  }

  @override
  String get hiddenTitle => '？？？';

  @override
  String get secret => 'シークレット';

  @override
  String achievementHint(Object hint) {
    return 'ヒント：$hint';
  }

  @override
  String achievementUnlockedOn(Object value) {
    return '$value に解除';
  }

  @override
  String achievementUnlockedAt(Object value, Object place) {
    return '$value に「$place」で解除';
  }

  @override
  String achievementSharePercent(Object value) {
    return '全体の $value';
  }

  @override
  String achievementNextTier(Object value, Object value2) {
    return '$valueまであと $value2';
  }

  @override
  String achievementRemaining(Object value) {
    return 'あと $value';
  }

  @override
  String get achievementCongrats => 'やったね';

  @override
  String get tierBronze => 'ブロンズ';

  @override
  String get tierSilver => 'シルバー';

  @override
  String get tierGold => 'ゴールド';

  @override
  String get rarityCommon => 'ふつう';

  @override
  String get rarityRare => 'レア';

  @override
  String get rarityEpic => 'すごくレア';

  @override
  String get rarityLegend => '伝説';

  @override
  String get achFirstStepTitle => 'はじめの一歩';

  @override
  String get achFirstStepDescription => '思い出ログを1件残す';

  @override
  String get achFirstStepDetail => 'すべてはここから。知られていない場所へ行き、思い出を1件残しましょう。';

  @override
  String get achPioneerTitle => '開拓者';

  @override
  String get achPioneerDescription => '{n}か所で1人目の訪問者になる';

  @override
  String get achPioneerDetail => 'ウラミチで誰もチェックインしていない場所に、最初に足跡を残しました。';

  @override
  String get achVeteranTitle => '古参の風格';

  @override
  String get achVeteranDescription => '10人目までの訪問者として{n}か所を記録する';

  @override
  String get achVeteranDetail => '流行る前から知っていた。そう言える場所を持っています。';

  @override
  String get achHonorableMissTitle => '名誉のハズレ';

  @override
  String get achHonorableMissDescription => '★1か★2の記録を1件残す';

  @override
  String get achHonorableMissDetail => 'ハズレも立派な開拓です。誰かが同じ道で迷わずに済みます。';

  @override
  String get achConnoisseurTitle => '目利き';

  @override
  String get achConnoisseurDescription => '★4以上の記録を{n}件残す';

  @override
  String get achConnoisseurDetail => '良い場所を見つける目を持っています。';

  @override
  String get achPerfectViewTitle => '満点の景色';

  @override
  String get achPerfectViewDescription => '★5の記録を{n}件残す';

  @override
  String get achPerfectViewDetail => '心から「最高！」と言える場所に何度も出会いました。';

  @override
  String get achWalkTitle => 'ウラミチ散歩';

  @override
  String get achWalkDescription => '{n}か所を記録する（同じ場所は1回）';

  @override
  String get achWalkDetail => '気の向くままに歩いて、地図の余白をあなたの記録が埋めていきます。';

  @override
  String get achRegularTitle => 'ウラミチ常連';

  @override
  String get achRegularDescription => '思い出ログを{n}件残す';

  @override
  String get achRegularDetail =>
      '記録を重ねるほど、街の見え方が変わってきます。ゴールドまで来れば、あなた自身がウラミチです。';

  @override
  String get achConsistentTitle => '三日坊主じゃない';

  @override
  String get achConsistentDescription => '{n}日に分けて記録する';

  @override
  String get achConsistentDetail => '1日だけの思いつきではありません。続けて歩いています。';

  @override
  String get achCommenterTitle => 'ひとこと名人';

  @override
  String get achCommenterDescription => 'ひとことを添えて{n}件記録する';

  @override
  String get achCommenterDetail => '短い言葉が、次に行く誰かの道しるべになります。';

  @override
  String get achStorytellerTitle => '語り部';

  @override
  String get achStorytellerDescription => '記録を{n}件タイムラインに公開する';

  @override
  String get achStorytellerDetail => 'あなたの発見が、周りのみんなのタイムラインに届いています。';

  @override
  String get achSoCloseTitle => '惜しい！';

  @override
  String get achSoCloseDescription => 'その場所の2人目の訪問者になる';

  @override
  String get achSoCloseDetail => 'あと一歩で開拓者でした。でも2人目も十分に古参です。';

  @override
  String get achSoCloseHint => 'あと少しで一番乗り……';

  @override
  String get achRoundNumberTitle => 'キリ番ゲッター';

  @override
  String get achRoundNumberDescription => '10の倍数の番目の訪問者になる';

  @override
  String get achRoundNumberDetail => '10人目、20人目……ちょうどの数字を踏みました。';

  @override
  String get achRoundNumberHint => '何人目かの数字に注目';

  @override
  String get achNightOwlTitle => '夜ふかし探検家';

  @override
  String get achNightOwlDescription => '0時から4時の間に記録する';

  @override
  String get achNightOwlDetail => 'みんなが眠っている時間にも、ウラミチは開いています。';

  @override
  String get achNightOwlHint => '月が見ている時間に';

  @override
  String get achEarlyBirdTitle => '朝活の達人';

  @override
  String get achEarlyBirdDescription => '5時から7時の間に記録する';

  @override
  String get achEarlyBirdDetail => '人の少ない朝の街は、いつもと違う顔を見せます。';

  @override
  String get achEarlyBirdHint => '早起きは三文の徳';

  @override
  String get achHopperTitle => 'はしご旅';

  @override
  String get achHopperDescription => '1日に3か所を記録する';

  @override
  String get achHopperDetail => '次から次へ。今日は寄り道の多い一日でした。';

  @override
  String get achHopperHint => '一日に、いくつ回れる？';

  @override
  String get achWeekendTitle => '週末冒険家';

  @override
  String get achWeekendDescription => '土日に5件記録する';

  @override
  String get achWeekendDetail => '休みの日は、知らない場所へ。';

  @override
  String get achWeekendHint => '休みの日の過ごし方';

  @override
  String get achTalkativeTitle => '語りすぎ';

  @override
  String get achTalkativeDescription => '100文字以上のひとことを残す';

  @override
  String get achTalkativeDetail => 'ひとことのはずが、ひとことでは収まりませんでした。';

  @override
  String get achTalkativeHint => 'ひとこと、とは';

  @override
  String get achRevisitTitle => 'また来ちゃった';

  @override
  String get achRevisitDescription => '同じ場所を3回記録する';

  @override
  String get achRevisitDetail => 'ここはもう、あなたの行きつけです。';

  @override
  String get achRevisitHint => '気に入った場所はありますか';

  @override
  String get almostUnlocked => 'もう少しで解除';

  @override
  String get noUnlockedAchievements => 'まだ解除した実績はありません。チェックインして思い出ログを残してみましょう';

  @override
  String get allAchievementsUnlocked => 'すべての実績を解除しました！';

  @override
  String secretAchievementCount(Object secretUnlocked, Object secretTotal) {
    return 'シークレット実績　$secretUnlocked / $secretTotal';
  }

  @override
  String get secretAchievementHelp => '条件は解除するまでわかりません。タップするとヒントが見られます。';

  @override
  String get filterAll => 'すべて';

  @override
  String get filterUnlocked => '解除済み';

  @override
  String get filterLocked => '未解除';

  @override
  String almostTileLabel(Object title, Object left) {
    return '$title、あと$left';
  }

  @override
  String unlockedOfTotal(Object total) {
    return '/ $total 解除';
  }

  @override
  String get achievementsEmptyHelp => 'チェックインして思い出ログを残すと、実績が増えていきます。';

  @override
  String achievementTileUnlocked(Object title) {
    return '$title、解除済み';
  }

  @override
  String achievementTileUnlockedTier(Object title, Object tier) {
    return '$title、解除済み、$tier';
  }

  @override
  String achievementTileLocked(Object title) {
    return '$title、未解除';
  }

  @override
  String achievementAllTiersOn(Object year, Object month, Object day) {
    return '$year/$month/$day にすべての段階を達成';
  }

  @override
  String achievementUnlockedOnDate(Object year, Object month, Object day) {
    return '$year/$month/$day に解除';
  }

  @override
  String get directions => '道順';

  @override
  String get reviews => 'レビュー';

  @override
  String get uramichiVisitors => 'ウラミチで来た人';

  @override
  String get distance => '距離';

  @override
  String distanceFrom(Object name) {
    return '$nameから';
  }

  @override
  String get iWasHere => 'ここに来た！';

  @override
  String get start => 'はじめる';

  @override
  String get reload => 'もう一度読み込む';

  @override
  String get logout => 'ログアウト';

  @override
  String get loginPrivacy =>
      '他のユーザーには、アプリ内で設定したニックネームとアイコン、一般公開に設定した記録のみが表示されます';

  @override
  String get appTagline => '逆張り観光アプリ';

  @override
  String get appLead => '有名スポットの代わりに、まだ知られていない場所へ。';

  @override
  String get loginFeatureSearch => '口コミの少ない穴場を地図から探す';

  @override
  String get loginFeatureStamp => '行った場所でチェックインスタンプを集める';

  @override
  String get loginFeatureBadge => '歩いた記録が実績のバッジに';

  @override
  String get loggingIn => 'ログインしています';

  @override
  String get loginWithGoogle => 'Google でログイン';

  @override
  String get errorProfileSave => 'プロフィールを保存できませんでした。通信状況を確認して、もう一度お試しください';

  @override
  String get profile => 'プロフィール';

  @override
  String get nickname => 'ニックネーム';

  @override
  String get nicknameHint => '例：路地裏の旅人';

  @override
  String get nicknameHelper => 'タイムラインに表示されます';

  @override
  String nicknameTooLong(Object nicknameMaxLength) {
    return '$nicknameMaxLength文字までです';
  }

  @override
  String get icon => 'アイコン';

  @override
  String get regionPickerLead => 'まだあまり知られていない地域を、のんびり歩いてみませんか？';

  @override
  String get regionSearchHint => '地名で調べる（例：飛騨高山）';

  @override
  String get regionSearch => '調べる';

  @override
  String get regionPairsHeading => '次の旅の候補に';

  @override
  String get regionAreasHeading => '地方から選ぶ';

  @override
  String regionPairLabel(Object name) {
    return '$nameに行ったことがあるなら';
  }

  @override
  String get settings => '設定';

  @override
  String get settingsAppearance => '見た目';

  @override
  String get settingsTheme => 'テーマ';

  @override
  String get themeSystem => '自動';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get settingsKeyColor => 'キーカラー';

  @override
  String get settingsMotionSound => '動きと音';

  @override
  String get settingsHaptics => '振動（ハプティクス）';

  @override
  String get settingsHapticsDescription => '★を付けたときやチェックインしたときなどに、端末を振動させる';

  @override
  String get settingsSound => '効果音';

  @override
  String get settingsSoundDescription =>
      'チェックインや実績の解除のときに音を鳴らす。マナーモードのときは鳴らさない';

  @override
  String get settingsData => 'データ';

  @override
  String get settingsDemoData => 'デモデータで動かす';

  @override
  String get settingsEndpoint => '接続先';

  @override
  String get none => 'なし';

  @override
  String get colorWallpaper => '壁紙から自動設定';

  @override
  String get colorOther => 'ほかの色';

  @override
  String get hue => '色相';

  @override
  String get brightness => '明るさ';

  @override
  String get useThisColor => 'この色にする';

  @override
  String searchingAlternatives(Object query) {
    return '「$query」の代わりを探しています';
  }

  @override
  String originNotFound(Object query) {
    return '「$query」が見つかりませんでした';
  }

  @override
  String get searchAnotherName => '別の名前で探す';

  @override
  String get alternativesLoadFailed => '候補を読み込めませんでした';

  @override
  String get noAlternativesNearby => '近くに代わりの場所が見つかりませんでした';

  @override
  String get alternativesTitle => '代わりに行くなら\nここ';

  @override
  String get famousSpotHint => '有名スポットの名前';

  @override
  String get clearInput => '入力を消す';

  @override
  String sameGenre(Object label) {
    return '同じ$label';
  }

  @override
  String reviewRatio(Object value) {
    return 'レビュー 1/$value';
  }

  @override
  String get onlyZeroReviews => 'レビュー 0件の場所だけ';

  @override
  String reviewRatioOrLess(Object value) {
    return 'レビュー 1/$value 以下';
  }

  @override
  String get otherCandidates => 'ほかの候補';

  @override
  String candidateCount(Object count) {
    return '  $count件';
  }

  @override
  String get here => 'ここ';

  @override
  String countLabel(Object value) {
    return '$value件';
  }

  @override
  String get badgePioneer => '開拓者バッジ（最初の訪問者）';

  @override
  String badgeVeteran(Object order) {
    return '古参バッジ（$order 人目）';
  }

  @override
  String get badgePioneerShort => '開拓者';

  @override
  String get badgeHonorableMiss => '名誉のハズレ';

  @override
  String get badgeRegular => 'ウラミチ常連';

  @override
  String get reloadLocation => '現在地を読み直す';

  @override
  String unsentCount(Object pending) {
    return '未送信 $pending 件';
  }

  @override
  String get checkingLocation => '現在地を確認しています';

  @override
  String get searchingSpots => '近くのスポットを探しています';

  @override
  String get locationCheckFailed => '現在地を確認できませんでした';

  @override
  String get findOnMap => '地図で探す';

  @override
  String get noSpotsNearby => '近くにスポットがありません';

  @override
  String get searchAgainShort => 'もう一度探す';

  @override
  String get offline => '通信できません';

  @override
  String get offlineRecordHelp => '今の場所を記録すると、通信できるようになってからスポットを選択できます';

  @override
  String get recordHere => '今の場所を記録';

  @override
  String get spotLimitReached => '今日はこれ以上、近くのスポットを探せません';

  @override
  String get spotLimitHelp => '地図で場所を探して、詳細の画面からチェックインできます。明日になると、また近くを探せます';

  @override
  String get recordedHere => '今の場所を記録しました';

  @override
  String get allowLocation => '位置情報を許可';

  @override
  String distanceOffline(Object value) {
    return '$value m・オフライン';
  }

  @override
  String get details => '詳細';

  @override
  String placeDetailsTooltip(Object name) {
    return '$nameの詳細';
  }

  @override
  String get possibleVisits => '行ったかもしれない場所';

  @override
  String get skipThisTime => '今回はチェックインしない';

  @override
  String get neverSuggestPlace => 'この場所を今後提案しない';

  @override
  String get positionRecorded => '位置を記録しました';

  @override
  String get searchingSpotsShort => 'スポットを探しています…';

  @override
  String get spotsLoadFailed => 'スポットを読み込めませんでした';

  @override
  String get skipCheckin => 'チェックインしない';

  @override
  String get findSpots => 'スポットを探す';

  @override
  String get changePlace => '場所を変更';

  @override
  String timeRange(Object start, Object value) {
    return '$start〜$value';
  }

  @override
  String get recordStaysTitle => '滞在した場所を記録しますか？';

  @override
  String get doNotRecord => '記録しない';

  @override
  String get recordStays => '滞在した場所を記録';

  @override
  String mapPinLabel(Object name, Object value, Object value2) {
    return '$name、$value、レビュー $value2件';
  }

  @override
  String mapPinLabelNoReviews(Object name, Object value) {
    return '$name、$value';
  }

  @override
  String recentUnlock(Object title, Object month, Object day) {
    return '最近の解除：$title（$month/$day）';
  }

  @override
  String recordStaysMessage(Object inMinutes) {
    return '同じ場所に $inMinutes 分以上いる場合に、この端末に位置と時刻を記録し、あとからチェックインすることができます。アプリを閉じていても記録するために、アプリの位置情報の権限では「常に許可」を選んでください。スポットを探すときのみ、位置をサーバーに送信します。';
  }

  @override
  String distanceToPlace(Object value, Object value2) {
    return 'この場所まで $value あります。$value2 以内でチェックインできます';
  }

  @override
  String get settingsDemoDataDescription =>
      'オンのあいだは架空の場所だけを使い、サーバーにも Google にも問い合わせません。オフのときはデモデータを使いません';

  @override
  String get photoLabel => '記録の写真';

  @override
  String get photoUnavailable => '写真を読み込めません';

  @override
  String get photoUnsupported => 'JPEG、PNG、WebP の写真を選んでください';

  @override
  String get photoTooLarge => '写真が大きすぎます。ほかの写真を選んでください';

  @override
  String get photoPickFailed => '写真を選べませんでした';

  @override
  String get photoTake => '写真を撮る';

  @override
  String get photoChoose => '写真を選ぶ';

  @override
  String get photoAdd => '写真を添える';

  @override
  String get photoRemove => '写真を外す';

  @override
  String get photoUploadFailed => '写真を送れなかったので、写真なしで残しました';

  @override
  String get reactionWant => '行ってみたい';

  @override
  String get reactionHelpful => '参考になった';

  @override
  String get reactionFailed => '反応を送れませんでした。もう一度お試しください';

  @override
  String reactionCount(String label, int count) {
    return '$label $count件';
  }

  @override
  String stampBookTitle(int count) {
    return 'スタンプ帳（$count個）';
  }

  @override
  String get stampBookAll => 'すべて見る';

  @override
  String get stampBookEmpty => 'チェックインすると、場所の種類ごとのスタンプがここにたまります';

  @override
  String stampBookDate(int month, int day) {
    return '$month/$day';
  }

  @override
  String stampBookMonth(int year, int month) {
    return '$year年$month月';
  }

  @override
  String stampBookKindCount(String kind, int count) {
    return '$kind $count';
  }

  @override
  String stampBookStampLabel(String place, int month, int day) {
    return '$placeのスタンプ（$month月$day日）';
  }

  @override
  String get notifyStayTitle => 'ここで少しゆっくりしましたか？';

  @override
  String get notifyStayBody => 'アプリを開くと、いまいる場所にチェックインしてスタンプを押せます';

  @override
  String get notifyStayChannel => '滞在の知らせ';

  @override
  String notifyReactionsBody(int count) {
    return 'あなたの口コミに新しい反応が$count件あります';
  }

  @override
  String get notifyReactionsOpen => '見る';

  @override
  String get settingsNotifications => '通知';

  @override
  String get settingsNotificationsDescription =>
      '同じ場所にしばらくいたときと、口コミに反応があったときに知らせます';

  @override
  String get settingsNotificationsWeb => 'Web 版では、口コミへの反応をアプリを開いたときに画面の中で知らせます';

  @override
  String get notificationsDenied => '通知が許可されていません。端末の設定から許可できます';

  @override
  String get pressToStamp => '押してスタンプ';

  @override
  String pressToStampAt(String place) {
    return '$placeで押してスタンプ';
  }

  @override
  String get pressStampShort => '押す';

  @override
  String get pressLater => '後から押す';

  @override
  String get hereQuestion => 'いま、ここにいますか？';

  @override
  String get whereAreYou => 'いまいる場所を選んでください';

  @override
  String otherPlaces(int count) {
    return 'ちがう場所？（近くにあと$countか所）';
  }

  @override
  String get findAroundOnMap => '地図で周りを探す';

  @override
  String get journeyTitle => '今日の旅';

  @override
  String journeySummary(int count) {
    return 'スタンプ $count 個';
  }

  @override
  String get journeyEmpty => '今日はまだスタンプがありません。着いた場所で、上のスタンプを押してみましょう';

  @override
  String journeyStay(int minutes) {
    return '押し忘れ？ ここに$minutes分いました';
  }

  @override
  String get journeyStayShort => '押し忘れ？ ここにいました';

  @override
  String mapHereTitle(String place) {
    return 'いま「$place」の近くにいます';
  }

  @override
  String get mapHereSubtitle => '押すとスタンプを押して記録できます';

  @override
  String get detailStampTitle => 'ここで押してスタンプ';

  @override
  String detailStampHelp(String range) {
    return '$range以内に着いたら押せます';
  }

  @override
  String typeAndDistance(String type, String distance) {
    return '$type・$distance';
  }

  @override
  String get alreadyStampedToday => '今日はここでスタンプを押しました';

  @override
  String get googleMapsAttributionLabel => '場所の情報の出典：Google マップ';

  @override
  String get googleMapsNoticeLead => 'ウラミチは Google マップの機能と内容を使っています。使うと、';

  @override
  String get googleMapsTermsLink => 'Google マップ／Google Earth 追加利用規約';

  @override
  String get googleMapsNoticeAnd => 'と';

  @override
  String get googlePrivacyLink => 'Google プライバシー ポリシー';

  @override
  String get googleMapsNoticeTail => 'に同意したものとみなされます。';

  @override
  String get settingsAbout => 'このアプリについて';

  @override
  String shareEntryMine(String placeName) {
    return '「$placeName」に行きました！';
  }

  @override
  String shareEntryOthers(String placeName) {
    return 'ウラミチで見つけた「$placeName」の口コミ';
  }

  @override
  String get shareOtherApps => 'ほかのアプリ';

  @override
  String get shareAction => 'シェア';

  @override
  String get shareSheetTitle => 'この記録をシェア';

  @override
  String get shareSheetTitleOthers => 'この口コミをシェア';

  @override
  String get shareCardFooter => '#ウラミチ';

  @override
  String get reportSheetTitle => 'この口コミを報告';

  @override
  String get reportSheetHelp =>
      '報告したことは投稿した人に伝わりません。報告した口コミは、あなたのタイムラインからすぐに消えます。3人から報告されると、みんなのタイムラインからも見えなくなり、運営が内容を確かめます。';

  @override
  String get reportReasonInappropriate => '不快な・攻撃的な内容';

  @override
  String get reportReasonUnrelated => '場所と関係のない内容';

  @override
  String get reportReasonPersonal => '個人情報が書かれている';

  @override
  String get reportReasonSpam => '宣伝・スパム';

  @override
  String get reportReasonOther => 'そのほか';

  @override
  String get reportNoteHint => 'くわしく（任意）';

  @override
  String get reportSend => '報告する';

  @override
  String get stampBookTotalUnit => '個のスタンプ';

  @override
  String stampBookKinds(int got, int all) {
    return '集めた種類 $got / $all';
  }

  @override
  String stampBookMonthCount(int count) {
    return '$count個';
  }

  @override
  String get achievementsViewAchievements => '実績';

  @override
  String get achievementsViewStamps => 'スタンプ帳';
}
