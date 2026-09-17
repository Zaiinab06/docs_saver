import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final String id;
  final String? email;
  final String? fullName;
  final bool hasSession;

  const UserEntity({
    required this.id,
    this.email,
    this.fullName,
    this.hasSession = true,
  });

  @override
  List<Object?> get props => [id, email, fullName, hasSession];
}
