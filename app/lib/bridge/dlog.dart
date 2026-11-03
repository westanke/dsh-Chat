/// 文件日志：vivo logcat 会滤掉 flutter/debugPrint，关键链路事件写进
/// app 私有文件（debug 包可用 `adb shell run-as com.dsh.dshchat cat` 读取）。
library;

import 'dart:io';

class DshLog {
  DshLog._();

  static File? _file;

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
    try {
      _file?.writeAsStringSync(
        '${DateTime.now().toIso8601String().substring(11, 23)} $msg\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
