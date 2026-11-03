part of 'settings_page.dart';

// ---------- 通用组件 ----------

class _Section extends StatelessWidget {
  const _Section({
    required this.colors,
    required this.title,
    required this.children,
  });

  final DsColors colors;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.settingsSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: DsTypography.smallStrong.copyWith(
                color: c.labelSecondary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.settingsSurface,
              borderRadius: BorderRadius.circular(
                DsSpacing.settingsCardRadius,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final DsColors colors;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsCardPadH,
        vertical: DsSpacing.settingsCardPadV,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.brand),
          const SizedBox(width: DsSpacing.settingsIconGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.base.copyWith(color: c.labelPrimary),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DsTypography.small.copyWith(
                    color: c.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.colors,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final DsColors colors;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.settingsCardPadH,
          vertical: DsSpacing.settingsCardPadV,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.brand),
            const SizedBox(width: DsSpacing.settingsIconGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DsTypography.base.copyWith(
                      color: c.labelPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: DsTypography.small.copyWith(
                      color: c.labelTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.colors,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final DsColors colors;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsCardPadH,
        vertical: DsSpacing.settingsCardPadV,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DsTypography.base.copyWith(color: c.labelPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: DsTypography.caption.copyWith(
                    color: c.labelTertiary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: c.brand,
          ),
        ],
      ),
    );
  }
}

class _SegmentedRow<T extends Enum> extends StatelessWidget {
  const _SegmentedRow({
    required this.colors,
    required this.label,
    required this.values,
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final DsColors colors;
  final String label;
  final List<T> values;
  final T selected;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsCardPadH,
        vertical: DsSpacing.settingsCardPadV,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: DsTypography.base.copyWith(color: c.labelPrimary),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<T>(
              segments: [
                for (final v in values)
                  ButtonSegment<T>(
                    value: v,
                    label: Text(labels[v] ?? v.name),
                  ),
              ],
              selected: <T>{selected},
              onSelectionChanged: (s) => onChanged(s.first),
              showSelectedIcon: false,
              style: _segmentedStyle(c),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _segmentedStyle(DsColors c) => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected)
                ? c.chipSelectedBg
                : c.settingsField),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected)
                ? c.chipSelectedFg
                : c.labelPrimary),
        side: WidgetStateProperty.all(BorderSide.none),
        textStyle: WidgetStateProperty.all(DsTypography.small),
      );
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.colors, required this.label});

  final DsColors colors;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsChipPadH,
        vertical: DsSpacing.settingsChipPadV,
      ),
      decoration: BoxDecoration(
        color: c.settingsField,
        borderRadius: BorderRadius.circular(DsSpacing.settingsChipRadius),
      ),
      child: Text(
        _labelFor(label),
        style: DsTypography.caption.copyWith(color: c.labelSecondary),
      ),
    );
  }

  static String _labelFor(String scope) => const {
        'chat.read': '聊天读取',
        'chat.write': '聊天写入',
        'files.read': '文件读取',
        'files.write': '文件写入',
        'files.delete': '文件删除',
        'settings.read': '设置读取',
        'settings.write': '设置写入',
      }[scope] ??
      scope;
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.colors, required this.text});

  final DsColors colors;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.settingsCardPadH,
        vertical: DsSpacing.settingsCardPadV,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: c.settingsWarnBg,
          borderRadius: BorderRadius.circular(DsSpacing.inlineCodeRadius),
        ),
        child: Text(
          text,
          style: DsTypography.small.copyWith(color: c.settingsWarnFg),
        ),
      ),
    );
  }
}
