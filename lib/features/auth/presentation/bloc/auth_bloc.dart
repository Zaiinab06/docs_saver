// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import '../../domain/usecases/get_current_user_usecase.dart';
import '../../domain/usecases/sign_in_usecase.dart';
import '../../domain/usecases/sign_out_usecase.dart';
import '../../domain/usecases/sign_up_usecase.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SignUpUseCase signUpUseCase;
  final SignInUseCase signInUseCase;
  final SignOutUseCase signOutUseCase;
  final GetCurrentUserUseCase getCurrentUserUseCase;
  final AuthRepository authRepository;
  StreamSubscription? _authSubscription;

  AuthBloc({
    required this.signUpUseCase,
    required this.signInUseCase,
    required this.signOutUseCase,
    required this.getCurrentUserUseCase,
    required this.authRepository,
  }) : super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<SignUpRequested>(_onSignUpRequested);
    on<SignInRequested>(_onSignInRequested);
    on<SignOutRequested>(_onSignOutRequested);

    _authSubscription = authRepository.authStateChanges.listen((user) {
      if (user != null) {
        add(AuthCheckRequested());
      } else {
        add(AuthCheckRequested());
      }
    });
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final user = getCurrentUserUseCase();
    if (user != null) {
      emit(Authenticated(user));
    } else {
      emit(Unauthenticated());
    }
  }

  Future<void> _onSignUpRequested(
    SignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      print('DEBUG: AuthBloc handling SignUpRequested for email: ${event.email}');
      final user = await signUpUseCase(
        email: event.email,
        password: event.password,
        fullName: event.fullName,
      );
      print('DEBUG: SignUp successful in AuthBloc for user: ${user.id}, email: ${user.email}');
      emit(AuthSuccess(user));
      emit(Authenticated(user));
    } on AuthException catch (e, stack) {
      print('DEBUG: AuthException in AuthBloc _onSignUpRequested: ${e.message} (status: ${e.statusCode})');
      print('DEBUG: Stack trace: $stack');
      emit(AuthFailure(e.message));
    } catch (e, stack) {
      print('DEBUG: Generic exception in AuthBloc _onSignUpRequested: $e');
      print('DEBUG: Stack trace: $stack');
      emit(AuthFailure(_cleanErrorMessage(e)));
    }
  }

  Future<void> _onSignInRequested(
    SignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await signInUseCase(
        email: event.email,
        password: event.password,
      );
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthFailure(_cleanErrorMessage(e)));
      emit(Unauthenticated());
    }
  }

  Future<void> _onSignOutRequested(
    SignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await signOutUseCase();
      emit(Unauthenticated());
    } catch (e) {
      emit(AuthFailure(_cleanErrorMessage(e)));
      emit(Unauthenticated());
    }
  }

  String _cleanErrorMessage(dynamic error) {
    if (error is AuthException) {
      return error.message;
    }
    final raw = error.toString();
    final regex = RegExp(r'AuthException\s*\(\s*message:\s*([^,)]+)');
    final match = regex.firstMatch(raw);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.trim();
    }
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '').trim();
    }
    return raw;
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
