import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_client.dart';
import '../theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.source, required this.name, this.type = ''});

  final String source;
  final String name;
  final String type;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  QrSession? _session;
  QrStatus? _status;
  String? _error;
  bool _creating = true;
  bool _checking = false;
  bool _succeeded = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _pollTimer?.cancel();
    final api = context.read<ApiClient>();
    setState(() {
      _creating = true;
      _error = null;
      _status = null;
      _session = null;
    });
    try {
      final session = await api.loginCreate(widget.source, type: widget.type);
      if (!mounted) return;
      if (session.key.isEmpty) {
        setState(() {
          _creating = false;
          _error = '平台没有返回登录会话，请尝试手动填写 Cookie';
        });
        return;
      }
      setState(() {
        _session = session;
        _creating = false;
        _status = const QrStatus(status: 'waiting', message: '等待扫码');
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error is ApiException ? error.message : '$error';
      });
    }
  }

  Future<void> _check() async {
    final session = _session;
    if (_checking || session == null || _succeeded) return;
    _checking = true;
    try {
      final status = await context.read<ApiClient>().loginCheck(widget.source, session.key, type: widget.type);
      if (!mounted) return;
      setState(() => _status = status);
      if (status.success) {
        _pollTimer?.cancel();
        setState(() => _succeeded = true);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.of(context).pop(true);
      } else if (status.terminal) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Transient network errors are ignored; the next poll retries.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.name} 扫码登录', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(colors: [AppColors.accent, AppColors.accentAlt]),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, size: 30, color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _succeeded ? '登录成功' : '使用 ${widget.name} App 扫码',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _succeeded ? 'Cookie 已保存，正在返回…' : '扫码后请在手机端确认登录',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: 272,
                    height: 272,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))],
                    ),
                    child: Center(child: _qrContent()),
                  ),
                  const SizedBox(height: 22),
                  if (_succeeded)
                    const _StatusPill(
                      icon: Icons.check_circle_rounded,
                      color: Color(0xFF54D68C),
                      text: '登录成功',
                    )
                  else if (_status != null)
                    _StatusPill(
                      icon: _statusIcon(_status!.status),
                      color: _statusColor(_status!.status),
                      text: _statusText(_status!),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, height: 1.5, color: Colors.redAccent.withValues(alpha: 0.85)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _creating ? null : _create,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('刷新二维码'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.keyboard_rounded, size: 17),
                        label: const Text('稍后手动登录'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Colors.white.withValues(alpha: 0.38)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '二维码有效期约 3-5 分钟。扫码后如果手机端没有反应，可以返回设置页手动填写 Cookie。',
                            style: TextStyle(fontSize: 11, height: 1.55, color: Colors.white.withValues(alpha: 0.42)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrContent() {
    if (_creating) {
      return const CircularProgressIndicator(strokeWidth: 2.4);
    }
    if (_succeeded) {
      return const Icon(Icons.check_rounded, size: 96, color: Color(0xFF0A0A11));
    }
    final session = _session;
    if (session == null) {
      return Icon(Icons.qr_code_2_rounded, size: 96, color: Colors.black.withValues(alpha: 0.18));
    }
    final image = session.imageUrl;
    if (image.startsWith('data:image')) {
      final comma = image.indexOf(',');
      if (comma > 0) {
        try {
          final bytes = base64Decode(image.substring(comma + 1));
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Image.memory(bytes, width: 244, height: 244, fit: BoxFit.contain, gaplessPlayback: true),
          );
        } catch (_) {
          // fall through to QR rendering
        }
      }
    }
    if (image.startsWith('http')) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: CachedNetworkImage(
          imageUrl: image,
          width: 244,
          height: 244,
          fit: BoxFit.contain,
          placeholder: (_, _) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          errorWidget: (_, _, _) => _qrFromUrl(session.url),
        ),
      );
    }
    return _qrFromUrl(session.url);
  }

  Widget _qrFromUrl(String url) {
    if (url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '无法生成二维码\n请手动填写 Cookie',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black.withValues(alpha: 0.55)),
        ),
      );
    }
    return QrImageView(
      data: url,
      version: QrVersions.auto,
      size: 244,
      padding: const EdgeInsets.all(14),
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
    );
  }

  String _statusText(QrStatus status) {
    switch (status.status) {
      case 'waiting':
        return status.message.isEmpty ? '等待扫码' : status.message;
      case 'scanned':
        return status.message.isEmpty ? '已扫码，请在手机上确认' : status.message;
      case 'expired':
        return '二维码已过期，请刷新';
      case 'failed':
        return status.message.isEmpty ? '登录失败，请重试' : status.message;
      default:
        return status.message.isEmpty ? status.status : status.message;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'scanned':
        return Icons.phone_android_rounded;
      case 'expired':
        return Icons.timer_off_rounded;
      case 'failed':
        return Icons.error_outline_rounded;
      default:
        return Icons.qr_code_scanner_rounded;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'scanned':
        return const Color(0xFF54D68C);
      case 'expired':
      case 'failed':
        return const Color(0xFFFF8A8A);
      default:
        return AppColors.accent;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
