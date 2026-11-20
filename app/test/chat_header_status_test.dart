// 会话页顶栏状态机单测（C 项 · chat_header_status.dart）。
import 'package:dshchat/bridge/gateway_events.dart';
import 'package:dshchat/ui/chat_header_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatHeaderStatus', () {
    test('未连接：idle / 未连接', () {
      final s = chatHeaderStatus(
        connection: GatewayState.idle,
        streaming: false,
        waitingApproval: false,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(s.tone, ChatStatusTone.idle);
      expect(s.label, '未连接');
    });

    test('连接中：busy / 连接中', () {
      final s = chatHeaderStatus(
        connection: GatewayState.connecting,
        streaming: false,
        waitingApproval: false,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(s.tone, ChatStatusTone.busy);
      expect(s.label, '连接中');
    });

    test('鉴权失败与连接关闭都算已断开', () {
      for (final state in [GatewayState.authFailed, GatewayState.closed]) {
        final s = chatHeaderStatus(
          connection: state,
          streaming: false,
          waitingApproval: false,
          waitingAnswer: false,
          hostLabel: '192.168.1.10',
        );
        expect(s.tone, ChatStatusTone.error);
        expect(s.label, '已断开');
      }
    });

    test('断线优先于生成中与等待', () {
      final s = chatHeaderStatus(
        connection: GatewayState.closed,
        streaming: true,
        waitingApproval: true,
        waitingAnswer: true,
        hostLabel: '192.168.1.10',
      );
      expect(s.label, '已断开');
    });

    test('等待审批与等待回答都是 warn，且先于生成中', () {
      final approval = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: true,
        waitingApproval: true,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(approval.tone, ChatStatusTone.warn);
      expect(approval.label, '等待审批');

      final answer = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: true,
        waitingApproval: false,
        waitingAnswer: true,
        hostLabel: '192.168.1.10',
      );
      expect(answer.tone, ChatStatusTone.warn);
      expect(answer.label, '等待回答');
    });

    test('生成中：busy / 生成中', () {
      final s = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: true,
        waitingApproval: false,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(s.tone, ChatStatusTone.busy);
      expect(s.label, '生成中');
    });

    test('一切正常：显示主机名', () {
      final s = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: false,
        waitingApproval: false,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(s.tone, ChatStatusTone.ok);
      expect(s.label, '192.168.1.10');
    });

    test('读屏文案缺省读 label，有专门文案时读它', () {
      final plain = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: false,
        waitingApproval: false,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
      );
      expect(plain.spokenLabel, '192.168.1.10');

      final spoken = chatHeaderStatus(
        connection: GatewayState.ready,
        streaming: false,
        waitingApproval: true,
        waitingAnswer: false,
        hostLabel: '192.168.1.10',
        spoken: '工具 bash 请求执行命令',
      );
      expect(spoken.label, '等待审批');
      expect(spoken.spokenLabel, '工具 bash 请求执行命令');
    });
  });
}
