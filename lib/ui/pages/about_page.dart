import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../services/app_update_service.dart';
import '../../services/music_api.dart';
import '../widgets/app_update_widgets.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.api});

  static final Uri _repositoryUri = Uri.parse(
    'https://github.com/umr-xiaomai/kgka_Music_hl',
  );

  final MusicApi api;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _changelog = '';
  bool _changelogLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    try {
      final content = await rootBundle.loadString('update.md');
      if (mounted) {
        setState(() {
          _changelog = content;
          _changelogLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _changelogLoaded = true);
      }
    }
  }

  Future<void> _openRepository(BuildContext context) async {
    final opened = await launchUrl(
      AboutPage._repositoryUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开 GitHub 仓库链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
        children: [
          const SizedBox(height: 12),
          Icon(Icons.music_note_rounded, size: 54, color: colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '版本 ${AppConfig.appVersion}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          _InfoSection(
            children: [
              const _InfoRow(label: '应用名称', value: AppConfig.appName),
              const _InfoRow(label: '当前版本', value: AppConfig.appVersion),
              const _InfoRow(label: '服务地址', value: AppConfig.apiBaseUrl),
              _InfoLinkRow(
                label: 'GitHub',
                value: 'umr-xiaomai/kgka_Music_hl',
                onTap: () => _openRepository(context),
              ),
            ],
          ),
          if (AppUpdateService.isSupportedPlatform) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () =>
                  checkAppUpdateManually(context: context, api: widget.api),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: const Text('检查更新'),
            ),
          ],
          if (_changelogLoaded && _changelog.isNotEmpty) ...[
            const SizedBox(height: 24),
            _ChangelogSection(content: _changelog),
          ],
          const SizedBox(height: 18),
          Text(
            '一个专注播放体验的音乐应用。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLinkRow extends StatelessWidget {
  const _InfoLinkRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogSection extends StatelessWidget {
  const _ChangelogSection({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lines = content.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.update_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '更新日志',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildMarkdownLines(context, lines),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMarkdownLines(BuildContext context, List<String> lines) {
    final widgets = <Widget>[];
    final colorScheme = Theme.of(context).colorScheme;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 4));
        }
        continue;
      }

      // Heading level 1
      if (trimmed.startsWith('# ') && !trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              trimmed.substring(2),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
        continue;
      }

      // Heading level 2
      if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              trimmed.substring(3),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colorScheme.primary,
              ),
            ),
          ),
        );
        continue;
      }

      // List item
      if (trimmed.startsWith('- ')) {
        final text = trimmed.substring(2);
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•  ',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Expanded(
                  child: _buildRichText(context, text),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Regular text
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _buildRichText(context, trimmed),
        ),
      );
    }

    return widgets;
  }

  Widget _buildRichText(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    final boldPattern = RegExp(r'\*\*(.*?)\*\*');
    var lastEnd = 0;

    for (final match in boldPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ));
    }

    if (spans.isEmpty) {
      return Text(
        text,
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      );
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: spans,
      ),
    );
  }
}
