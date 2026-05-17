import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import 'config/app_config.dart';
import 'controllers/auth_controller.dart';
import 'controllers/player_controller.dart';
import 'core/api_client.dart';
import 'services/music_audio_handler.dart';
import 'services/music_api.dart';
import 'ui/app_theme.dart';
import 'ui/pages/app_shell.dart';
import 'ui/pages/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final client = ApiClient();
  final api = MusicApi(client);
  final audioHandler = await AudioService.init(
    builder: MusicAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'kgka_music_hl.playback',
      androidNotificationChannelName: 'KA Music 播放控制',
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(KaMusicApp(client: client, api: api, audioHandler: audioHandler));
}

class KaMusicApp extends StatefulWidget {
  const KaMusicApp({
    super.key,
    required this.client,
    required this.api,
    required this.audioHandler,
  });

  final ApiClient client;
  final MusicApi api;
  final MusicAudioHandler audioHandler;

  @override
  State<KaMusicApp> createState() => _KaMusicAppState();
}

class _KaMusicAppState extends State<KaMusicApp> {
  late final ApiClient _client;
  late final MusicApi _api;
  late final AuthController _auth;
  late final PlayerController _player;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _api = widget.api;
    _auth = AuthController(_api);
    _player = PlayerController(_api, widget.audioHandler);
    _auth.restore();
  }

  @override
  void dispose() {
    _auth.dispose();
    _player.dispose();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: AnimatedBuilder(
        animation: _auth,
        builder: (context, _) {
          if (_auth.isRestoring) {
            return const _RestoreSessionPage();
          }

          if (!_auth.isLoggedIn) {
            return LoginPage(auth: _auth);
          }

          return AppShell(api: _api, auth: _auth, player: _player);
        },
      ),
    );
  }
}

class _RestoreSessionPage extends StatelessWidget {
  const _RestoreSessionPage();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 14),
            Text(
              '正在进入',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
