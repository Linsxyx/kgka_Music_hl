import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/player_controller.dart';
import '../../services/app_update_service.dart';
import '../../services/music_api.dart';
import '../widgets/audio_quality_sheet.dart';
import '../widgets/app_update_widgets.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.api,
    required this.auth,
    required this.player,
  });

  final MusicApi api;
  final AuthController auth;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
        children: [
          _SettingsGroup(
            title: '账号',
            children: [
              AnimatedBuilder(
                animation: auth,
                builder: (context, _) {
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: Icon(
                      Icons.sync_rounded,
                      color: colorScheme.primary,
                    ),
                    title: const Text('同步个人信息'),
                    subtitle: const Text('刷新头像、昵称和歌单数据'),
                    enabled: !auth.isLoading,
                    trailing: auth.isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(
                            Icons.chevron_right_rounded,
                            color: colorScheme.outline,
                          ),
                    onTap: auth.isLoading ? null : auth.refreshProfile,
                  );
                },
              ),
              const Divider(height: 1, indent: 54),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: const Icon(Icons.logout_rounded),
                title: const Text('退出登录'),
                textColor: colorScheme.error,
                iconColor: colorScheme.error,
                onTap: auth.isLoading ? null : () => _confirmLogout(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '播放',
            children: [
              AnimatedBuilder(
                animation: player,
                builder: (context, _) {
                  return Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        leading: Icon(
                          Icons.high_quality_rounded,
                          color: colorScheme.primary,
                        ),
                        title: const Text('默认音质'),
                        subtitle: Text(player.audioQuality.label),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.outline,
                        ),
                        onTap: () => _selectDefaultAudioQuality(context),
                      ),
                      const Divider(height: 1, indent: 54),
                      SwitchListTile(
                        value: player.addListeningTimeEnabled,
                        onChanged: player.setAddListeningTimeEnabled,
                        secondary: Icon(
                          Icons.bar_chart_rounded,
                          color: colorScheme.primary,
                        ),
                        title: const Text('增加听歌时长'),
                        subtitle: const Text('每播放 30 分钟自动同步一次'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            title: '应用',
            children: [
              if (AppUpdateService.isSupportedPlatform) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  leading: Icon(
                    Icons.system_update_alt_rounded,
                    color: colorScheme.primary,
                  ),
                  title: const Text('检查更新'),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.outline,
                  ),
                  onTap: () =>
                      checkAppUpdateManually(context: context, api: api),
                ),
                const Divider(height: 1, indent: 54),
              ],
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: colorScheme.primary,
                ),
                title: const Text('关于'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colorScheme.outline,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AboutPage(api: api)),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectDefaultAudioQuality(BuildContext context) async {
    final quality = await showAudioQualitySheet(
      context: context,
      selected: player.audioQuality,
      title: '默认音质',
      subtitle: '新播放的歌曲会使用这个音质',
    );
    if (quality == null) {
      return;
    }
    await player.setAudioQuality(quality);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定要退出当前账号吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出登录'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await auth.logout();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}
