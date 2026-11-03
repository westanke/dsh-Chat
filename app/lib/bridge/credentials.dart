import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// bridge 凭证持久化（baseUrl + token）。
///
/// 支撑「一次配对，此后自动连接」：pair() 成功后 save()，
/// 下次启动 load() 命中则走 GatewayClient.connect()（子协议 dsh-auth）。
/// 存储键名 dsh.credentials，值为 JSON {baseUrl, token}。
class DshCredentials {
  DshCredentials._();

  static const String _key = 'dsh.credentials';

  static String? baseUrl;
  static String? token;

  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      baseUrl = j['baseUrl'] as String?;
      token = j['token'] as String?;
    } on FormatException {
      await clear();
    }
  }

  static Future<void> save({
    required String baseUrl,
    required String token,
  }) async {
    DshCredentials.baseUrl = baseUrl;
    DshCredentials.token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode({'baseUrl': baseUrl, 'token': token}));
  }

  static Future<void> clear() async {
    baseUrl = null;
    token = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
