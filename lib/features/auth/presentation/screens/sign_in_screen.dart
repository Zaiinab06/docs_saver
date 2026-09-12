import 'package:flutter/material.dart';
import 'auth_screen.dart';
export 'auth_screen.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthScreen(initialMode: AuthMode.signIn);
  }
}
