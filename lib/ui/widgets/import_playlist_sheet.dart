import 'package:flutter/material.dart';

import '../../controllers/auth_controller.dart';
import '../../models/music_models.dart';
import '../../services/music_api.dart';
import '../../services/playlist_import_service.dart';
import 'toast.dart';

Future<void> showImportPlaylistSheet({
  required BuildContext context,
  required MusicApi api,
  required AuthController auth,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  builder: (_) => ImportPlaylistSheet(api: api, auth: auth),
);

class ImportPlaylistSheet extends StatefulWidget {
  const ImportPlaylistSheet({super.key, required this.api, required this.auth});
  final MusicApi api;
  final AuthController auth;

  @override
  State<ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

enum _ImportStep { input, parsing, parsed, importing, complete }

class _ImportPlaylistSheetState extends State<ImportPlaylistSheet> {
  static const _newPlaylist = '__new__';
  final _controller = TextEditingController();
  final _nameController = TextEditingController();
  _ImportStep _step = _ImportStep.input;
  ExternalPlaylistParseResult? _result;
  String? _error;
  String _selectedListId = _newPlaylist;
  bool _cancelRequested = false;
  PlaylistImportProgress _progress = const PlaylistImportProgress();

  List<PlaylistSummary> get _targetPlaylists => widget.auth.playlists
      .where((p) => p.isCreatedPlaylist && p.listId?.isNotEmpty == true)
      .toList();
  bool get _busy => _step == _ImportStep.importing;

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Toast.info('请先粘贴 QQ 音乐 / 网易云歌单分享链接');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _ImportStep.parsing;
      _error = null;
    });
    try {
      final result = await widget.api
          .parseExternalPlaylist(text)
          .timeout(const Duration(minutes: 2));
      if (!mounted) return;
      if (result.importTracks.isEmpty) {
        throw const FormatException('歌单为空或不可见，请确认歌单已公开');
      }
      setState(() {
        _result = result;
        _nameController.text = result.playlistName;
        _selectedListId = _newPlaylist;
        _step = _ImportStep.parsed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ImportStep.input;
        _error = '解析失败：$e';
      });
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final result = _result;
    if (result == null) return;
    if (!widget.auth.isLoggedIn) {
      setState(() => _error = '请先登录 KA Music 的酷狗账号，再导入歌单');
      return;
    }
    if (_selectedListId == _newPlaylist &&
        _nameController.text.trim().isEmpty) {
      setState(() => _error = '请输入新歌单名称');
      return;
    }
    setState(() {
      _step = _ImportStep.importing;
      _error = null;
      _cancelRequested = false;
      _progress = const PlaylistImportProgress();
    });
    PlaylistSummary? target;
    try {
      if (_selectedListId == _newPlaylist) {
        final previousIds = _targetPlaylists.map((p) => p.listId).toSet();
        await widget.auth.createPlaylist(_nameController.text.trim());
        if (!mounted) return;
        if (widget.auth.errorMessage != null) {
          throw StateError(widget.auth.errorMessage!);
        }
        for (final playlist in _targetPlaylists) {
          if (!previousIds.contains(playlist.listId) &&
              playlist.title == _nameController.text.trim()) {
            target = playlist;
            _selectedListId = playlist.listId!;
            break;
          }
        }
      } else {
        for (final playlist in _targetPlaylists) {
          if (playlist.listId == _selectedListId) target = playlist;
        }
      }
      if (target == null) throw StateError('未找到目标歌单，请刷新后重新选择');
      final existing = await widget.api
          .playlistSongs(target.id, fetchAll: true)
          .timeout(const Duration(seconds: 30));
      final progress = await PlaylistImportService(widget.api).import(
        listId: target.listId!,
        tracks: result.importTracks,
        existingHashes: existing.map((song) => song.hash).toSet(),
        shouldCancel: () => !mounted || _cancelRequested,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      try {
        await widget.auth
            .refreshImportedPlaylist(target)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        // Songs have already been written. A list refresh must not turn the
        // completed import into a failure or keep the progress sheet open.
        debugPrint('Could not refresh imported playlist: $e');
      }
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _step = _ImportStep.complete;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ImportStep.parsed;
        _error = '导入出错：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final result = _result;
    final tracks = result?.importTracks ?? const <ExternalPlaylistTrack>[];
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('导入歌单', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('在 QQ 音乐或网易云分享歌单，复制链接粘贴到这里。QQ 歌单需设为公开。'),
              const SizedBox(height: 16),
              if (_step == _ImportStep.input ||
                  _step == _ImportStep.parsing) ...[
                TextField(
                  controller: _controller,
                  enabled: _step != _ImportStep.parsing,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: '粘贴歌单分享链接或整段分享文本',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _step == _ImportStep.parsing ? null : _parse,
                  icon: const Icon(Icons.link_rounded),
                  label: Text(_step == _ImportStep.parsing ? '解析中…' : '解析歌单'),
                ),
              ] else if (result != null) ...[
                Text(
                  result.playlistName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${tracks.length} 首歌曲 · ${result.sourcePlatform}'),
                if ((result.totalSongCount ?? tracks.length) > tracks.length)
                  Text(
                    '原歌单共 ${result.totalSongCount} 首，其中部分歌曲不可读取。',
                    style: TextStyle(color: colors.error),
                  ),
                const SizedBox(height: 8),
                const Text('按歌名、歌手和时长匹配曲库，跳过目标歌单中已有歌曲；未匹配项会列出。'),
                const SizedBox(height: 12),
                if (_step == _ImportStep.parsed) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedListId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '导入到'),
                    items: [
                      const DropdownMenuItem(
                        value: _newPlaylist,
                        child: Text('新建歌单'),
                      ),
                      for (final playlist in _targetPlaylists)
                        DropdownMenuItem(
                          value: playlist.listId,
                          child: Text(playlist.title),
                        ),
                    ],
                    onChanged: (id) =>
                        setState(() => _selectedListId = id ?? _newPlaylist),
                  ),
                  if (_selectedListId == _newPlaylist) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '新歌单名称'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('开始导入'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _step = _ImportStep.input;
                      _error = null;
                    }),
                    child: const Text('更换分享链接'),
                  ),
                ],
                if (_busy || _step == _ImportStep.complete) ...[
                  if (_busy)
                    LinearProgressIndicator(
                      value: tracks.isEmpty
                          ? null
                          : _progress.processed / tracks.length,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${_busy ? '正在导入' : (_cancelRequested ? '已停止' : '导入完成')}：'
                    '${_progress.processed}/${tracks.length} 首',
                  ),
                  Text(
                    '新增 ${_progress.added} · 已存在 ${_progress.duplicates} · '
                    '未匹配 ${_progress.unmatched.length} · 失败 ${_progress.failed.length}',
                  ),
                  if (_busy)
                    TextButton(
                      onPressed: _cancelRequested
                          ? null
                          : () => setState(() => _cancelRequested = true),
                      child: Text(_cancelRequested ? '当前请求结束后停止…' : '停止导入'),
                    ),
                  if (_step == _ImportStep.complete) ...[
                    if (_progress.unmatched.isNotEmpty)
                      ExpansionTile(
                        title: const Text('未匹配的歌曲'),
                        children: [
                          SelectableText(_progress.unmatched.join('\n')),
                        ],
                      ),
                    if (_progress.failed.isNotEmpty)
                      ExpansionTile(
                        title: const Text('请求失败的歌曲（可重新导入）'),
                        children: [SelectableText(_progress.failed.join('\n'))],
                      ),
                    if (_progress.failed.isNotEmpty || _cancelRequested)
                      TextButton(
                        onPressed: _import,
                        child: const Text('重新导入（跳过已有歌曲）'),
                      ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成'),
                    ),
                  ],
                ],
              ],
              if (_error case final message?) ...[
                const SizedBox(height: 10),
                Text(message, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
