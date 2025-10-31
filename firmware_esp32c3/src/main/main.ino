#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <DHT.h>

// ===================== SENSOR CONFIGURATION =====================
// NOTE: You must install the "DHT sensor library" by Adafruit
#define DHTPIN 4      // GPIO pin for the DHT22 data line
#define DHTTYPE DHT22 // Type of DHT sensor

const int GAS_PIN = 0;    // GPIO pin for the MQ-2 analog output
const int LIGHT_PIN = 1;  // GPIO pin for the LDR/photoresistor analog output (measures lamp)
const int AMBIENT_LIGHT_PIN = 2; // GPIO pin for the ambient LDR (measures room light)

// ===================== AUTO MODE CONFIG =====================
const int AMBIENT_LIGHT_THRESHOLD = 1000; // If ambient lux is below this, turn light on

// ===================== CONFIGURATION (FOR ESP32-C3) =====================
// NOTE: These values are hardcoded for the firmware.
// For consistency, they should be synchronized with the main .env file
// in the root of the project.
// ========================================================================

// WiFi settings
const char* WIFI_SSID = "not";
const char* WIFI_PASS = "tung1234";

// MQTT settings  
const char* MQTT_HOST = "broker.hivemq.com";
const int MQTT_PORT = 1883;
const char* MQTT_USER = "";
const char* MQTT_PASSWD = "";

// Topic namespace
const char* NS = "lstiot/lab/room1";

// Telegram settings
const char* TELEGRAM_BOT_TOKEN = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11";
const char* TELEGRAM_CHAT_ID = "123456789";

// Alert thresholds
const float TEMP_HIGH_C = 35.0;
const int GAS_RAW_HIGH = 1800;
const int STREAK_NEEDED = 5;
const unsigned long ALERT_COOLDOWN_MS = 60000; // 60 seconds

// Pins (Adjusted for ESP32-C3 with 2 LEDs and L298N Fan Driver)
const int STATUS_LED_PIN = 8;  // LED for on/off status
const int ALERT_LED_PIN = 9;   // LED for alert notifications
const int FAN_IN1_PIN = 6;     // L298N Input 1
const int FAN_IN2_PIN = 7;     // L298N Input 2

// ===================== GLOBAL VARIABLES =====================
WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);
DHT dht(DHTPIN, DHTTYPE);

// Device state
bool lightState = false;
bool fanState = false;
bool lightAutoMode = false;
int ledR = 0, ledG = 0, ledB = 0;

// Sensor data with EMA filtering
float tempC = 25.0;
float humPct = 60.0;
int gasRaw = 400; // Start with a typical clean air value
int lux = 100;
int ambientLux = 100;

// Reusable JSON document for memory efficiency
StaticJsonDocument<512> doc;

// Alert tracking
int tempHighStreak = 0;
int gasHighStreak = 0;
unsigned long lastTempAlert = 0;
unsigned long lastGasAlert = 0;

// Timing
unsigned long lastSensorPublish = 0;
unsigned long lastHeartbeat = 0;
const unsigned long SENSOR_INTERVAL = 1000; // 1s
const unsigned long HEARTBEAT_INTERVAL = 15000; // 15s

// Non-blocking alert blinking state
bool isBlinking = false;
unsigned long blinkStartTime = 0;
unsigned long lastBlinkToggle = 0;
bool alertLedState = false;

// Topics
char topicSensorState[50];
char topicDeviceState[50];
char topicDeviceCmd[50];
char topicAlertEvent[50];
char topicSysOnline[50];

// Function Prototypes
void handleBlinking();

void setup() {
  Serial.begin(115200);
  Serial.println("Booting...");
  
  // Initialize pins
  pinMode(STATUS_LED_PIN, OUTPUT);
  pinMode(ALERT_LED_PIN, OUTPUT);
  pinMode(FAN_IN1_PIN, OUTPUT);
  pinMode(FAN_IN2_PIN, OUTPUT);

  // Initialize Sensors
  dht.begin();
  Serial.println("DHT22 and MQ-2 sensors initialized.");

  // Ensure fan is off at startup
  digitalWrite(FAN_IN1_PIN, LOW);
  digitalWrite(FAN_IN2_PIN, LOW);
  
  // Build topic strings safely
  snprintf(topicSensorState, sizeof(topicSensorState), "%s/sensor/state", NS);
  snprintf(topicDeviceState, sizeof(topicDeviceState), "%s/device/state", NS);
  snprintf(topicDeviceCmd, sizeof(topicDeviceCmd), "%s/device/cmd", NS);
  snprintf(topicAlertEvent, sizeof(topicAlertEvent), "%s/alert/event", NS);
  snprintf(topicSysOnline, sizeof(topicSysOnline), "%s/sys/online", NS);
  
  // Connect WiFi
  connectWiFi();
  
  // Setup MQTT
  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(onMqttMessage);
  
  // Connect MQTT with LWT
  connectMqtt();
  
  Serial.println("ESP32-C3 IoT Demo Ready!");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  // Maintain MQTT connection
  if (!mqttClient.connected()) {
    connectMqtt();
  }
  mqttClient.loop(); // This should be called as often as possible
  
  unsigned long now = millis();
  
  // Publish sensor data every SENSOR_INTERVAL
  if (now - lastSensorPublish >= SENSOR_INTERVAL) {
    lastSensorPublish = now; // Reset timer immediately
    updateSensorReadings();
    publishSensorState();
  }
  
  // Handle automatic light control
  handleAutoLightMode();

  // Handle non-blocking alert blinking
  handleBlinking();

  // Publish device heartbeat every HEARTBEAT_INTERVAL
  if (now - lastHeartbeat >= HEARTBEAT_INTERVAL) {
    lastHeartbeat = now; // Reset timer immediately
    publishDeviceState();
  }
  
  // Check for alerts
  checkAlerts(now);
}

void handleBlinking() {
  if (!isBlinking) {
    return;
  }

  unsigned long now = millis();

  // Check if total blink duration (10s) is over
  if (now - blinkStartTime >= 10000) {
    isBlinking = false;
    alertLedState = false;
    digitalWrite(ALERT_LED_PIN, LOW);
    Serial.println("Visual alert finished.");
    return;
  }

  // Check if it's time to toggle the LED (300ms interval)
  if (now - lastBlinkToggle >= 300) {
    alertLedState = !alertLedState; // Flip the state
    digitalWrite(ALERT_LED_PIN, alertLedState);
    lastBlinkToggle = now;
  }
}

void handleAutoLightMode() {
  if (!lightAutoMode) {
    return; // Do nothing if auto mode is off
  }

  bool shouldBeOn = (ambientLux < AMBIENT_LIGHT_THRESHOLD);
  
  if (lightState != shouldBeOn) {
    lightState = shouldBeOn;
    digitalWrite(STATUS_LED_PIN, lightState ? HIGH : LOW);
    Serial.print("Auto-light changed state to: ");
    Serial.println(lightState ? "ON" : "OFF");
    publishDeviceState(); // Publish the change immediately
  }
}

void connectWiFi() {
  Serial.print("Connecting to WiFi");
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  WiFi.setTxPower(WIFI_POWER_8_5dBm); // Lower WiFi power to improve stability
  
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - startTime > 30000) { // 30 second timeout
      Serial.println("\nFailed to connect to WiFi. Rebooting...");
      delay(1000);
      ESP.restart();
    }
    delay(500);
    Serial.print(".");
  }
  
  Serial.println();
  Serial.print("WiFi connected! IP: ");
  Serial.println(WiFi.localIP());
}

void connectMqtt() {
  while (!mqttClient.connected()) {
    Serial.print("Connecting to MQTT...");

    // Create a unique client ID using the MAC address (and remove colons)
    String mac = WiFi.macAddress();
    mac.replace(":", "");
    char clientId[50];
    snprintf(clientId, sizeof(clientId), "ESP32-C3-IoT-%s", mac.c_str());
    
    // Set LWT message
    const char* lwtMsg = "{\"online\":false}";
    
    if (mqttClient.connect(clientId, MQTT_USER, MQTT_PASSWD,
                          topicSysOnline, 1, true, lwtMsg)) {
      Serial.println(" connected!");
      
      // Publish online status (retained)
      const char* onlineMsg = "{\"online\":true}";
      mqttClient.publish(topicSysOnline, onlineMsg, true);
      
      // Subscribe to device commands
      mqttClient.subscribe(topicDeviceCmd, 1);
      
      // Send initial device state
      publishDeviceState();
      
    } else {
      Serial.print(" failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" retrying in 5 seconds");
      delay(5000);
    }
  }
}

void onMqttMessage(char* topic, byte* payload, unsigned int length) {
  // Print the topic and payload without creating new String objects
  Serial.print("Received: ");
  Serial.print(topic);
  Serial.print(" = ");
  for (int i = 0; i < length; i++) {
    Serial.print((char)payload[i]);
  }
  Serial.println();
  
  // Handle device commands
  if (strcmp(topic, topicDeviceCmd) == 0) {
    handleDeviceCommand(payload, length);
  }
}

void handleDeviceCommand(byte* payload, unsigned int length) {
  doc.clear();
  DeserializationError error = deserializeJson(doc, payload, length);
  
  if (error) {
    Serial.println("Failed to parse command JSON");
    return;
  }
  
  bool stateChanged = false;

  // Handle auto light mode command
  if (doc.containsKey("auto_light")) {
    const char* autoCmd = doc["auto_light"];
    if (strcmp(autoCmd, "on") == 0) {
      lightAutoMode = true;
    } else if (strcmp(autoCmd, "off") == 0) {
      lightAutoMode = false;
    }
    stateChanged = true;
  }

  // Handle alert trigger command from server
  if (doc.containsKey("trigger_alert")) {
    const char* alertCmd = doc["trigger_alert"];
    if (strcmp(alertCmd, "blink") == 0) {
      Serial.println("Received command to blink alert LED.");
      triggerVisualAlert();
    }
  }
  
  // Handle light command
  if (doc.containsKey("light")) {
    const char* lightCmd = doc["light"];
    if (strcmp(lightCmd, "on") == 0) {
      lightState = true;
      lightAutoMode = false; // Disable auto mode on manual control
      stateChanged = true;
    } else if (strcmp(lightCmd, "off") == 0) {
      lightState = false;
      lightAutoMode = false; // Disable auto mode on manual control
      stateChanged = true;
    } else if (strcmp(lightCmd, "toggle") == 0) {
      lightState = !lightState;
      lightAutoMode = false; // Disable auto mode on manual control
      stateChanged = true;
    }
    digitalWrite(STATUS_LED_PIN, lightState ? HIGH : LOW);
  }
  
  // Handle fan command
  if (doc.containsKey("fan")) {
    const char* fanCmd = doc["fan"];
    if (strcmp(fanCmd, "on") == 0) {
      fanState = true;
      stateChanged = true;
    } else if (strcmp(fanCmd, "off") == 0) {
      fanState = false;
      stateChanged = true;
    } else if (strcmp(fanCmd, "toggle") == 0) {
      fanState = !fanState;
      stateChanged = true;
    }
    // Control L298N Driver
    if (fanState) {
      // To run the fan, set one IN pin HIGH and the other LOW
      digitalWrite(FAN_IN1_PIN, HIGH);
      digitalWrite(FAN_IN2_PIN, LOW);
    } else {
      // To stop the fan, set both IN pins LOW
      digitalWrite(FAN_IN1_PIN, LOW);
      digitalWrite(FAN_IN2_PIN, LOW);
    }
  }
  
  // Handle LED RGB (optional)
  if (doc.containsKey("led_rgb")) {
    JsonArray rgb = doc["led_rgb"];
    if (rgb.size() >= 3) {
      ledR = rgb[0];
      ledG = rgb[1]; 
      ledB = rgb[2];
      stateChanged = true;
      // Note: RGB LED implementation would go here
    }
  }
  
  // Publish updated device state immediately after command
  if (stateChanged) {
    publishDeviceState();
  }
}

void updateSensorReadings() {
  // Read from physical sensors
  // EMA filtering (smoothing) is applied to reduce noise
  float alpha = 0.2; // Smoothing factor

  // Read DHT22 Temperature and Humidity
  float newTemp = dht.readTemperature();
  float newHum = dht.readHumidity();
  // Check if any reads failed and keep the last valid reading.
  if (!isnan(newTemp)) {
    tempC = alpha * newTemp + (1 - alpha) * tempC;
  }
  if (!isnan(newHum)) {
    humPct = alpha * newHum + (1 - alpha) * humPct;
  }

  // Read MQ-2 Gas Sensor (raw analog value)
  int newGas = analogRead(GAS_PIN);
  gasRaw = alpha * newGas + (1 - alpha) * gasRaw;

  // Read LDR Light Sensor (raw analog value)
  // The value is inverted because higher light -> lower resistance -> lower analog reading
  int newLux = 4095 - analogRead(LIGHT_PIN); // ESP32 ADC is 12-bit (0-4095)
  lux = alpha * newLux + (1 - alpha) * lux;

  // Read Ambient LDR Light Sensor
  int newAmbientLux = 4095 - analogRead(AMBIENT_LIGHT_PIN);
  ambientLux = alpha * newAmbientLux + (1 - alpha) * ambientLux;
}

void publishSensorState() {
  doc.clear();
  doc["ts"] = millis();
  doc["temp_c"] = round(tempC * 10) / 10.0;
  doc["hum_pct"] = round(humPct * 10) / 10.0;
  doc["gas"] = gasRaw;
  doc["lux"] = lux;
  doc["ambient_lux"] = ambientLux;
  
  char payload[250];
  serializeJson(doc, payload);
  
  mqttClient.publish(topicSensorState, payload);
}

void publishDeviceState() {
  doc.clear();
  doc["ts"] = millis();
  doc["light"] = lightState ? "on" : "off";
  doc["fan"] = fanState ? "on" : "off";
  doc["auto_light"] = lightAutoMode ? "on" : "off";
  doc["rssi"] = WiFi.RSSI();
  doc["fw"] = "iot-demo-1.0.0";
  
  char payload[350];
  serializeJson(doc, payload);
  
  mqttClient.publish(topicDeviceState, payload, true);
}

void checkAlerts(unsigned long now) {
  // Check temperature alert
  if (tempC >= TEMP_HIGH_C) {
    tempHighStreak++;
    if (tempHighStreak >= STREAK_NEEDED && 
        (now - lastTempAlert) >= ALERT_COOLDOWN_MS) {
      char note[100];
      snprintf(note, sizeof(note), "Temperature over threshold for %ds", STREAK_NEEDED);
      publishAlert("temp_high", tempC, note);
      triggerVisualAlert(); // Keep local visual alert for temp
      lastTempAlert = now;
      tempHighStreak = 0;
    }
  } else {
    tempHighStreak = 0;
  }
  
  // Check gas alert
  if (gasRaw >= GAS_RAW_HIGH) {
    gasHighStreak++;
    if (gasHighStreak >= STREAK_NEEDED && 
        (now - lastGasAlert) >= ALERT_COOLDOWN_MS) {
      char note[100];
      snprintf(note, sizeof(note), "Gas leak detected: %d", gasRaw);
      publishAlert("gas_high", gasRaw, note);
      // triggerVisualAlert(); // DISABLED - This is now triggered by the server
      lastGasAlert = now;
      gasHighStreak = 0;
    }
  } else {
    gasHighStreak = 0;
  }
}

void publishAlert(const char* type, float value, const char* note) {
  doc.clear();
  doc["ts"] = millis();
  doc["type"] = type;
  doc["value"] = value;
  doc["note"] = note;
  
  char payload[300];
  serializeJson(doc, payload);
  
  mqttClient.publish(topicAlertEvent, payload);
  
  // Also send heartbeat after alert
  publishDeviceState();
}

// Changed to be non-blocking
void triggerVisualAlert() {
  if (!isBlinking) { // Prevent re-triggering if already blinking
    isBlinking = true;
    blinkStartTime = millis();
    lastBlinkToggle = blinkStartTime;
    alertLedState = true;
    digitalWrite(ALERT_LED_PIN, alertLedState);
    Serial.println("Visual alert activated.");
  }
}

void sendTelegramAlert(String message) {
  if (WiFi.status() == WL_CONNECTED) {
    WiFiClientSecure client;
    client.setInsecure(); // For testing only
    
    String url = "/bot" + String(TELEGRAM_BOT_TOKEN) + "/sendMessage";
    String payload = "chat_id=" + String(TELEGRAM_CHAT_ID) + "&text=" + message;
    
    if (client.connect("api.telegram.org", 443)) {
      client.println("POST " + url + " HTTP/1.1");
      client.println("Host: api.telegram.org");
      client.println("Content-Type: application/x-www-form-urlencoded");
      client.println("Content-Length: " + String(payload.length()));
      client.println();
      client.println(payload);
      
      Serial.println("Telegram alert sent: " + message);
      client.stop();
    }
  }
}