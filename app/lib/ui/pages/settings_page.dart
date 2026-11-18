import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_state.dart';
import '../../core/backend.dart';
import '../../core/models.dart';
import '../../core/permissions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, String> _cookies = {};
  bool _loadingCookies = true;
  String _appVersion = '';
  String _coreVersion = '';
  NotificationStatus? _notificationStatus;

  @override
  void initState() {
    super.initState();
    _loadCookies();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final api = context.read<ApiClient>();
    String appVersion = '';
    String coreVersion = '';
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.isEmpty ? '' : '+${info.buildNumber}';
      appVersion = '${info.version}$build';
    } catch (_) {}
    try {
      final health = await api.health();
      coreVersion = '${health['version'] ?? ''}';
    } catch (_) {}
    final status = await AppPermissions.notificationStatus();
    if (!mounted) return;
    setState(() {
      _appVersion = appVersion;
      _coreVersion = coreVersion;
      _notificationStatus = status;
    });
  }

  Future<void> _refreshNotificationStatus() async {
    final status = await AppPermissions.notificationStatus();
    if (!mounted) return;
    setState(() => _notificationStatus = status);
  }

  /// Posts a normal notification so the user can verify the permission and
  /// channel without starting playback.
  Future<void> _sendTestNotification() async {
    final result = await AppPermissions.sendTestNotification();
    if (!mounted) return;
    final message = switch (result) {
      'posted' => '测试通知已发送，请下拉通知栏查看',
      'permission' => '通知权限未开启，请在系统设置中允许「声屿」通知',
      'app_disabled' => '系统已关闭「声屿」通知，请点按「播放通知」去开启',
      'channel_disabled' => '「通知测试」渠道被关闭，请在通知设置中重新允许',
      _ => '无法发送测试通知，请检查系统通知设置',
    };
    showAppSnack(context, message);
    await _refreshNotificationStatus();
  }

  Future<void> _loadCookies() async {
    final api = context.read<ApiClient>();
    try {
      final cookies = await api.cookies();
      if (!mounted) return;
      setState(() {
        _cookies = cookies;
        _loadingCookies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCookies = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final themeMode = switch (app.settings.themeMode) {
      'light' => 'light',
      'dark' => 'dark',
      _ => 'system',
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
        children: [
          _sectionTitle('默认搜索源', '搜索时会同时查询勾选的平台'),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in app.sources.where((e) => e.search))
                      FilterChip(
                        label: Text(source.name),
                        selected: app.defaultSources.contains(source.id),
                        showCheckmark: false,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: app.defaultSources.contains(source.id) ? FontWeight.w700 : FontWeight.w500,
                        ),
                        selectedColor: AppColors.accent.withValues(alpha: 0.24),
                        backgroundColor: context.neutral(0.045),
                        side: BorderSide.none,
                        onSelected: (selected) async {
                          final next = List<String>.from(app.defaultSources);
                          if (selected) {
                            if (!next.contains(source.id)) next.add(source.id);
                          } else {
                            if (next.length <= 1) {
                              showAppSnack(context, '至少保留一个搜索源');
                              return;
                            }
                            next.remove(source.id);
                          }
                          await app.setDefaultSources(next);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        final all = app.sources.where((e) => e.search).map((e) => e.id).toList();
                        app.setDefaultSources(all);
                      },
                      child: const Text('全选', style: TextStyle(fontSize: 11.5)),
                    ),
                    TextButton(
                      onPressed: () => app.setDefaultSources(const ['netease', 'qq', 'kugou', 'kuwo', 'migu']),
                      child: const Text('恢复默认', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _sectionTitle('账号与登录', '扫码或填写 Cookie 后可播放会员歌曲、查看我的歌单'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: _loadingCookies
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                : Column(
                    children: [
                      for (final source in app.sources)
                        if (source.qrLogin || source.note.isNotEmpty || app.defaultSources.contains(source.id))
                          _accountTile(context, app, source),
                      if (app.sources.isEmpty)
                        const ListTile(title: Text('暂无音乐源')),
                    ],
                  ),
          ),
          _sectionTitle('下载', '修改下载目录与文件命名规则'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('下载目录'),
                  subtitle: Text(app.settings.downloadDir, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () async {
                    final value = await _askText(context, '下载目录', app.settings.downloadDir);
                    if (value == null || value.trim().isEmpty) return;
                    await _updateSettings(app, downloadDir: value.trim());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_rename_outline_rounded),
                  title: const Text('文件命名'),
                  subtitle: Text(app.settings.filenameTemplate),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                  onTap: () async {
                    final value = await _askText(
                      context,
                      '文件命名模板',
                      app.settings.filenameTemplate,
                      hint: '例如 {artist} - {name}',
                      description: '可用变量：{artist} 歌手、{name} 歌名、{album} 专辑、{source} 平台',
                    );
                    if (value == null || value.trim().isEmpty) return;
                    await app.setFilenameTemplate(value.trim());
                    if (context.mounted) showAppSnack(context, '已保存');
                  },
                ),
              ],
            ),
          ),
          _sectionTitle('外观', '选择跟随系统、浅色或深色界面'),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      expandedInsets: EdgeInsets.zero,
                      segments: const [
                        ButtonSegment(
                          value: 'system',
                          icon: Icon(Icons.brightness_auto_rounded, size: 16),
                          label: Text('跟随系统'),
                        ),
                        ButtonSegment(
                          value: 'light',
                          icon: Icon(Icons.light_mode_rounded, size: 16),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: 'dark',
                          icon: Icon(Icons.dark_mode_rounded, size: 16),
                          label: Text('深色'),
                        ),
                      ],
                      selected: {themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (values) async {
                        await app.setThemeMode(values.first);
                        if (context.mounted) showAppSnack(context, '外观已更新');
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_full_rounded),
                  title: const Text('点歌后进入播放页'),
                  subtitle: const Text('关闭后点歌只开始播放，停留当前列表'),
                  trailing: Switch(
                    value: app.tapSongOpensPlayer,
                    onChanged: (value) => app.setTapSongOpensPlayer(value),
                  ),
                ),
              ],
            ),
          ),
          _sectionTitle('关于', null),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: const Text('声屿'),
                  subtitle: Text(
                    '版本 ${_appVersion.isEmpty ? '—' : _appVersion} · 核心 ${_coreVersion.isEmpty ? '—' : _coreVersion}',
                  ),
                ),
                if (_notificationStatus != null)
                  ListTile(
                    leading: Icon(
                      _notificationStatus!.enabled
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_off_rounded,
                      color: _notificationColor(context),
                    ),
                    title: const Text('播放通知'),
                    subtitle: Text(_notificationStatus!.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '刷新通知状态',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          onPressed: _refreshNotificationStatus,
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                    onTap: AppPermissions.openChannelSettings,
                  ),
                if (_notificationStatus != null)
                  ListTile(
                    leading: const Icon(Icons.notification_add_rounded),
                    title: const Text('发送测试通知'),
                    subtitle: const Text('不播放音乐，只验证通知权限与渠道是否正常'),
                    trailing: const Icon(Icons.send_rounded, size: 18),
                    onTap: _sendTestNotification,
                  ),
                ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: const Text('本地音乐核心'),
                  subtitle: Text(context.read<ApiClient>().baseUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_rounded),
                  title: const Text('数据目录'),
                  subtitle: Text(BackendService.instance.handle?.dataDir ?? '-'),
                ),
                const ListTile(
                  leading: Icon(Icons.code_rounded),
                  title: Text('开源组件'),
                  subtitle: Text('Flutter · just_audio · music-lib'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 18, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 13,
            margin: const EdgeInsets.only(top: 2, right: 8),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 10.5, color: context.neutral(0.34))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Green when the media notification can be posted, amber when the channel
  /// is muted, red when the app or permission blocks notifications.
  Color _notificationColor(BuildContext context) {
    final status = _notificationStatus;
    if (status == null) return context.neutral(0.4);
    if (!status.enabled) return Colors.redAccent;
    if (!status.channelEnabled || status.channelImportance <= 0) return const Color(0xFFFFB02E);
    return const Color(0xFF54D68C);
  }

  Widget _accountTile(BuildContext context, AppState app, SourceInfo source) {
    final hasCookie = (_cookies[source.id] ?? '').isNotEmpty;
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: (hasCookie ? const Color(0xFF54D68C) : AppColors.accent).withValues(alpha: 0.16),
        child: Icon(
          hasCookie ? Icons.check_rounded : Icons.account_circle_outlined,
          size: 18,
          color: hasCookie ? const Color(0xFF54D68C) : AppColors.accent,
        ),
      ),
      title: Text(source.name),
      subtitle: Text(
        hasCookie ? '已登录 · 会员歌曲可用' : (source.qrLogin ? '未登录 · 可扫码登录' : (source.note.isEmpty ? '未登录' : source.note)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: () => _showAccountSheet(context, app, source, hasCookie),
    );
  }

  Future<void> _showAccountSheet(BuildContext context, AppState app, SourceInfo source, bool hasCookie) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Text(source.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  if (source.note.isNotEmpty)
                    Expanded(
                      child: Text(source.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: context.neutral(0.4))),
                    ),
                ],
              ),
            ),
            if (source.qrLogin)
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('扫码登录'),
                subtitle: const Text('使用手机 App 扫描二维码'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await _qrLogin(context, source);
                },
              ),
            if (source.id == 'qq')
              ListTile(
                leading: const Icon(Icons.wechat_rounded),
                title: const Text('微信扫码登录'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await _qrLogin(context, source, type: 'wx');
                },
              ),
            ListTile(
              leading: const Icon(Icons.key_rounded),
              title: Text(hasCookie ? '更新 Cookie' : '手动填写 Cookie'),
              onTap: () async {
                Navigator.pop(sheet);
                await _editCookie(context, source, hasCookie);
              },
            ),
            if (hasCookie)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                title: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(sheet);
                  await app.api.setCookie(source.id, '');
                  await _loadCookies();
                  if (context.mounted) showAppSnack(context, '已退出 ${source.name}');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _qrLogin(BuildContext context, SourceInfo source, {String type = ''}) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => LoginPage(source: source.id, name: source.name, type: type),
    ));
    if (result == true) {
      await _loadCookies();
      if (context.mounted) showAppSnack(context, '${source.name} 登录成功');
    }
  }

  Future<void> _editCookie(BuildContext context, SourceInfo source, bool hasCookie) async {
    final controller = TextEditingController(text: _cookies[source.id] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${source.name} Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('从浏览器开发者工具复制 Cookie 请求头，粘贴到下方。',
                style: TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Cookie 内容'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          if (hasCookie)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('清除', style: TextStyle(color: Colors.redAccent)),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    await context.read<ApiClient>().setCookie(source.id, result.trim());
    await _loadCookies();
    if (context.mounted) showAppSnack(context, result.trim().isEmpty ? '已清除 Cookie' : 'Cookie 已保存');
  }

  Future<void> _updateSettings(AppState app, {String? downloadDir}) async {
    final api = context.read<ApiClient>();
    try {
      final patch = {
        'downloadDir': downloadDir ?? app.settings.downloadDir,
        'filenameTemplate': app.settings.filenameTemplate,
        'embedLyrics': true,
        'defaultSearchSources': app.defaultSources,
        'preferredQuality': 'best',
        'themeMode': app.settings.themeMode,
      };
      await api.updateSettings(patch);
      await app.initialize();
      if (mounted) showAppSnack(context, '已保存');
    } catch (error) {
      if (mounted) showAppSnack(context, '$error');
    }
  }

  Future<String?> _askText(BuildContext context, String title, String initial,
      {String? hint, String? description}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null) ...[
              Text(description, style: const TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
