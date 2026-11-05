/// 全屏 Markdown 文档查看页（文件卡第四轮反馈 6 改进）：
/// 点 .md 文件卡 → resolve + 取字节 → 本页渲染。可滚动看长文档。
/// 加载中转圈 / 失败给重试；顶部显示文件名。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../bridge/gateway.dart';
import '../design/tokens.dart';
import 'md_view.dart';

class MdViewerPage extends StatefulWidget {
  const MdViewerPage({
    super.key,
    required this.gateway,
    required this.absolutePath,
    required this.title,
    required this.colors,
  });

  final GatewayClient gateway;

  /// deliverables 事件里的服务器绝对路径（resolve 由本页内部完成）。
  final String absolutePath;
  final String title;
  final DsColors colors;

  @override
  State<MdViewerPage> createState() => _MdViewerPageState();
}

class _MdViewerPageState extends State<MdViewerPage> {
  String? _text;
  String? _error;
  bool _loading = true;
  int _size = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resolved = await gatewayResolvePath(widget.gateway,
          widget.absolutePath);
      final bytes = await gatewayReadFileBytes(
        widget.gateway,
        resolved.rootId,
        resolved.path,
      );
      if (!mounted) return;
      setState(() {
        _text = utf8.decode(bytes, allowMalformed: true);
        _size = bytes.length;
        _loading = false;
      });
    } on RequestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取失败：$e';
        _loading = false;
      });
    }
  }

  String get _sizeLabel {
    final b = _size;
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              overflow: TextOverflow.ellipsis,
              style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
            ),
            if (_size > 0)
              Text(
                _sizeLabel,
                style: DsTypography.caption.copyWith(color: c.labelTertiary),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DsSpacing.screenPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: DsTypography.small.copyWith(
                              color: c.danger,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: DsSpacing.hMargin,
                      vertical: DsSpacing.screenPad,
                    ),
                    child: DsMarkdownView(text: _text ?? '', colors: c),
                  ),
      ),
    );
  }
}
