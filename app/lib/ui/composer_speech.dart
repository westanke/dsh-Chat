part of 'composer.dart';

/// 输入条左侧的「语音」圆钮：`speech-catalog` 可用且麦克风权限可用时出现。
/// 点按开始录音，再点结束并把转写结果交给 [onInsert]；录音/准备/转写中
/// 额外显示取消键。状态机在 [SpeechController]，错误由调用方 SnackBar 展示。
class _ComposerSpeechKeys extends StatefulWidget {
  const _ComposerSpeechKeys({
    required this.colors,
    required this.gateway,
    required this.enabled,
    required this.onInsert,
    required this.onStatusChanged,
  });

  final DsColors colors;
  final GatewayClient? gateway;
  final bool enabled;
  final ValueChanged<String> onInsert;
  final ValueChanged<String?> onStatusChanged;

  @override
  State<_ComposerSpeechKeys> createState() => _ComposerSpeechKeysState();
}

class _ComposerSpeechKeysState extends State<_ComposerSpeechKeys> {
  SpeechController? _speech;
  GatewayClient? _boundGateway;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _ComposerSpeechKeys oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  /// 连接可用时挂一个控制器并探测目录；断开/重建时整体释放。
  void _sync() {
    final gateway = widget.gateway;
    if (!widget.enabled || gateway == null) {
      _release();
      return;
    }
    // 同一个网关只探测一次：连接/可用性变化会重建 Composer（enabled 翻转），
    // 那时 [_release] + 新建控制器会重新探测。
    if (identical(_boundGateway, gateway)) return;
    _release();
    _boundGateway = gateway;
    final speech = SpeechController(gateway: gateway);
    speech.attachPushStream(gateway.speechPushes);
    _speech = speech..addListener(_onSpeechChanged);
    _probe(speech);
  }

  /// 目录探测（单飞，避免同一控制器重复发帧）。
  Future<void> _probe(SpeechController speech) async {
    if (_probing) return;
    _probing = true;
    try {
      await speech.probe();
    } finally {
      _probing = false;
    }
  }

  void _release() {
    _probing = false;
    _speech?.removeListener(_onSpeechChanged);
    _speech?.dispose();
    _speech = null;
    _boundGateway = null;
  }

  void _onSpeechChanged() {
    if (!mounted) return;
    setState(() {});
    widget.onStatusChanged(_speech?.statusText);
  }

  Future<void> _toggle() async {
    final speech = _speech;
    if (speech == null || speech.busy) return;
    if (speech.recording) {
      final text = await speech.finish();
      if (!mounted) return;
      if (text == null) {
        _showError();
        return;
      }
      if (text.isEmpty) {
        _snack(speech.error ?? '没有识别到语音');
        return;
      }
      widget.onInsert(text);
      return;
    }
    await speech.begin();
    if (!mounted) return;
    _showError();
  }

  void _showError() {
    final message = _speech?.error;
    if (message == null || message.isEmpty) return;
    _snack(message);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final speech = _speech;
    if (speech == null || !speech.visible) return const SizedBox.shrink();
    final colors = widget.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: speech.recording ? '结束录音并转写' : '语音输入',
          child: _RoundIconButton(
            colors: colors,
            filled: speech.recording,
            quietFill: !speech.recording,
            icon: speech.recording
                ? Icons.stop
                : speech.busy
                ? Icons.graphic_eq
                : Icons.mic_none,
            iconSize: speech.recording ? 18 : 22,
            onPressed: speech.busy ? null : _toggle,
          ),
        ),
        if (speech.recording || speech.busy) ...[
          const SizedBox(width: 2),
          Tooltip(
            message: '取消语音输入',
            child: _RoundIconButton(
              colors: colors,
              filled: false,
              quietFill: true,
              icon: Icons.close,
              iconSize: 18,
              onPressed: () => speech.cancel(),
            ),
          ),
        ],
      ],
    );
  }
}
