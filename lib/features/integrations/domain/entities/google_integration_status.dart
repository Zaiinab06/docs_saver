import 'package:equatable/equatable.dart';

enum GoogleConnectionState {
  notConnected,
  connecting,
  connected,
  connectionFailed,
  cancelled,
}

class GoogleIntegrationStatus extends Equatable {
  final GoogleConnectionState state;
  final String? email;
  final String? name;
  final String? errorMessage;
  final DateTime? updatedAt;

  const GoogleIntegrationStatus({
    this.state = GoogleConnectionState.notConnected,
    this.email,
    this.name,
    this.errorMessage,
    this.updatedAt,
  });

  bool get isConnected => state == GoogleConnectionState.connected;
  bool get isConnecting => state == GoogleConnectionState.connecting;

  GoogleIntegrationStatus copyWith({
    GoogleConnectionState? state,
    String? email,
    String? name,
    String? errorMessage,
    DateTime? updatedAt,
  }) {
    return GoogleIntegrationStatus(
      state: state ?? this.state,
      email: email ?? this.email,
      name: name ?? this.name,
      errorMessage: errorMessage ?? this.errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [state, email, name, errorMessage, updatedAt];
}
