import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../playback/loudness.dart';
import 'models.dart';

/// Preferencias de la app (mismas que la versión Kotlin, menos las de Android solamente).
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.maxVideoHeight = 1080,
    this.preferredOutput = OutputKind.mp4,
    this.mp3BitrateKbps = 192,
    this.maxConcurrentDownloads = 2,
    this.autoplayNext = true,
    this.saveHistory = true,
    this.mixtapeEnabled = true,
    this.mixtapeMax = 100,
    this.mixtapeWifiOnly = true,
    this.loudnessMode = LoudnessMode.normal,
    this.boostQuiet = false,
  });

  final ThemeMode themeMode;

  /// Calidad máxima para descargar y ver (null = la mejor disponible).
  final int? maxVideoHeight;
  final OutputKind preferredOutput;
  final int mp3BitrateKbps;
  final int maxConcurrentDownloads;
  final bool autoplayNext;
  final bool saveHistory;

  /// Guardar el audio de lo que escuchas (más de 30 s) para oírlo sin internet.
  final bool mixtapeEnabled;

  /// Canciones máximas del mixtape; al pasarse se borran las más antiguas guardadas solas.
  final int mixtapeMax;

  /// Solo guardar con Wi-Fi (para no gastar datos).
  final bool mixtapeWifiOnly;

  /// Volumen parejo entre canciones (como YouTube).
  final LoudnessMode loudnessMode;

  /// Subir también las canciones bajas (solo Android: LoudnessEnhancer).
  final bool boostQuiet;

  static const mixtapeSizes = [25, 50, 100, 200, 500];
  static const mp3Bitrates = [128, 192, 256, 320];
  static const heights = [null, 1080, 720, 480, 360];

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? maxVideoHeight,
    bool clearMaxHeight = false,
    OutputKind? preferredOutput,
    int? mp3BitrateKbps,
    int? maxConcurrentDownloads,
    bool? autoplayNext,
    bool? saveHistory,
    bool? mixtapeEnabled,
    int? mixtapeMax,
    bool? mixtapeWifiOnly,
    LoudnessMode? loudnessMode,
    bool? boostQuiet,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        maxVideoHeight: clearMaxHeight ? null : (maxVideoHeight ?? this.maxVideoHeight),
        preferredOutput: preferredOutput ?? this.preferredOutput,
        mp3BitrateKbps: mp3BitrateKbps ?? this.mp3BitrateKbps,
        maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
        autoplayNext: autoplayNext ?? this.autoplayNext,
        saveHistory: saveHistory ?? this.saveHistory,
        mixtapeEnabled: mixtapeEnabled ?? this.mixtapeEnabled,
        mixtapeMax: mixtapeMax ?? this.mixtapeMax,
        mixtapeWifiOnly: mixtapeWifiOnly ?? this.mixtapeWifiOnly,
        loudnessMode: loudnessMode ?? this.loudnessMode,
        boostQuiet: boostQuiet ?? this.boostQuiet,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences? _prefs;

  static const _kTheme = 'theme_mode';
  static const _kHeight = 'max_video_height';
  static const _kOutput = 'preferred_output';
  static const _kMp3 = 'mp3_bitrate';
  static const _kConcurrent = 'max_concurrent';
  static const _kAutoplay = 'autoplay_next';
  static const _kHistory = 'save_history';
  static const _kMixtape = 'mixtape_enabled';
  static const _kMixtapeMax = 'mixtape_max';
  static const _kMixtapeWifi = 'mixtape_wifi_only';
  static const _kLoudness = 'loudness_mode';
  static const _kBoostQuiet = 'loudness_boost_quiet';

  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    const d = AppSettings();
    final height = p.containsKey(_kHeight) ? p.getInt(_kHeight) : d.maxVideoHeight;
    state = AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == p.getString(_kTheme), orElse: () => d.themeMode),
      maxVideoHeight: (height ?? 0) <= 0 ? null : height,
      preferredOutput: OutputKind.values.firstWhere((k) => k.name == p.getString(_kOutput), orElse: () => d.preferredOutput),
      mp3BitrateKbps: AppSettings.mp3Bitrates.contains(p.getInt(_kMp3)) ? p.getInt(_kMp3)! : d.mp3BitrateKbps,
      maxConcurrentDownloads: (p.getInt(_kConcurrent) ?? d.maxConcurrentDownloads).clamp(1, 3),
      autoplayNext: p.getBool(_kAutoplay) ?? d.autoplayNext,
      saveHistory: p.getBool(_kHistory) ?? d.saveHistory,
      mixtapeEnabled: p.getBool(_kMixtape) ?? d.mixtapeEnabled,
      mixtapeMax: AppSettings.mixtapeSizes.contains(p.getInt(_kMixtapeMax)) ? p.getInt(_kMixtapeMax)! : d.mixtapeMax,
      mixtapeWifiOnly: p.getBool(_kMixtapeWifi) ?? d.mixtapeWifiOnly,
      loudnessMode: LoudnessMode.values.firstWhere((m) => m.name == p.getString(_kLoudness), orElse: () => d.loudnessMode),
      boostQuiet: p.getBool(_kBoostQuiet) ?? d.boostQuiet,
    );
  }

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.setString(_kTheme, next.themeMode.name);
    await p.setInt(_kHeight, next.maxVideoHeight ?? 0);
    await p.setString(_kOutput, next.preferredOutput.name);
    await p.setInt(_kMp3, next.mp3BitrateKbps);
    await p.setInt(_kConcurrent, next.maxConcurrentDownloads.clamp(1, 3));
    await p.setBool(_kAutoplay, next.autoplayNext);
    await p.setBool(_kHistory, next.saveHistory);
    await p.setBool(_kMixtape, next.mixtapeEnabled);
    await p.setInt(_kMixtapeMax, next.mixtapeMax);
    await p.setBool(_kMixtapeWifi, next.mixtapeWifiOnly);
    await p.setString(_kLoudness, next.loudnessMode.name);
    await p.setBool(_kBoostQuiet, next.boostQuiet);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
