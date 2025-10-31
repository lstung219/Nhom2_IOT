# IoT Demo Infrastructure Setup

This directory contains the infrastructure configuration for the IoT Demo project using Mosquitto MQTT broker.

## Prerequisites

- Docker and Docker Compose installed
- Mosquitto MQTT broker
- Basic understanding of MQTT protocol

## Quick Start

### 1. Docker Setup (Recommended)

Create a `docker-compose.yml` file:

```yaml
version: '3.8'
services:
  mosquitto:
    image: eclipse-mosquitto:2.0
    container_name: iot-mosquitto
    ports:
      - "1883:1883"    # MQTT TCP
      - "9001:9001"    # MQTT WebSocket  
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
      - ./password_file:/mosquitto/config/password_file
      - mosquitto_data:/mosquitto/data
    restart: unless-stopped

volumes:
  mosquitto_data:
```

### 2. Create User Accounts

Create a password file for MQTT authentication:

```bash
# Create password file (Linux/Mac)
mosquitto_passwd -c password_file user1

# Or on Windows with mosquitto installed:
mosquitto_passwd.exe -c password_file user1
```

When prompted, enter password: `pass1`

Add more users:
```bash
mosquitto_passwd password_file app_user
mosquitto_passwd password_file web_user
```

### 3. Start the Broker

```bash
# Using Docker Compose
docker-compose up -d

# Check if running
docker ps
docker logs iot-mosquitto
```

### 4. Test the Setup

#### Test TCP Connection (Port 1883)
```bash
# Subscribe to test topic
mosquitto_sub -h 192.168.1.10 -p 1883 -u user1 -P pass1 -t "test/topic"

# Publish test message (in another terminal)
mosquitto_pub -h 192.168.1.10 -p 1883 -u user1 -P pass1 -t "test/topic" -m "Hello MQTT"
```

#### Test WebSocket Connection (Port 9001)
Open `web_readonly/index.html` in a browser and check the connection status.

## IoT Demo Topics

The system uses the following standardized topics:

### Sensor Data
```
lab/room1/sensor/state
```
**Payload Example:**
```json
{"ts":1695890000,"temp_c":28.6,"hum_pct":62.1,"gas":1234,"lux":120}
```

### Device State (Retained)
```
lab/room1/device/state  
```
**Payload Example:**
```json
{"ts":1695890000,"light":"off","fan":"on","rssi":-57,"fw":"iot-demo-1.0.0"}
```

### Device Commands  
```
lab/room1/device/cmd
```
**Payload Examples:**
```json
{"light":"on"}
{"fan":"toggle"}  
{"led_rgb":[255,0,0]}
```

### Alert Events
```
lab/room1/alert/event
```
**Payload Example:**
```json
{"ts":1695890000,"type":"temp_high","value":42.5,"note":"Temperature over threshold for 5s"}
```

### System Online (LWT - Retained)
```
lab/room1/sys/online
```
**Payload Examples:**
```json
{"online":true}   // Device connected
{"online":false}  // Device disconnected (LWT)
```

## Understanding Retained Messages

Retained messages are crucial for this IoT system:

- **Device State**: Always retained so new clients immediately know current state
- **Online Status**: Retained LWT (Last Will Testament) for offline detection
- **Sensor Data**: Not retained (real-time stream)
- **Commands**: Not retained (one-time actions)

## Last Will Testament (LWT) Explained

LWT enables automatic offline detection:

1. **Device connects** with LWT configured:
   - Topic: `lab/room1/sys/online`
   - Message: `{"online":false}`
   - Retained: `true`

2. **While connected**, device publishes:
   - `{"online":true}` to same topic (retained)

3. **If device disconnects** unexpectedly:
   - Broker automatically publishes the LWT message
   - Subscribers immediately know device is offline

## Troubleshooting

### Connection Issues

1. **Check broker status:**
```bash
docker logs iot-mosquitto
```

2. **Verify ports are open:**
```bash
netstat -an | grep 1883
netstat -an | grep 9001
```

3. **Test with mosquitto clients:**
```bash
# Test authentication
mosquitto_pub -h 192.168.1.10 -p 1883 -u user1 -P pass1 -t "test" -m "auth_test"
```

### Permission Issues

1. **Check password file permissions:**
```bash
ls -la password_file
# Should be readable by mosquitto user
```

2. **Recreate password file if needed:**
```bash
rm password_file
mosquitto_passwd -c password_file user1
```

### WebSocket Issues

1. **Browser console errors** - Check CORS/mixed content
2. **Connection refused** - Verify port 9001 is accessible
3. **Authentication failed** - Ensure same credentials work with TCP

## Security Considerations

### Production Deployment

1. **Use TLS/SSL:**
   - Configure certificates in mosquitto.conf
   - Use ports 8883 (MQTTS) and 8084 (WSS)

2. **Access Control Lists (ACL):**
```bash
# Create acl_file
echo "user app_user" > acl_file
echo "topic readwrite lab/room1/device/cmd" >> acl_file
echo "topic read lab/room1/+/+" >> acl_file

echo "user web_user" >> acl_file  
echo "topic read lab/room1/+/+" >> acl_file
```

3. **Firewall rules:**
   - Limit access to known IP ranges
   - Block unused ports

4. **Regular updates:**
   - Keep Mosquitto version updated
   - Monitor security advisories

## Monitoring & Logs

### Enable detailed logging:
```conf
# Add to mosquitto.conf
log_type all
log_dest file /mosquitto/log/mosquitto.log
```

### Monitor connections:
```bash
# Watch active connections
docker exec -it iot-mosquitto mosquitto_sub -h localhost -t '$SYS/broker/clients/connected'

# Monitor message statistics  
docker exec -it iot-mosquitto mosquitto_sub -h localhost -t '$SYS/broker/messages/received'
```

## Integration with Node-RED

The `nodered/alerts_flow.json` connects to this broker:

1. Import the flow in Node-RED
2. Update broker configuration to match your setup
3. Replace `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` placeholders
4. Deploy and test

## Performance Tuning

For high-throughput scenarios:

```conf
# Add to mosquitto.conf
max_inflight_messages 40
max_queued_messages 1000
message_size_limit 8192
```

## Backup & Recovery

```bash
# Backup retained messages and config
docker cp iot-mosquitto:/mosquitto/data ./backup/
cp mosquitto.conf password_file ./backup/

# Restore
docker cp ./backup/data iot-mosquitto:/mosquitto/
```