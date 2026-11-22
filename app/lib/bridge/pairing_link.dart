/// 桥 `/tunnel` 回复的「一行短码」：`<地址>#<配对码>`。
///
/// 为什么不是 DSH1 长文本：那串长文本经 IM 转发/复制会掉字符，43 位令牌变成「库里
/// 不存在的一枚」，连接只会报超时或「配对令牌已失效」（见桥仓 issue #28）。
/// 短码只有地址 + 8 位配对码，用户整行粘进导入框，由这里拆成两格。
class PairingLink {
  const PairingLink({required this.endpoints, required this.code});

  /// 候选地址表（隧道在前），都已剥掉尾部 `/` 与误贴的 `/api/v1`。
  final List<String> endpoints;
  final String code;

  /// 第一条 —— 老码（单地址）就是它；多址时仍以它为首选探测目标。
  String get baseUrl => endpoints.first;
}

final _codeRe = RegExp(r'^[A-Za-z0-9_-]{4,32}$');
final _apiSuffix = RegExp(r'/api/v1$');

/// 解析一行短码；不是这个形状就返回 null（调用方再回落到 DSH1）。
PairingLink? parsePairingLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  // 只看第一行有内容的行：IM 里往往还跟着一句说明。
  final line = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return null;
  // 用最后一个 `#`：地址里理论上也可能带片段，但配对码一定在末尾。
  final cut = line.lastIndexOf('#');
  if (cut <= 0 || cut == line.length - 1) return null;
  final code = line.substring(cut + 1).trim();
  if (!_codeRe.hasMatch(code)) return null;
  final endpoints = <String>[];
  for (final raw in line.substring(0, cut).split(',')) {
    final url = raw.trim().replaceAll(RegExp(r'/+$'), '').replaceAll(_apiSuffix, '');
    if (url.isEmpty) continue;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (!endpoints.contains(url)) endpoints.add(url);
  }
  if (endpoints.isEmpty) return null;
  return PairingLink(endpoints: endpoints, code: code);
}
