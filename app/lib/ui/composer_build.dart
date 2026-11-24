part of 'composer.dart';

/// 输入条的装配（从 composer.dart 拆出，宪法 §7 单文件 ≤500 行）。
///
/// 只搬代码不改行为：面板区（@ / 斜杠候选）+ 输入条本体 + 免责提示。
extension _ComposerBuild on ComposerState {
  Widget buildComposer(BuildContext context) {
    final at = _atDraft;
    final slashMatches = _slashMatches;
    // 斜杠面板三态：候选（列表）/ 参数提示（单行）/ 不显示。
    final slashContent = at == null ? _paletteContent : const PaletteNone();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        DsSpacing.composerMargin,
        widget.topGap,
        DsSpacing.composerMargin,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 面板整体限高内滚（屏幕 42%）：会话分组 + 文件/命令面板叠起来会顶出屏幕。
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (at != null && slashMatches.isEmpty) ...[
                    if (_atSessionMatches.isNotEmpty)
                      _AtSessionPanel(
                        colors: c,
                        sessions: _atSessionMatches,
                        onPick: _applySessionEntry,
                      ),
                    _AtFilePanel(
                      colors: c,
                      entries: _atMatches,
                      query: _atLeafQuery,
                      rootLabel: _atRoots.isEmpty ? '' : _atRoots.first.label,
                      loading: _atLoading,
                      failed: _atFailed,
                      onRetry: () {
                        _atLoadedDir = null;
                        _ensureAtEntries('');
                      },
                      highlighted: _panelHighlight,
                      onPick: _applyAtEntry,
                      onHighlightChanged: (i) =>
                          _refresh(() => _panelHighlight = i),
                    ),
                  ] else if (slashContent is! PaletteNone)
                    // 点面板外关闭 + 返回键先关面板（dsh-go TextFieldTapRegion
                    // / PopScope 同口径），出现时淡入并轻微上浮。
                    TextFieldTapRegion(
                      onTapOutside: (_) => _dismissSlashPalette(),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.bottomCenter,
                        // 候选 ⇄ 参数提示切换时淡入并轻微上浮（dsh-go
                        // AnimatedSwitcher + ScaleTransition(0.96→1) 同观感）。
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeOut,
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: 0.96,
                                end: 1,
                              ).animate(anim),
                              alignment: Alignment.bottomCenter,
                              child: child,
                            ),
                          ),
                          child: _CommandPanel(
                            colors: c,
                            key: ValueKey<String>(
                              slashContent.runtimeType.toString(),
                            ),
                            content: slashContent,
                            highlighted: _panelHighlight,
                            onPick: _applyCommand,
                            onHighlightChanged: (i) =>
                                _refresh(() => _panelHighlight = i),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          _ComposerBar(
            colors: c,
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            onKey: _onKey,
            onChanged: _onChanged,
            permissionLabel: _permissionLabel,
            permissionActive: (widget.currentPermission ?? '').isNotEmpty,
            onPickPermission: _pickPermission,
            pendingImageNames: [for (final i in _pendingImages) i.name],
            onRemoveImage: (i) => _refresh(() => _pendingImages.removeAt(i)),
            canPickImage: widget.enabled,
            onPickImage: _openPlusPanel,
            onInsertContent: () {
              _focus.requestFocus();
              insertAtMention(_controller, _onChanged);
            },
            sendState: _sendKeyState,
            canSend: widget.enabled && (_hasText || _hasImage),
            onSend: _send,
            onStop: widget.onCancel,
            answering: widget.answering,
            gateway: widget.gateway,
            sessionId: widget.sessionId,
            onPickModel: widget.onPickModel,
            modelLabel: widget.modelLabel,
          ),
          const SizedBox(height: DsSpacing.composerHintGap),
          // 免责声明：流式思考中不显示（思考块已在消息流里滚动展示）。
          if (!widget.streaming)
            Text(
              '回答由 AI 生成，仅供参考',
              style: DsTypography.caption.copyWith(color: c.inputHintText),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
