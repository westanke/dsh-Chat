/// 文件日志：vivo logcat 会滤掉 flutter/debugPrint，关键链路事件写进
/// app 私有文件（debug 包可用 `adb shell run-as com.dsh.dshchat cat` 读取）。
library;

import 'dart:io';

class DshLog {
  DshLog._();

  static File? _file;

  /// 设置页「诊断日志」开关：关闭后只跳过写入，保留文件已有内容。
  /// 默认 true（保持加开关之前的行为，与 companion AppPreferences 默认一致）。
  static bool enabled = true;

  /// main() 里初始化；失败静默（日志绝不能影响业务）。
  static void init(String path) {
    try {
      _file = File(path);
      _file?.parent.createSync(recursive: true);
      _file?.writeAsStringSync(
        '---- session ${DateTime.now().toIso8601String()} ----\n',
        mode: FileMode.append,
      );
    } catch (_) {
      _file = null;
    }
  }

  /// 单文件上限 2 MiB：超了只保留尾部 —— 诊断关心「刚发生了什么」，
  /// 不是几小时前的全量（真机 debug 包 `run-as cat` 读整份会卡）。
  static const int maxBytes = 2 * 1024 * 1024;

  /// 裁剪不是「一超就剪」：剪完仍可能刚好越线，那样每写一行就要整份读 + 整份写
  /// （2 MiB × 每行 → UI 线程直接卡死，真机表现为 ANR）。留 25% 余量，摊到
  /// 每 ~512 KiB 才重写一次。
  static const int trimAtBytes = maxBytes + maxBytes ~/ 4;

  /// 同一句在这个窗口内重复只计数、不落盘：日志打点在每帧路径上，
  /// 不断重复的帧会把文件刷满并且把真正的现场挤出视野。
  static const Duration dedupeWindow = Duration(seconds: 2);

  static String? _lastMsg;
  static DateTime? _lastAt;
  static int _suppressed = 0;

  /// 纯判据（单测直接喂时间，不碰文件系统）：同一条消息在窗口内重复就抑制。
  static bool shouldSuppress(String msg, String? last, DateTime? lastAt, DateTime now) =>
      last == msg && lastAt != null && now.difference(lastAt) < dedupeWindow;

  /// 纯函数：内容超过 [limit] 时返回「该保留的起点偏移」（对齐到下一行首），否则 0。
  static int trimOffset(String content, int limit) {
    if (limit <= 0 || content.length <= limit) return 0;
    final cut = content.length - limit;
    final nl = content.indexOf('\n', cut);
    return nl < 0 ? content.length : nl + 1;
  }

  static String _stamp(DateTime now) =>
      now.toIso8601String().substring(11, 23);

  static void w(String msg) {
    if (!enabled) return;
    final now = DateTime.now();
    if (shouldSuppress(msg, _lastMsg, _lastAt, now)) {
      _suppressed++;
      _lastAt = now;
      return;
    }
    _lastMsg = msg;
    _lastAt = now;
    try {
      final file = _file;
      if (file == null) return;
      final buffer = StringBuffer();
      if (_suppressed > 0) {
        buffer.write('${_stamp(now)} （上一条重复 $_suppressed 次）\n');
        _suppressed = 0;
      }
      buffer.write('${_stamp(now)} $msg\n');
      if (file.existsSync() && file.lengthSync() > trimAtBytes) {
        final kept = file.readAsStringSync();
        file.writeAsStringSync(kept.substring(trimOffset(kept, maxBytes)));
      }
      file.writeAsStringSync(buffer.toString(), mode: FileMode.append);
    } catch (_) {}
  }

  /// 设置页「读日志」：返回文件全部文本；无文件/读失败返回空串（不抛）。
  static String read() {
    try {
      return _file?.readAsStringSync() ?? '';
    } catch (_) {
      return '';
    }
  }
}
