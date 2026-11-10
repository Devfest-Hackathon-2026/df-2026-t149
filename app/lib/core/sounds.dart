import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 効果音の種類。音のファイルは scripts/make_sounds.py で作り、assets/sounds/ に同梱する
enum Sound {
  /// チェックインでチェックインスタンプを押したとき
  stamp('stamp.wav'),

  /// 実績を解除・昇格したとき
  unlock('unlock.wav'),

  /// ★を付けたとき
  star('star.wav'),

  /// お気に入りに入れたとき
  favorite('favorite.wav'),

  /// 保存できたとき
  success('success.wav'),

  /// 地図の主なボタンを押したとき
  tap('tap.wav');

  const Sound(this.file);
  final String file;
}

/// 効果音を鳴らす。
///
/// 設定の画面でオフにできる（[AppSettings.soundEnabled]）。オフのときは何もしない。
/// 端末のマナーモードでは鳴らさず、ほかのアプリの音楽を止めずに重ねて鳴らす（docs/decisions.md の D-031）。
/// [init] を呼ぶまでは何も鳴らさない。テストでは呼ばないので、音の機能のない環境でも動く
abstract final class Sounds {
  /// 鳴らすか。[AppSettings] が設定の値を入れる
  static bool enabled = true;

  static SoundBackend? _backend;

  /// 鳴らした音を記録する。テストで確かめるために使う
  @visibleForTesting
  static set backend(SoundBackend? value) => _backend = value;

  /// アプリの起動時に呼ぶ。音を読み込んでおき、押したときにすぐ鳴るようにする
  static Future<void> init() async {
    if (_backend != null) {
      return;
    }
    final AudioPlayersBackend backend = AudioPlayersBackend();
    _backend = backend;
    await backend.preload();
  }

  static Future<void> play(Sound sound) async {
    final SoundBackend? backend = _backend;
    if (!enabled || backend == null) {
      return;
    }
    try {
      await backend.play(sound);
    } catch (error) {
      // 鳴らせない端末でも、操作は続ける
      debugPrint('効果音を鳴らせません: $error');
    }
  }

  static Future<void> stamp() => play(Sound.stamp);
  static Future<void> unlock() => play(Sound.unlock);
  static Future<void> star() => play(Sound.star);
  static Future<void> favorite() => play(Sound.favorite);
  static Future<void> success() => play(Sound.success);
  static Future<void> tap() => play(Sound.tap);
}

/// 効果音を実際に鳴らす部分
abstract interface class SoundBackend {
  Future<void> play(Sound sound);
}

/// audioplayers で鳴らす。音ごとにプレイヤーを1つ持ち、読み込んだまま使い回す
class AudioPlayersBackend implements SoundBackend {
  final Map<Sound, AudioPlayer> _players = <Sound, AudioPlayer>{};

  /// マナーモードを守り、ほかのアプリの音を止めない
  static final AudioContext _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
    respectSilence: true,
  ).build();

  Future<void> preload() async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
    } catch (error) {
      debugPrint('効果音の設定をできません: $error');
    }
    for (final Sound sound in Sound.values) {
      try {
        await _player(sound);
      } catch (error) {
        debugPrint('効果音を読み込めません: ${sound.file} $error');
      }
    }
  }

  Future<AudioPlayer> _player(Sound sound) async {
    final AudioPlayer? existing = _players[sound];
    if (existing != null) {
      return existing;
    }
    final AudioPlayer player = AudioPlayer(playerId: 'sound-${sound.name}');
    _players[sound] = player;
    await player.setReleaseMode(ReleaseMode.stop);
    // 短い音は、遅れの少ない再生のしかたで鳴らす（Web にはないので通常の再生）
    if (!kIsWeb) {
      await player.setPlayerMode(PlayerMode.lowLatency);
    }
    await player.setSource(AssetSource('sounds/${sound.file}'));
    return player;
  }

  @override
  Future<void> play(Sound sound) async {
    final AudioPlayer player = await _player(sound);
    // 鳴っている途中でも、頭から鳴らし直す
    await player.stop();
    await player.resume();
  }
}
