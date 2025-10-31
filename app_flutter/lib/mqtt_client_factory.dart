import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Factory for creating an MQTT client on non-web platforms (VM).
MqttClient getMqttClient(String server, String clientIdentifier) {
  final client = MqttServerClient(server, clientIdentifier);
  // For mobile, we connect to TCP, not WSS.
  // The server URL should be just the host, e.g., 'broker.hivemq.com'
  // and the port should be 1883 for non-secure TCP.
  // If you need secure connection on mobile, use port 8883 and client.secure = true.
  client.port = 1883; // Standard MQTT port
  return client;
}