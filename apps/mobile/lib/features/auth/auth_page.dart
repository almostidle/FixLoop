import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/widgets.dart';
import '../../state/app_controller.dart';

/// Live Sign In and Student Registration screen using FixLoop REST auth endpoints.
class AuthPage extends StatefulWidget {
  const AuthPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _registerMode = false;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final fullName = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (_registerMode && fullName.isEmpty)) {
      setState(() => _errorMessage = 'Please complete all required fields.');
      return;
    }

    widget.controller.clearBanner();
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      if (_registerMode) {
        await widget.controller.registerAndSignIn(
          email: email,
          password: password,
          fullName: fullName,
        );
      } else {
        await widget.controller.signIn(email: email, password: password);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = _formatApiError(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not sign in right now. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _formatApiError(ApiException error) {
    if (error.details.isNotEmpty) {
      final first = error.details.entries.first;
      return '${first.key}: ${first.value}';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final banner = _errorMessage ?? widget.controller.bannerError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const MoonGraphic(phase: MoonPhase.almostFull, size: 52, orbit: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Fix Loop', style: text.headlineLarge),
                            Text(
                              'Report it. Track it. Close the loop.',
                              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Sign in'),
                        icon: Icon(Icons.login_rounded),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Register'),
                        icon: Icon(Icons.person_add_alt_1_rounded),
                      ),
                    ],
                    selected: <bool>{_registerMode},
                    onSelectionChanged: _submitting
                        ? null
                        : (selected) => setState(() {
                              _registerMode = selected.first;
                              _errorMessage = null;
                            }),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _registerMode ? 'Create student account' : 'Welcome back',
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _registerMode
                        ? 'Use your @bmu.edu.in university email address.'
                        : 'Sign in with your campus account to view or report issues.',
                    style: text.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  if (banner != null && banner.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(Icons.error_outline_rounded, size: 20, color: colors.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              banner,
                              style: text.bodyMedium?.copyWith(
                                color: colors.onErrorContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (_registerMode) ...<Widget>[
                    TextField(
                      key: const ValueKey<String>('auth-fullname'),
                      controller: _nameController,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        hintText: 'Aarav Mehta',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    key: const ValueKey<String>('auth-email'),
                    controller: _emailController,
                    enabled: !_submitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'University email',
                      hintText: 'name@bmu.edu.in',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey<String>('auth-password'),
                    controller: _passwordController,
                    enabled: !_submitting,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: _registerMode ? 'Use at least 12 characters or a passphrase.' : null,
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  PrimaryAction(
                    key: const ValueKey<String>('auth-submit'),
                    label: _registerMode ? 'Create account' : 'Sign in',
                    icon: Icons.arrow_forward_rounded,
                    busy: _submitting,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.shield_outlined, size: 18, color: colors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your identity is hidden from peers and service handlers by default; '
                          'only you and campus administrators can view reporter details.',
                          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
