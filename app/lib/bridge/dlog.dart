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

  static void w(String msg) {
    if (!enabled) return;
    try {
      _file?.writeAsStringSync(
        '${DateTime.now().toIso8601String().substring(11, 23)} $msg\n',
        mode: FileMode.append,
      );
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
