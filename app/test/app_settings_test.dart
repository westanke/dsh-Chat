// 本地偏好单测：normalizeFontScale / AppFontScaler / AppSettings。
// 对照 dsh-companion data/AppPreferences.kt 与 ui/theme/AppFontScale.kt。
import 'dart:convert';

import 'package:dshchat/design/app_settings.dart';
import 'package:flutter/painting.dart' show TextScaler;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('normalizeFontScale', () {
    test('finite in-range values pass through', () {
      expect(normalizeFontScale(1.0), 1.0);
      expect(normalizeFontScale(1.25), 1.25);
      expect(normalizeFontScale(0.8), 0.8);
      expect(normalizeFontScale(1.5), 1.5);
    });

    test('out-of-range values clamp to 0.8..1.5', () {
      expect(normalizeFontScale(0.5), 0.8);
      expect(normalizeFontScale(2.0), 1.5);
      expect(normalizeFontScale(-1.0), 0.8);
    });

    test('NaN / Inf fall back to 1.0 (no NaN layout)', () {
      expect(normalizeFontScale(double.nan), 1.0);
      expect(normalizeFontScale(double.infinity), 1.0);
      expect(normalizeFontScale(double.negativeInfinity), 1.0);
    });
  });

  group('AppFontScaler', () {
    test('multiplies the system scaler with the in-app scale', () {
      const scaler = AppFontScaler(TextScaler.linear(2.0), 1.3);
      expect(scaler.scale(10), 26.0);
      expect(scaler.scale(1.0), 2.6);
      expect(scaler.textScaleFactor, 2.6);
    });

    test('appScale == 1.0 is a pure pass-through of the system scaler', () {
      const scaler = AppFontScaler(TextScaler.linear(1.5), 1.0);
      expect(scaler.scale(16), 24.0);
    });

    test('clamp wraps the base clamp and keeps appScale', () {
      const base = AppFontScaler(TextScaler.linear(2.0), 1.3);
      final clamped = base.clamp(minScaleFactor: 1, maxScaleFactor: 1.5);
      expect(clamped, isA<AppFontScaler>());
      expect((clamped as AppFontScaler).appScale, 1.3);
    });

    test('equality is by base + appScale (avoids needless rebuilds)', () {
      const a = AppFontScaler(TextScaler.linear(2.0), 1.3);
      const b = AppFontScaler(TextScaler.linear(2.0), 1.3);
      const c = AppFontScaler(TextScaler.linear(2.0), 1.4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('AppSettings', () {
    test('defaults match the pre-settings behavior', () {
      final s = AppSettings();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.fontScale, 1.0);
      expect(s.fontFollowsSystem, isFalse);
      expect(s.busySendMode, BusySendMode.queue);
      expect(s.diagLog, isTrue);
      // 2026-11-16 通用设置批次：详细档 / 回答结束后收起 / 全部回复 / 关闭。
      expect(s.workStepsDetail, WorkStepsDetail.detailed);
      expect(s.collapseTiming, CollapseTiming.completion);
      expect(s.foldedReplies, FoldedReplies.all);
      expect(s.codeWorkView, isFalse);
      expect(s.effectiveFontScale, 1.0);
    });

    test('effectiveFontScale ignores the app scale when following system', () {
      final s = AppSettings();
      s.setFontScale(1.4);
      expect(s.effectiveFontScale, 1.4);
      s.setFontFollowsSystem(true);
      expect(s.effectiveFontScale, 1.0);
      s.setFontFollowsSystem(false);
      expect(s.effectiveFontScale, 1.4);
    });

    test('setters normalize and notify listeners', () {
      final s = AppSettings();
      var notified = 0;
      s.addListener(() => notified++);
      s.setFontScale(9.0);
      expect(s.fontScale, 1.5);
      s.setThemeMode(AppThemeMode.dark);
      expect(s.themeMode, AppThemeMode.dark);
      s.setThemeMode(AppThemeMode.dark); // no-op should not notify
      expect(notified, 2);
    });

    test('load reads enums by name and clamps the font scale', () async {
      SharedPreferences.setMockInitialValues({
        'dsh.settings': jsonEncode({
          'themeMode': 'dark',
          'fontScale': 2.0,
          'fontFollowsSystem': true,
          'busySendMode': 'steer',
          'diagLog': false,
          'workStepsDetail': 'verbose',
          'collapseTiming': 'next-input',
          'foldedReplies': 'final',
          'codeWorkView': true,
        }),
      });
      final s = AppSettings();
      await s.load();
      expect(s.themeMode, AppThemeMode.dark);
      expect(s.fontScale, 1.5);
      expect(s.fontFollowsSystem, isTrue);
      expect(s.busySendMode, BusySendMode.steer);
      expect(s.diagLog, isFalse);
      expect(s.workStepsDetail, WorkStepsDetail.verbose);
      expect(s.collapseTiming, CollapseTiming.nextInput);
      expect(s.foldedReplies, FoldedReplies.finalOnly);
      expect(s.codeWorkView, isTrue);
      expect(s.effectiveFontScale, 1.0);
    });

    test('new general-settings enums round-trip through their jsonName', () async {
      // 存读走官方 token 字符串（workStepsDetail/collapseTiming/foldedReplies），
      // 未知名与缺键回默认；setX 即时 _save 可被再次 load 读回。
      final s = AppSettings();
      var notified = 0;
      s.addListener(() => notified++);
      s.setWorkStepsDetail(WorkStepsDetail.concise);
      s.setCollapseTiming(CollapseTiming.nextInput);
      s.setFoldedReplies(FoldedReplies.finalOnly);
      s.setCodeWorkView(true);
      expect(notified, 4);
      s.setWorkStepsDetail(WorkStepsDetail.concise); // no-op 不 notify
      s.setCodeWorkView(false);
      expect(notified, 5);
      expect(s.codeWorkView, isFalse);

      final saved = jsonDecode(
        (await SharedPreferences.getInstance()).getString('dsh.settings')!,
      ) as Map<String, dynamic>;
      expect(saved['workStepsDetail'], 'concise');
      expect(saved['collapseTiming'], 'next-input');
      expect(saved['foldedReplies'], 'final');
      // 前面 no-op 演练已把 codeWorkView 设回 false，存盘也应是 false。
      expect(saved['codeWorkView'], false);

      SharedPreferences.setMockInitialValues({
        'dsh.settings': jsonEncode({
          'workStepsDetail': 'NO_SUCH',
          'collapseTiming': 'NO_SUCH',
          'foldedReplies': 'NO_SUCH',
        }),
      });
      final r = AppSettings();
      await r.load();
      expect(r.workStepsDetail, WorkStepsDetail.detailed);
      expect(r.collapseTiming, CollapseTiming.completion);
      expect(r.foldedReplies, FoldedReplies.all);
      expect(r.codeWorkView, isFalse);
    });

    test('load keeps defaults on corrupt JSON / unknown enum names', () async {
      SharedPreferences.setMockInitialValues({'dsh.settings': '{not json'});
      final s = AppSettings();
      await s.load();
      expect(s.themeMode, AppThemeMode.system);
      expect(s.fontScale, 1.0);
      expect(s.busySendMode, BusySendMode.queue);

      SharedPreferences.setMockInitialValues({
        'dsh.settings': jsonEncode({
          'themeMode': 'NO_SUCH_MODE',
          'busySendMode': 'NO_SUCH_MODE',
        }),
      });
      final s2 = AppSettings();
      await s2.load();
      expect(s2.themeMode, AppThemeMode.system);
      expect(s2.busySendMode, BusySendMode.queue);
    });
  });
}
