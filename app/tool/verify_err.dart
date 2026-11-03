// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:dshchat/bridge/models.dart';

void main() {
  final raw = jsonDecode(File('../ref/hist-err.json').readAsStringSync());
  final page = HistoryPage.fromEvents(raw['events'] as List);
  for (final m in page.items) {
    print('${m.role.padRight(10)} ${m.text.replaceAll("\n", " ").substring(0, m.text.length > 50 ? 50 : m.text.length)}');
  }
}
