/// 应用新版本检测（真机反馈 2026-11-04 第 9 项）。
///
/// 发布通道：release.sh 把 `dsh-Chat-v<VER>.apk` 同时发到 Gitee 与 GitHub
/// Release（tag `v<name>`，见 scripts/release.sh）。国内直连 GitHub 不稳定、
/// GitHub 直连 Gitee 也常见超时，所以两站都探测：先 Gitee（国内主站），
/// 失败再 GitHub（国外），都失败返回 null（UI 提示「检查失败」）。
///
/// 对比口径：tag_name（`v1.0.0`）去掉 `v` 前缀后按语义化版本三段比较。
/// 下载交给原生 DownloadManager（platform.dart 的 downloadApk，零权限）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const _repo = 'westanke/dsh-Chat';

/// 一条可下载的发布信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.apkUrl,
    required this.apkName,
    this.size,
    this.sha256,
    this.notes,
  });

  final String tag; // 如 v1.0.1
  final String apkUrl;
  final String apkName;
  final int? size; // 字节；API 给了才有
  final String? sha256; // SHA256SUMS.txt 或发布正文里给了才有
  final String? notes; // 发布正文（Markdown 纯文本用）

  /// 语义化版本三段（tag 去 v 前缀；解析失败回 0.0.0）。
  List<int> get versionParts {
    final t = tag.startsWith('v') ? tag.substring(1) : tag;
    final parts = t.split('.');
    return [
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }
}

/// 拉最新发布：先 Gitee 后 GitHub；都失败抛 RequestException。
Future<ReleaseInfo> fetchLatestRelease() async {
  // Gitee：api/v5 releases/latest，assets[].name + browser_download_url。
  try {
    final r = await http
        .get(
          Uri.parse('https://gitee.com/api/v5/repos/$_repo/releases/latest'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final rel = _releaseFromJson(jsonDecode(r.body), gitee: true);
      if (rel != null) return rel;
    }
  } on Exception {
    // 落到 GitHub。
  }
  // GitHub：api.github.com releases/latest（国内可能超时——上面的 8s 上限兜底）。
  final r = await http
      .get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 8));
  if (r.statusCode != 200) {
    throw Exception('release check failed (gitee+github)');
  }
  final rel = _releaseFromJson(jsonDecode(r.body), gitee: false);
  if (rel == null) {
    throw Exception('no apk asset in release');
  }
  return rel;
}

/// 从 Gitee/GitHub 的 release JSON 里挑出 APK 资产。
/// 两站形状一致：tag_name / body / assets[]{name,browser_download_url,size}。
ReleaseInfo? _releaseFromJson(Object? body, {required bool gitee}) {
  if (body is! Map) return null;
  final tag = (body['tag_name'] ?? '') as String;
  if (tag.isEmpty) return null;
  final assets = body['assets'];
  if (assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = (a['name'] ?? '') as String;
    if (!name.endsWith('.apk') || !name.startsWith('dsh-Chat-')) continue;
    final url = (a['browser_download_url'] ?? '') as String;
    if (url.isEmpty) continue;
    return ReleaseInfo(
      tag: tag,
      apkUrl: url,
      apkName: name,
      size: a['size'] is int ? a['size'] as int : null,
      notes: (body['body'] ?? '') as String,
    );
  }
  return null;
}

/// a 是否比 b 新（语义化三段逐位比较）。
bool isNewerVersion(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
