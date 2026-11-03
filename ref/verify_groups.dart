import 'dart:convert';
import 'dart:io';
import 'package:dshchat/bridge/models.dart';

void main() {
  final raw = jsonDecode(File('../ref/hist-demo.json').readAsStringSync());
  final page = HistoryPage.fromEvents(raw['events'] as List);
  for (final m in page.items) {
    if (m.isProcess) {
      print('PROCESS calls=${m.toolCalls.length} phrase=${m.phraseText}');
      for (final t in m.toolCalls) {
        print('   - ${t.callId} ${t.phrases.join("/")} | ${t.summary}');
      }
    } else {
      print('${m.role.toUpperCase()} ${m.text.replaceAll("\n", " ").substring(0, m.text.length > 40 ? 40 : m.text.length)}');
    }
  }
}
