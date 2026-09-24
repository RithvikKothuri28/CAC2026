import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../data/data.dart';
import '../../core/widgets/components.dart';
import '../workspace/workspace_controller.dart';

Future<bool> showAuth(
  BuildContext context,
  WorkspaceController state, {
  bool reauthenticate = false,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
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
  final _displayName = TextEditingController();
  final _confirmPassword = TextEditingController();
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
    _displayName.dispose();
    _confirmPassword.dispose();
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
        await auth.signUp(
          _email.text,
          _password.text,
          displayName: _displayName.text.trim(),
        );
        widget.state.notice =
            'Account created. Check your email to verify your address.';
      } else {
        await auth.signIn(_email.text, _password.text);
      }
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
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (signup) ...[
                TextFormField(
                  controller: _displayName,
                  decoration: const InputDecoration(labelText: 'Display name'),
                  autofillHints: const [AutofillHints.name],
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
              ],
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
              if (signup) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) =>
                      value == _password.text ? null : 'Passwords must match',
                  onFieldSubmitted: (_) {
                    if (!busy) submit();
                  },
                ),
              ],
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
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CreateFarmDialog(state: state),
  );
}

class _CreateFarmDialog extends StatefulWidget {
  const _CreateFarmDialog({required this.state});
  final WorkspaceController state;

  @override
  State<_CreateFarmDialog> createState() => _CreateFarmDialogState();
}

class _CreateFarmDialogState extends State<_CreateFarmDialog> {
  final _form = GlobalKey<FormState>();
  // Retries retain this id, including a retry after a network timeout.
  final _farmId = const Uuid().v4();
  final _name = TextEditingController();
  final _country = TextEditingController();
  final _region = TextEditingController();
  final _currency = TextEditingController();
  final _acres = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _country, _region, _currency, _acres]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!widget.state.signedIn) {
        throw const AuthenticationFailure('Sign in before creating a farm.');
      }
      await widget.state.createFarm(
        id: _farmId,
        name: _name.text,
        country: _country.text,
        region: _region.text,
        currencyCode: _currency.text,
        declaredAcres: double.parse(_acres.text.trim()),
      );
      // The repository completes only after the server accepts the write.
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) setState(() => _error = failure.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Add New Farm'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  autofocus: true,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Farm name'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a farm name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _country,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Country'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter a country' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _region,
                  enabled: !_saving,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'State or region',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter a state or region'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currency,
                  enabled: !_saving,
                  maxLength: 3,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Currency code',
                    hintText: 'Three-letter code, such as USD',
                  ),
                  validator: (value) =>
                      RegExp(
                        r'^[A-Z]{3}$',
                      ).hasMatch((value ?? '').trim().toUpperCase())
                      ? null
                      : 'Enter a three-letter currency code',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _acres,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total farm acres',
                  ),
                  validator: (value) {
                    final acres = double.tryParse((value ?? '').trim());
                    return acres == null || !acres.isFinite || acres <= 0
                        ? 'Enter a positive number of acres'
                        : null;
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add fields, crops, and operating assumptions after your farm is saved. Review the configurable planning defaults before calculating.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Notice(_error!, error: true),
                ],
                if (_saving) ...[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    'Waiting for Cloud Firestore to accept your farm...',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
