enum ConnectionState { 
  disconnected, 
  connecting, 
  connected, 
  sleeping 
}

extension ConnectionStateX on ConnectionState {
  bool get isConnected => this == ConnectionState.connected;
  bool get isConnecting => this == ConnectionState.connecting;
  bool get isSleeping => this == ConnectionState.sleeping;
  bool get isActive => 
      this == ConnectionState.connected || 
      this == ConnectionState.sleeping;
}
