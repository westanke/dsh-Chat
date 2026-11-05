/// 设置页：纯本地偏好 + 来自 hello 帧的只读连接/设备信息。
///
/// 对照 dsh-companion ui/SettingsScreen.kt，但刻意只做「每条都真实生效」的项：
/// - 服务端设置（命名空间 / 模型 / 插件 / providers）全走 REST /api/v1/settings/*，
///   且设备默认 scope 不含 settings.write，照搬就会变成「一排拨不动的开关」
///   （companion 自己踩过的坑）。因此这里不提供任何服务端写入入口，只在连接区
///   诚实说明其能力与授权前提。
/// - 语言三档 / 配色四套需要完整本地化资源与四套 token，本版本未做，不摆空开关。
/// - 「深度思考 / 智能搜索」chip、点赞/朗读/分享属于仿官方 App 像素的既有 UI，
///   协议 message 帧无对应字段，不在这里伪装成设置项。
///
/// 样式全部走 DsColors / DsTypography / DsSpacing（宪法 §4）；设置页专属色值与
/// 间距在 docs/design-tokens.md §4.4 登记后才在此引用。
/// 宪法 §7 单文件 ≤500 行：分区与通用组件拆到同库的 part 文件，私有成员共享。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import '../bridge/credentials.dart';
import '../bridge/dlog.dart';
import '../bridge/gateway.dart';
import '../bridge/platform.dart';
import '../bridge/release_check.dart';
import '../design/app_settings.dart';
import '../design/tokens.dart';

part 'settings_sections.dart';
part 'settings_widgets.dart';
part 'settings_update.dart';

/// 与 app/pubspec.yaml 的 version 保持一致（Flutter 无 BuildConfig，
/// 不引入 package_info_plus，避免为一个展示字符串增加依赖，宪法 §8）。
const String _appVersion = '1.0.9+10';

/// 子协议与握手协议版本：常量锚点在 bridge/gateway.dart，此处只读展示。
const String _subprotocol = 'dsh-mobile-v1';
const int _helloProtocol = 3;

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.colors,
    required this.gateway,
    required this.onDisconnect,
  });

  final DsColors colors;
  final GatewayClient? gateway;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Scaffold(
      backgroundColor: c.bgBase,
      appBar: AppBar(
        backgroundColor: c.bgBase,
        elevation: 0,
        title: Text(
          '设置',
          style: DsTypography.pageTitle.copyWith(color: c.labelPrimary),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: appSettings,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: DsSpacing.settingsPadH,
              vertical: DsSpacing.settingsPadV,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DsSpacing.settingsMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '设置',
                      style: DsTypography.h3.copyWith(color: c.labelPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '本地偏好即时生效；连接与设备信息来自服务端 hello 帧，只读。',
                      style: DsTypography.small.copyWith(
                        color: c.labelTertiary,
                      ),
                    ),
                    const SizedBox(height: DsSpacing.settingsSectionGap),
                    _ConnectionSection(colors: c, gateway: gateway),
                    _AppearanceSection(colors: c),
                    _SendSection(colors: c),
                    _DiagnosticsSection(colors: c),
                    _AboutSection(colors: c),
                    _DisconnectSection(
                      colors: c,
                      onDisconnect: onDisconnect,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
