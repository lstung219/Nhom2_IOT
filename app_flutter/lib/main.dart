
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:rxdart/rxdart.dart'; // For BehaviorSubject for alerts
import 'package:intl/intl.dart';
import 'package:mqtt_client/mqtt_server_client.dart'; // Use server client for Android

// --- MAIN ---
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF4F7F6), // This can be const
        cardTheme: CardThemeData( // Removed const here
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white.withOpacity(0.8),
        ),
        useMaterial3: true,
      ),
      home: ChangeNotifierProvider(
        create: (_) => IoTProvider(),
        child: const DashboardScreen(),
      ),
    );
  }
}

class DateTimePicker extends StatelessWidget {
  final DateTime selectedDateTime;
  final ValueChanged<DateTime> onDateTimeChanged;

  const DateTimePicker({
    super.key,
    required this.selectedDateTime,
    required this.onDateTimeChanged,
  });

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      _selectTime(context, pickedDate);
    }
  }

  Future<void> _selectTime(BuildContext context, DateTime date) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );
    if (pickedTime != null) {
      final newDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      onDateTimeChanged(newDateTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => _selectDate(context),
          icon: const Icon(Icons.calendar_today),
          label: const Text('Select Date/Time'),
        ),
      ],
    );
  }
}

class AlertDisplay extends StatelessWidget {
  const AlertDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: context.read<IoTProvider>().activeAlerts,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final alerts = snapshot.data!;
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: alerts.map((alertId) {
            // This is a simplified alert display. In a real app, you'd store alert messages and types.
            // For now, we'll just show the ID as a placeholder.
            // A more robust solution would involve passing Alert objects with message, type, and ID.
            String message = '';
            Color color = Colors.red; // Default to danger
            IconData icon = Icons.warning;

            if (alertId.contains('temp_high')) {
              message = 'Temperature threshold crossed!';
              color = Colors.red;
              icon = Icons.thermostat;
            } else if (alertId.contains('gas_high')) {
              message = 'Gas level threshold crossed!';
              color = Colors.red;
              icon = Icons.local_fire_department;
            } else if (alertId.contains('lux_low')) {
              message = 'Light level is too low!';
              color = Colors.orange;
              icon = Icons.lightbulb_outline;
            } else if (alertId.contains('device_offline')) {
              message = 'Device has gone offline!';
              color = Colors.red;
              icon = Icons.developer_board_off;
            } else if (alertId.contains('device_online')) {
              message = 'Device is back online!';
              color = Colors.green;
              icon = Icons.developer_board;
            } else if (alertId.contains('mqtt_disconnected')) {
              message = 'MQTT is disconnected. Cannot send command.';
              color = Colors.orange;
              icon = Icons.wifi_off;
            } else if (alertId.contains('api_error') || alertId.contains('api_connection_failed')) {
              message = 'API error occurred!';
              color = Colors.red;
              icon = Icons.cloud_off;
            } else {
              message = 'Unknown alert: $alertId';
              color = Colors.grey;
              icon = Icons.info_outline;
            }


            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: color.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    // Optionally add a close button
                    // IconButton(
                    //   icon: Icon(Icons.close, color: Colors.white),
                    //   onPressed: () {
                    //     // This would require a method in IoTProvider to dismiss alerts
                    //   },
                    // ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// --- PROVIDER (STATE MANAGEMENT) ---
class IoTProvider extends ChangeNotifier {
  // ===================== CONFIGURATION =====================
  // Use the full WebSocket URL for WSS connections
  // For Android, we use the hostname for TCP connection, not a WebSocket URL.
  static const String BROKER_HOST = 'broker.hivemq.com';
  static const int BROKER_PORT = 1883; // Standard non-secure MQTT port

  static const String TOPIC_PREFIX = 'lstiot/lab/room1';
  static final String SENSOR_TOPIC = '$TOPIC_PREFIX/sensor/state';
  static final String DEVICE_TOPIC = '$TOPIC_PREFIX/device/state';
  static final String DEVICE_CMD_TOPIC = '$TOPIC_PREFIX/device/cmd';
  static final String ONLINE_TOPIC = '$TOPIC_PREFIX/sys/online';
  // IMPORTANT: For Android, use your computer's IP address, not 'localhost'.
  static const String API_URL = 'http://192.168.1.8:3001/api/history'; // <-- CHANGE THIS TO YOUR PC's IP

  static const double TEMP_HIGH_C = 35.0;
  static const int GAS_HIGH = 1800;
  static const int LUX_LOW = 500;
  static const int STREAK_NEEDED = 3;
  static const int ALERT_COOLDOWN_MS = 30000; // 30 seconds

  // Connection Status
  MqttConnectionState _brokerStatus = MqttConnectionState.disconnected;
  MqttConnectionState get brokerStatus => _brokerStatus;
  bool _deviceOnline = false; // Moved declaration here
  bool get deviceOnline => _deviceOnline; // Moved getter here
  // Real-time Data
  double temp = 0.0;
  double hum = 0.0;
  int gas = 0;
  int lux = 0;
  int rssi = 0;
  String firmware = '--';
  int messageCount = 0;

  // Device Control State
  bool lightState = false;
  bool fanState = false;
  bool autoLightState = false;

  // Chart Data
  Map<String, List<FlSpot>> history = {
    'temp': [], 'hum': [], 'gas': [], 'lux': []
  };
  DateTime _selectedDateTime = DateTime.now();
  DateTime get selectedDateTime => _selectedDateTime;
  String _selectedRange = '24h';
  String get selectedRange => _selectedRange;
  String _selectedChart = 'temp';
  String get selectedChart => _selectedChart;

  // Alert State
  Map<String, int> _alertStreaks = {'temp': 0, 'gas': 0, 'lux': 0};
  Map<String, int> _lastAlerts = {'temp': 0, 'gas': 0, 'lux': 0};
  final BehaviorSubject<List<String>> _activeAlerts = BehaviorSubject.seeded([]);
  Stream<List<String>> get activeAlerts => _activeAlerts.stream;
  List<String> _currentAlerts = [];

  MqttServerClient? client;

  IoTProvider() {
    _selectedDateTime = DateTime.now(); // Initialize with current time
    _connect();
    fetchHistory(); // Fetch initial historical data
  }

  void _connect() async {
    client = MqttServerClient(BROKER_HOST, 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    client!.port = BROKER_PORT; // Use the standard TCP port
    
    // IMPORTANT: Enable logging for debugging purposes
    client!.logging(on: true);

    client!.onConnected = onConnected;
    client!.onDisconnected = onDisconnected;
    client!.onSubscribed = onSubscribed;
    client!.onSubscribeFail = onSubscribeFail;
    client!.onUnsubscribed = (topic) => print('Unsubscribed from $topic');
    client!.pongCallback = pong;
    client!.keepAlivePeriod = 20; // The 'wss' scheme handles security automatically.
    client!.secure = false; // Set to false for standard TCP connection on port 1883
    client!.setProtocolV311();

    // LWT (Last Will and Testament) for this client (optional but good practice)
    final MqttClientPayloadBuilder willMessage = MqttClientPayloadBuilder();
    // This client doesn't represent the physical device, so we don't publish to sys/online
    // willMessage.addString(json.encode({'online': false}));

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atMostOnce); // Set to atMostOnce or remove if not using LWT
    client!.connectionMessage = connMessage;

    try {
      _brokerStatus = MqttConnectionState.connecting;
      notifyListeners();
      await client!.connect();
      print('MQTT Client connection attempt successful.');
    } catch (e) {
      print('MQTT Client Exception: $e');
      onDisconnected();
    }
  }

  void onConnected() {
    _brokerStatus = MqttConnectionState.connected;
    print('MQTT Client connected');
    // Subscribe to topics
    client!.subscribe(SENSOR_TOPIC, MqttQos.atLeastOnce);
    client!.subscribe(DEVICE_TOPIC, MqttQos.atLeastOnce);
    client!.subscribe(ONLINE_TOPIC, MqttQos.atLeastOnce);
    notifyListeners();
  }

  void onDisconnected() {
    _brokerStatus = MqttConnectionState.disconnected;
    _deviceOnline = false; // Assume device is offline if broker disconnects
    notifyListeners();
    print('MQTT Client disconnected. Attempting to reconnect in 5 seconds...');
    Future.delayed(const Duration(seconds: 5), () => _connect()); // Auto-reconnect
  }

  void onSubscribed(String topic) {
    print('Subscribed to $topic');
    client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage message = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(message.payload.message);
      final topic = c[0].topic;
      
      try {
        final data = json.decode(payload);
        messageCount++;

        if (topic == SENSOR_TOPIC) {
          _updateSensorData(data);
          _checkAlerts(data);
        } else if (topic == DEVICE_TOPIC) {
          _updateDeviceData(data);
        } else if (topic == ONLINE_TOPIC) {
          _updateOnlineStatus(data);
        }
        notifyListeners();
      } catch (e) {
        print('Error parsing MQTT message on topic $topic: $e');
      }
    });
  }

  void _updateSensorData(Map<String, dynamic> data) {
    temp = (data['temp_c'] ?? temp).toDouble();
    hum = (data['hum_pct'] ?? hum).toDouble();
    gas = (data['gas'] ?? gas).toInt();
    lux = (data['lux'] ?? lux).toInt();
    // For real-time charts, you might want to add data here as well
    // For simplicity, this demo relies on historical fetch for charts.
  }

  void _updateDeviceData(Map<String, dynamic> data) {
    lightState = data['light'] == 'on';
    fanState = data['fan'] == 'on';
    autoLightState = data['auto_light'] == 'on';
    rssi = (data['rssi'] ?? rssi).toInt();
    firmware = data['fw'] ?? firmware;
  }

  void _updateOnlineStatus(Map<String, dynamic> data) {
    final bool isOnline = data['online'] == true;
    if (_deviceOnline != isOnline) { // Only show alert if status changes
      if (!isOnline) {
        _showAlert('device_offline', 'Device has gone offline!', AlertType.danger);
      } else {
        _showAlert('device_online', 'Device is back online!', AlertType.success, duration: 5000);
      }
      _deviceOnline = isOnline; // Update the state
    }
  }

  void onSubscribeFail(String topic) {
    print('Failed to subscribe to $topic');
  }

  void pong() {
    print('Ping response received');
  }

  void sendCommand(String device, bool state) {
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      final payload = json.encode({device: state ? 'on' : 'off'});
      client!.publishMessage(DEVICE_CMD_TOPIC, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(payload).payload!);
      
      // Optimistic UI update for responsiveness
      if (device == 'light') lightState = state;
      if (device == 'fan') fanState = state;
      if (device == 'auto_light') autoLightState = state;
      notifyListeners();
    } else {
      _showAlert('mqtt_disconnected', 'Cannot send command. MQTT is disconnected.', AlertType.warning);
    }
  }

  Future<void> fetchHistory([String? range, DateTime? time]) async {
    _selectedRange = range ?? _selectedRange;
    _selectedDateTime = time ?? _selectedDateTime;

    String url = '$API_URL?range=$_selectedRange';
    if (['1h', '24h'].contains(_selectedRange) && _selectedDateTime != null) {
      url += '&time=${_selectedDateTime.toIso8601String()}';
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        history['temp'] = data.map((d) => FlSpot(DateTime.parse(d['time_bucket']).millisecondsSinceEpoch.toDouble(), double.parse(d['avg_temp']))).toList();
        history['hum'] = data.map((d) => FlSpot(DateTime.parse(d['time_bucket']).millisecondsSinceEpoch.toDouble(), double.parse(d['avg_hum']))).toList();
        history['gas'] = data.map((d) => FlSpot(DateTime.parse(d['time_bucket']).millisecondsSinceEpoch.toDouble(), double.parse(d['avg_gas']))).toList();
        history['lux'] = data.map((d) => FlSpot(DateTime.parse(d['time_bucket']).millisecondsSinceEpoch.toDouble(), double.parse(d['avg_lux']))).toList();
      }
      else {
        _showAlert('api_error', 'Failed to load history: ${response.reasonPhrase}', AlertType.danger);
      }
    } catch (e) {
      _showAlert('api_connection_failed', 'API connection failed. Is the server running?', AlertType.danger);
      print("Failed to fetch history: $e");
    }
    notifyListeners();
  }

  void selectChart(String chart) {
    _selectedChart = chart;
    notifyListeners();
  }

  void setSelectedDateTime(DateTime newDateTime) {
    _selectedDateTime = newDateTime;
    fetchHistory(null, newDateTime); // Refetch history with new time
  }

  // ===================== ALERT LOGIC (from demo_dashboard.html) =====================
  void _checkAlerts(Map<String, dynamic> data) {
    final now = DateTime.now().millisecondsSinceEpoch;

    void check(String key, num? value, num threshold, bool isMax) {
      if (value == null) return;

      if ((isMax && value >= threshold) || (!isMax && value <= threshold)) {
        _alertStreaks[key] = (_alertStreaks[key] ?? 0) + 1;
        if (_alertStreaks[key]! >= STREAK_NEEDED && (now - (_lastAlerts[key] ?? 0)) >= ALERT_COOLDOWN_MS) {
          final msg = '${key.capitalize()} threshold crossed: ${value.toStringAsFixed(1)}';
          _showAlert(key, msg, AlertType.danger);
          _lastAlerts[key] = now;
          _alertStreaks[key] = 0;
        }
      } else {
        _alertStreaks[key] = 0;
      }
    }

    check('temp', data['temp_c'], TEMP_HIGH_C, true);
    check('gas', data['gas'], GAS_HIGH, true);
    check('lux', data['lux'], LUX_LOW, false);
  }

  void _showAlert(String id, String message, AlertType type, {int duration = 10000}) {
    // Prevent duplicate alerts of the same ID (unless it's a success/info message which can repeat)
    if (_currentAlerts.contains(id) && type != AlertType.success) {
      return;
    }

    _currentAlerts.add(id);
    _activeAlerts.add(List.from(_currentAlerts)); // Notify UI to show the alert

    print('ALERT ($type): $message'); // For console logging

    // Auto-remove alert after its duration
    Future.delayed(Duration(milliseconds: duration), () {
      _currentAlerts.remove(id);
      _activeAlerts.add(List.from(_currentAlerts)); // Notify listeners
    });
  }

  @override
  void dispose() {
    client?.disconnect();
    _activeAlerts.close();
    super.dispose();
  }
}

enum AlertType { info, success, warning, danger }

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

// --- UI: DASHBOARD SCREEN ---
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.contain,
          child: Text('IoT Dashboard'),
        ),
        backgroundColor: Colors.white,
        elevation: 1, // Shadow for AppBar
        actions: const [
          BrokerStatusChip(),
          DeviceStatusChip(),
          SizedBox(width: 16),
        ],
      ),
      body: Stack( // Use Stack to overlay alerts
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: isDesktop
                ? const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: LeftColumn()),
                      SizedBox(width: 16),
                      Expanded(flex: 3, child: RightColumn()),
                    ],
                  )
                : const SingleChildScrollView(
                    child: Column(
                      children: [LeftColumn(), SizedBox(height: 16), RightColumn()],
                    ),
                  ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: AlertDisplay(), // Display alerts here
          ),
        ],
      ),
    );
  }
}

// --- UI: COLUMNS ---
class LeftColumn extends StatelessWidget {
  const LeftColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CurrentReadingsCard(),
        SizedBox(height: 16),
        DeviceControlCard(),
        SizedBox(height: 16),
        SystemInfoCard(),
      ],
    );
  }
}

class RightColumn extends StatelessWidget {
  const RightColumn({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SensorHistoryCard(),
      ],
    );
  }
}

// --- UI: WIDGETS & CARDS ---

class BrokerStatusChip extends StatelessWidget {
  const BrokerStatusChip({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<IoTProvider>(
      builder: (context, provider, child) {
        String text;
        Color color;
        IconData icon = Icons.wifi_off; // Default icon
        switch (provider.brokerStatus) { // Added icon variable initialization
          case MqttConnectionState.connected:
            text = 'MQTT: Connected';
            color = Colors.green;
            icon = Icons.wifi;
            break;
          case MqttConnectionState.connecting:
            text = 'MQTT: Connecting...';
            color = Colors.orange;
            icon = Icons.wifi_calling;
            break;
          default:
            text = 'MQTT: Disconnected';
            color = Colors.red;
            icon = Icons.wifi_off;
        }
        return Chip(
          label: Text(text),
          backgroundColor: color.withOpacity(0.2),
          avatar: Icon(icon, color: color, size: 18),
        );
      },
    );
  }
}

class DeviceStatusChip extends StatelessWidget {
  const DeviceStatusChip({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<IoTProvider>(
      builder: (context, provider, child) {
        final text = provider.deviceOnline ? 'Device: Online' : 'Device: Offline';
        final color = provider.deviceOnline ? Colors.green : Colors.red;
        final icon = provider.deviceOnline ? Icons.developer_board : Icons.developer_board_off;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Chip(
            label: Text(text),
            backgroundColor: color.withOpacity(0.2),
            avatar: Icon(icon, color: color, size: 18),
          ),
        );
      },
    );
  }
}

class CurrentReadingsCard extends StatelessWidget {
  const CurrentReadingsCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<IoTProvider>(
          builder: (context, provider, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Readings', style: Theme.of(context).textTheme.headlineSmall),
              const Divider(height: 20),
              InfoRow(icon: '🌡️', label: 'Temperature', value: '${provider.temp.toStringAsFixed(1)} °C'),
              InfoRow(icon: '💧', label: 'Humidity', value: '${provider.hum.toStringAsFixed(1)} %'),
              InfoRow(icon: '💨', label: 'Gas', value: provider.gas.toString()),
              InfoRow(icon: '☀️', label: 'Light', value: '${provider.lux} lux'),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceControlCard extends StatelessWidget {
  const DeviceControlCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<IoTProvider>(
          builder: (context, provider, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device Control', style: Theme.of(context).textTheme.headlineSmall),
              const Divider(height: 20),
              SwitchListTile(
                title: const Text('💡 Light'),
                value: provider.lightState,
                onChanged: (val) => provider.sendCommand('light', val),
              ),
              SwitchListTile(
                title: const Text('🌀 Fan'),
                value: provider.fanState,
                onChanged: (val) => provider.sendCommand('fan', val),
              ),
              SwitchListTile(
                title: const Text('🤖 Auto Light'),
                value: provider.autoLightState,
                onChanged: (val) => provider.sendCommand('auto_light', val),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SystemInfoCard extends StatelessWidget {
  const SystemInfoCard({super.key});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Consumer<IoTProvider>(
          builder: (context, provider, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('System Info', style: Theme.of(context).textTheme.headlineSmall),
              const Divider(height: 20),
              InfoRow(icon: '📶', label: 'WiFi Signal', value: '${provider.rssi} dBm'),
              InfoRow(icon: '⚙️', label: 'Firmware', value: provider.firmware),
              InfoRow(icon: '📦', label: 'Msgs Rcvd', value: provider.messageCount.toString()),
            ],
          ),
        ),
      ),
    );
  }
}

class SensorHistoryCard extends StatelessWidget {
  const SensorHistoryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IoTProvider>();
    final bool showDateTimePicker = ['1h', '24h'].contains(provider.selectedRange);

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sensor History', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: '1h', label: Text('1 Hour')),
                      ButtonSegment(value: '24h', label: Text('24 Hours')),
                      ButtonSegment(value: '7d', label: Text('7 Days')),
                      ButtonSegment(value: '30d', label: Text('30 Days')),
                    ],
                    selected: {provider.selectedRange},
                    onSelectionChanged: (newSelection) {
                      context.read<IoTProvider>().fetchHistory(newSelection.first);
                    },
                  ),
                ),
                if (showDateTimePicker) ...[
                  const SizedBox(height: 16),
                  DateTimePicker(
                    selectedDateTime: provider.selectedDateTime,
                    onDateTimeChanged: (newDateTime) {
                      context.read<IoTProvider>().setSelectedDateTime(newDateTime);
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChartTabButton(icon: '🌡️', label: 'Temperature', id: 'temp'),
                ChartTabButton(icon: '💧', label: 'Humidity', id: 'hum'),
                ChartTabButton(icon: '💨', label: 'Gas', id: 'gas'),
                ChartTabButton(icon: '☀️', label: 'Light', id: 'lux'),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: HistoryChart(),
            ),
          ),
        ],
      ),
    );
  }
}

class ChartTabButton extends StatelessWidget {
  final String icon;
  final String label;
  final String id;

  const ChartTabButton({super.key, required this.icon, required this.label, required this.id});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IoTProvider>();
    final isSelected = provider.selectedChart == id;
    return TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Text(icon),
      label: Text(label),
      onPressed: () => context.read<IoTProvider>().selectChart(id),
    );
  }
}

class HistoryChart extends StatelessWidget {
  HistoryChart({super.key});

  final Map<String, Color> chartColors = {
    'temp': Colors.red,
    'hum': Colors.blue,
    'gas': Colors.orange,
    'lux': Colors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IoTProvider>();
    final selected = provider.selectedChart;
    final data = provider.history[selected] ?? [];

    String getBottomTitles(double value, String range) {
      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
      if (range == '1h') {
        return DateFormat('mm').format(date); // Minutes for 1 hour
      } else if (range == '24h') {
        return DateFormat('HH:mm').format(date); // Hours and minutes for 24 hours
      } else {
        return DateFormat('MMM dd').format(date); // Month and day for longer ranges
      }
    }

    if (data.isEmpty) {
      return const Center(child: Text('No historical data available.'));
    }

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: data,
            isCurved: true,
            color: chartColors[selected]!,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: chartColors[selected]!.withOpacity(0.2),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: provider.selectedRange == '1h' ? 60000 * 10 : (provider.selectedRange == '24h' ? 3600000 * 4 : 3600000 * 24), // Adjust interval based on range
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Text(getBottomTitles(value, provider.selectedRange), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.blueGrey.withOpacity(0.8),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((LineBarSpot touchedSpot) {
                final date = DateTime.fromMillisecondsSinceEpoch(touchedSpot.x.toInt());
                return LineTooltipItem(
                  '${DateFormat('MMM dd HH:mm').format(date)}\n${touchedSpot.y.toStringAsFixed(1)}',
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}


// --- UI: HELPER WIDGETS ---
class InfoRow extends StatelessWidget {
  final String icon;
  final String label;
  final String value;

  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
