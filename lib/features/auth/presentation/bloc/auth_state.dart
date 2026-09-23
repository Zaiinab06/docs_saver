import 'package:equatable/equatable.dart';
import '../../domain/entities/user_entity.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class Authenticated extends AuthState {
  final UserEntity user;

  const Authenticated(this.user);

  @override
  List<Object?> get props => [user];
}

class AuthSuccess extends AuthState {
  final UserEntity user;
  final String? message;

  const AuthSuccess(this.user, {this.message});

  @override
  List<Object?> get props => [user, message];
}

class Unauthenticated extends AuthState {}

class AuthNeedsConfirmation extends AuthState {
  final String email;
  final String? message;

  const AuthNeedsConfirmation({required this.email, this.message});

  @override
  List<Object?> get props => [email, message];
}

class AuthFailure extends AuthState {
  final String errorMessage;

  const AuthFailure(this.errorMessage);

  @override
  List<Object?> get props => [errorMessage];
}
