import 'dart:async';

import 'package:flutter/material.dart';

import '../Ui/demo_login_credentials.dart';
import 'repository.dart';

/// All account entry points share one dialog, preserving input on failure.
class ShopAuthDialog extends StatefulWidget {
  const ShopAuthDialog({
    super.key,
    required this.repo,
    required this.t,
    this.admin = false,
    this.initialMode = 'login',
  });
  final ShopRepository repo;
  final String Function(String) t;
  final bool admin;
  final String initialMode;
  @override
  State<ShopAuthDialog> createState() => _ShopAuthDialogState();
}

class _ShopAuthDialogState extends State<ShopAuthDialog> {
  late String mode = widget.initialMode;
  final account = TextEditingController(),
      email = TextEditingController(),
      username = TextEditingController(),
      code = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool sending = false, requesting = false;
  int cooldown = 0;
  Timer? timer;
  String? error, notice;
  String t(String key) => widget.t(key);

  @override
  void dispose() {
    timer?.cancel();
    for (final field in [account, email, username, code, password, confirm]) {
      field.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    TextEditingController controller, {
    bool secret = false,
    bool mail = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey('auth-$key'),
      controller: controller,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: !secret,
      keyboardType: mail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(labelText: t(key)),
      onSubmitted: (_) {
        if (!sending && mode == 'login') unawaited(submit());
      },
    ),
  );

  Future<void> sendCode() async {
    if (requesting || cooldown > 0) return;
    setState(() {
      requesting = true;
      error = null;
      notice = null;
    });
    try {
      final result = await widget.repo.requestEmailCode(
        email.text.trim(),
        purpose: mode == 'register' ? 'register' : 'reset_password',
      );
      if (!mounted) return;
      setState(() {
        notice = result['demo_code'] is String
            ? '${t('demoEmailCode')}: ${result['demo_code']}'
            : t('codeSent');
        cooldown = 60;
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (tick) {
        if (!mounted) {
          tick.cancel();
          return;
        }
        setState(() => cooldown--);
        if (cooldown <= 0) tick.cancel();
      });
    } catch (e) {
      if (mounted) setState(() => error = t(e.toString()));
    } finally {
      if (mounted) setState(() => requesting = false);
    }
  }

  Future<void> submit() async {
    if (sending) return;
    setState(() {
      sending = true;
      error = null;
      notice = null;
    });
    try {
      if (mode == 'login') {
        if (account.text.trim().isEmpty || password.text.isEmpty) {
          throw Exception(t('required'));
        }
        await widget.repo.login(
          account.text.trim(),
          password.text,
          asAdmin: widget.admin,
        );
      } else {
        if (password.text.length < 8) throw Exception(t('passwordRules'));
        if (password.text != confirm.text) {
          throw Exception(t('passwordMismatch'));
        }
        if (mode == 'register') {
          await widget.repo.register(
            email: email.text.trim(),
            code: code.text.trim(),
            username: username.text.trim(),
            password: password.text,
            confirmPassword: confirm.text,
          );
        } else {
          await widget.repo.resetPassword(
            email: email.text.trim(),
            code: code.text.trim(),
            password: password.text,
            confirmPassword: confirm.text,
          );
          if (!mounted) return;
          setState(() {
            mode = 'login';
            account.text = email.text.trim();
            password.clear();
            confirm.clear();
            notice = t('passwordReset');
          });
          return;
        }
      }
      if (mounted && widget.repo.user != null) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = t(e.toString()));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(t(mode)),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 4,
              children: [
                for (final tab in ['login', 'register', 'forgotPassword'])
                  TextButton(
                    key: ValueKey('auth-tab-$tab'),
                    onPressed: sending || requesting
                        ? null
                        : () => setState(() {
                            mode = tab;
                            error = null;
                            notice = null;
                            password.clear();
                            confirm.clear();
                          }),
                    style: tab == mode
                        ? TextButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                          )
                        : null,
                    child: Text(t(tab)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(liveRegion: true, child: Text(notice!)),
              ),
            if (mode == 'login')
              field('loginAccount', account)
            else ...[
              field('email', email, mail: true),
              OutlinedButton(
                onPressed: requesting || sending || cooldown > 0
                    ? null
                    : sendCode,
                child: Text(
                  cooldown > 0 ? '${t('sendCode')} ($cooldown)' : t('sendCode'),
                ),
              ),
              const SizedBox(height: 16),
              field('emailCode', code),
              if (mode == 'register') field('username', username),
            ],
            field('password', password, secret: true),
            if (mode != 'login') ...[
              field('confirmPassword', confirm, secret: true),
              Text(t('passwordRules')),
            ],
            if (mode == 'login')
              DemoLoginCredentials(
                credentials: widget.repo.demoCredentials,
                hint: t('demoConfiguredHint'),
                customerLabel: t('demoCustomer'),
                adminLabel: t('merchant'),
                accountLabel: t('account'),
                passwordLabel: t('password'),
                copyLabel: t('copy'),
                copiedLabel: t('copied'),
                copyFailedLabel: t('copyFailed'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: sending ? null : () => Navigator.pop(context),
        child: Text(t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('auth-submit'),
        onPressed: sending || requesting ? null : submit,
        child: sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(t(mode == 'forgotPassword' ? 'resetPassword' : mode)),
      ),
    ],
  );
}
