import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DemoLoginCredentials extends StatefulWidget {
  const DemoLoginCredentials({
    super.key,
    this.hint = '当前演示部署的实际账户和密码，可点击复制后粘贴登录。',
    this.customerLabel = '客户',
    this.adminLabel = '管理员',
    this.accountLabel = '账户',
    this.passwordLabel = '密码',
    this.copyLabel = '复制',
    this.copiedLabel = '已复制',
    this.copyFailedLabel = '复制失败，请选中文本复制。',
    this.credentials = const [],
  });

  final String hint;
  final String customerLabel;
  final String adminLabel;
  final String accountLabel;
  final String passwordLabel;
  final String copyLabel;
  final String copiedLabel;
  final String copyFailedLabel;
  final List<Map<String, dynamic>> credentials;

  @override
  State<DemoLoginCredentials> createState() => _DemoLoginCredentialsState();
}

class _DemoLoginCredentialsState extends State<DemoLoginCredentials> {
  String? _copiedField;
  bool _copyFailed = false;
  int _copySequence = 0;
  OverlayEntry? _tipEntry;
  Timer? _tipTimer;

  void _removeTip() {
    _tipTimer?.cancel();
    _tipTimer = null;
    final entry = _tipEntry;
    _tipEntry = null;
    entry?.remove();
    entry?.dispose();
  }

  void _tip(String text) {
    _removeTip();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _tipEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context), media = MediaQuery.of(context);
        return Positioned.fill(
          child: IgnorePointer(
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  24 + media.viewInsets.bottom,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      child: Material(
                        key: const ValueKey('demo-copy-tip'),
                        color: theme.colorScheme.inverseSurface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_tipEntry!);
    _tipTimer = Timer(const Duration(seconds: 2), _removeTip);
  }

  @override
  void dispose() {
    _removeTip();
    super.dispose();
  }

  Future<void> _copy(String field, String value) async {
    final sequence = ++_copySequence;
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted || sequence != _copySequence) return;
      setState(() {
        _copiedField = field;
        _copyFailed = false;
      });
      _tip(widget.copiedLabel);
    } catch (_) {
      if (!mounted || sequence != _copySequence) return;
      setState(() {
        _copiedField = null;
        _copyFailed = true;
      });
      _tip(widget.copyFailedLabel);
    }
  }

  Widget _field(String id, String role, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              SelectableText(
                value,
                key: ValueKey('demo-$id'),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Semantics(
            label: '$role $label',
            liveRegion: true,
            child: TextButton(
              key: ValueKey('copy-demo-$id'),
              onPressed: () => _copy(id, value),
              child: Text(
                _copiedField == id ? widget.copiedLabel : widget.copyLabel,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _role(String id, String role, String account, String password) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(role, style: Theme.of(context).textTheme.titleSmall),
          _field('$id-account', role, widget.accountLabel, account),
          _field('$id-password', role, widget.passwordLabel, password),
        ],
      );

  @override
  Widget build(BuildContext context) => widget.credentials.isEmpty
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.hint),
            const SizedBox(height: 12),
            for (final credential in widget.credentials) ...[
              _role(
                '${credential['role']}',
                credential['role'] == 'admin'
                    ? widget.adminLabel
                    : widget.customerLabel,
                '${credential['account']}',
                '${credential['password']}',
              ),
              const SizedBox(height: 16),
            ],
            if (_copyFailed) ...[
              const SizedBox(height: 8),
              Semantics(liveRegion: true, child: Text(widget.copyFailedLabel)),
            ],
          ],
        );
}
