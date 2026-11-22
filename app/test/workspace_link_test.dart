// 消息内「工作区文件链接」的判定与解析（ui/workspace_link.dart）。
import 'package:dshchat/ui/workspace_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspacePathOf', () {
    test('http/https 不归本模块', () {
      expect(workspacePathOf('https://example.com/a.md'), isNull);
      expect(workspacePathOf('http://x/y.txt'), isNull);
    });

    test('绝对路径直接用', () {
      expect(
        workspacePathOf('/media/wangke/OFFICE/workspace/README.md'),
        '/media/wangke/OFFICE/workspace/README.md',
      );
    });

    test('file:// 去掉 scheme', () {
      expect(workspacePathOf('file:///tmp/a.md'), '/tmp/a.md');
    });

    test('相对路径要拼 cwd，且必须命中可读扩展名', () {
      expect(
        workspacePathOf('docs/README.md', cwd: '/w'),
        '/w/docs/README.md',
      );
      // 不在白名单里的扩展名不当文件
      expect(workspacePathOf('docs/a.unknownext', cwd: '/w'), isNull);
      // 没有 cwd 就不猜
      expect(workspacePathOf('docs/README.md'), isNull);
    });

    test('行尾标点剥掉', () {
      expect(workspacePathOf('/w/a.md.'), '/w/a.md');
      expect(workspacePathOf('/w/a.md)'), '/w/a.md');
    });

    test('空串与纯文字不算', () {
      expect(workspacePathOf('   '), isNull);
      expect(workspacePathOf('看看这个'), isNull);
    });
  });
}
