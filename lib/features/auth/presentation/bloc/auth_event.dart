import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class SignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String? fullName;

  const SignUpRequested({
    required this.email,
    required this.password,
    this.fullName,
  });

  @override
  List<Object?> get props => [email, password, fullName];
}

class SignInRequested extends AuthEvent {
  final String email;
  final String password;

  const SignInRequested({
    required this.email,
    required this.password,
  });

  @override
  List<Object?> get props => [email, password];
}

class SignOutRequested extends AuthEvent {}
