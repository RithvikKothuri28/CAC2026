import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/farm_domain.dart';
import '../../app/theme/farm_theme.dart';
import '../../core/widgets/components.dart';
import '../workspace/workspace_controller.dart';

Future<bool> showAuth(
  BuildContext context,
  WorkspaceController state, {
  bool reauthenticate = false,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) =>
            _AuthDialog(state: state, reauthenticate: reauthenticate),
      ) ??
      false;
}

class _AuthDialog extends StatefulWidget {
  const _AuthDialog({required this.state, required this.reauthenticate});
  final WorkspaceController state;
  final bool reauthenticate;
  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool signup = false, busy = false;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    _email.text = widget.state.cloud?.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final auth = widget.state.cloud!.auth;
      if (widget.reauthenticate) {
        await auth.reauthenticate(_email.text, _password.text);
      } else if (signup) {
        await auth.signUp(_email.text, _password.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
      if (!widget.reauthenticate) widget.state.leaveSample();
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reauthenticate
          ? 'Confirm your identity'
          : signup
          ? 'Create your account'
          : 'Welcome back',
    ),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (value) =>
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value ?? '')
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              autofillHints: [
                signup ? AutofillHints.newPassword : AutofillHints.password,
              ],
              validator: (value) => (value ?? '').isEmpty
                  ? 'Enter a password'
                  : signup && value!.length < 8
                  ? 'Use at least eight characters'
                  : null,
              onFieldSubmitted: (_) {
                if (!busy) submit();
              },
            ),
            if (!widget.reauthenticate)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() {
                            busy = true;
                            error = null;
                            notice = null;
                          });
                          try {
                            await widget.state.cloud!.auth.resetPassword(
                              _email.text,
                            );
                            if (mounted) {
                              setState(
                                () => notice =
                                    'If this email has an account, password reset instructions have been sent.',
                              );
                            }
                          } catch (failure) {
                            if (mounted) {
                              setState(() => error = failure.toString());
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: const Text('Reset password'),
                ),
              ),
            if (error != null) Notice(error!, error: true),
            if (notice != null) Notice(notice!),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (!widget.reauthenticate)
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  signup = !signup;
                  error = null;
                }),
          child: Text(signup ? 'I have an account' : 'Create an account'),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : submit,
        child: Text(
          widget.reauthenticate
              ? 'Confirm'
              : signup
              ? 'Create account'
              : 'Sign in',
        ),
      ),
    ],
  );
}

Future<void> createFarmDialog(
  BuildContext context,
  WorkspaceController state,
) async {
  final defaults = FarmSettings.fromJson(
    jsonDecode(
          await rootBundle.loadString('assets/config/default_settings.json'),
        )
        as Map<String, dynamic>,
  );
  if (!context.mounted) return;
  final form = GlobalKey<FormState>();
  var name = '';
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Create your farm'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                onChanged: (value) => name = value,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Farm name'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a farm name' : null,
              ),
              const SizedBox(height: 18),
              Text(
                'Configured starting inputs: ${defaults.currencyCode}; objective weights ${defaults.optimization.weights.entries.where((e) => e.value > 0).map((e) => '${e.key.name} ${percentage(e.value)}').join(', ')}; '
                '${percentage(defaults.priceGrowthRate)} annual price growth; ${percentage(defaults.expenseInflationRate)} expense inflation. Review model assumptions before analysis.',
                style: const TextStyle(color: FarmTheme.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, name.trim());
            }
          },
          child: const Text('Create farm'),
        ),
      ],
    ),
  );
  if (result != null) {
    await state.perform('Creating farm', () => state.createFarm(result));
  }
}
