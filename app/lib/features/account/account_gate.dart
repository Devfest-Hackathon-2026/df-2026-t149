import 'package:flutter/material.dart';

import '../../core/auth/account_controller.dart';
import '../../core/widgets/state_view.dart';
import 'login_screen.dart';
import 'profile_form_screen.dart';
import '../../core/strings.dart';

/// ログインしてプロフィールを保存するまで、[child]（アプリの画面）の代わりにログインと入力の画面を表示する
class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.account, required this.child});

  final AccountController account;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (BuildContext context, Widget? _) => switch (account.state) {
      AccountReady() => child,
      AccountSignedOut() || AccountSigningIn() => LoginScreen(account: account),
      AccountNeedsProfile() => ProfileFormScreen(
        submitLabel: l10n.start,
        onSubmit: account.saveProfile,
        onSignOut: account.signOut,
      ),
      AccountProfileFailed(:final String message) => Scaffold(
        body: SafeArea(
          child: StateView(
            icon: Icons.cloud_off,
            title: message,
            primary: StateViewAction(
              l10n.reload,
              account.retry,
              icon: Icons.refresh,
            ),
            secondary: StateViewAction(l10n.logout, account.signOut),
          ),
        ),
      ),
      AccountChecking() || AccountLoadingProfile() => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    },
  );
}
