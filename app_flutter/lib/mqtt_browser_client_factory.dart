import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_browser_client.dart';

/// Factory for creating an MQTT client on the web platform.
MqttClient getMqttClient(String server, String clientIdentifier) {
  // The server URL for web MUST be a WebSocket URL (e.g., 'wss://broker.hivemq.com:8884/mqtt')
  final client = MqttBrowserClient(server, clientIdentifier);
  // The port is part of the URL for WebSockets, but we set it here to ensure
  // the library uses it correctly, overriding any internal defaults.
  client.port = 8884;
  return client;
}