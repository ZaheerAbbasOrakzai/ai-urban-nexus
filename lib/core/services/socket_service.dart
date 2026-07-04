// lib/core/services/socket_service.dart
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ai_urban_nexus_mobile/core/config/api_endpoints.dart';
import 'package:ai_urban_nexus_mobile/models/vehicle_model.dart';
import 'package:flutter/foundation.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService();
});

class SocketService {
  late io.Socket _socket;
  final List<VehicleModel> _vehicles = [];
  Function(List<VehicleModel>)? onVehiclesUpdate;

  List<VehicleModel> get vehicles => _vehicles;

  void connect() {
    _socket = io.io(
      ApiEndpoints.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket.connect();

    _socket.onConnect((_) {
      debugPrint('Connected to WebSocket: ${_socket.id}');
    });

    _socket.on('vehicle_update', (data) {
      final List<dynamic> list = data as List<dynamic>;
      final updatedVehicles = list.map((json) => VehicleModel.fromJson(json)).toList();
      _vehicles.clear();
      _vehicles.addAll(updatedVehicles);
      onVehiclesUpdate?.call(_vehicles);
    });

    _socket.onDisconnect((_) {
      debugPrint('WebSocket Disconnected');
    });
  }

  void disconnect() {
    _socket.disconnect();
    _socket.dispose();
  }
}
