// =================================================================
// IoT Data Service - FINAL & CORRECTED
// =================================================================
// This service connects to MQTT, processes all messages, sends
// Telegram alerts, and stores all data into a PostgreSQL database.
// It is a complete replacement for the original alert_system.js
// =================================================================

require('dotenv').config();

const mqtt = require('mqtt');
const { Pool } = require('pg');
const express = require('express');
const http = require('http');

// --- Configuration ---
const MQTT_URL = `wss://${process.env.MQTT_HOST}:${process.env.MQTT_WSS_PORT}/mqtt`;
const TOPIC_PREFIX = process.env.TOPIC_NS;
const CMD_TOPIC = `${TOPIC_PREFIX}/device/cmd`;

// Alerting thresholds and state
const TEMP_HIGH_C = parseFloat(process.env.TEMP_HIGH_C);
const GAS_HIGH = parseInt(process.env.GAS_RAW_HIGH);
const LUX_LOW = parseInt(process.env.LUX_LOW);
const STREAK_NEEDED = 5;
const ALERT_COOLDOWN_MS = 10000;

let tempHighStreak = 0, gasHighStreak = 0, luxLowStreak = 0;
let lastTempAlert = 0, lastGasAlert = 0, lastLuxAlert = 0;
let lastLightState = null, lastFanState = null;

// --- PostgreSQL Client Setup ---
const pgPool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  database: process.env.PGDATABASE,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
});

pgPool.on('error', (err) => console.error('❌ PostgreSQL Pool Error:', err));
console.log('🐘 Connecting to PostgreSQL...');
pgPool.connect().then(client => {
    console.log('✅ PostgreSQL connected successfully!');
    client.release();
}).catch(err => console.error('❌ Failed to connect to PostgreSQL:', err.stack));

// --- MQTT Client Setup ---
console.log(`📡 Connecting to MQTT Broker at ${MQTT_URL}...`);
const mqttClient = mqtt.connect(MQTT_URL, {
  clientId: `iot-data-service-${Math.random().toString(16).slice(2)}`,
  reconnectPeriod: 5000,
  connectTimeout: 10000,
});

mqttClient.on('connect', () => {
  console.log('✅ MQTT Broker connected');
  const topic = `${TOPIC_PREFIX}/#`;
  mqttClient.subscribe(topic, { qos: 1 }, (err) => {
    if (err) console.error('❌ MQTT subscription error:', err);
    else console.log(`✅ Subscribed to topic: ${topic}`);
  });
});

mqttClient.on('reconnect', () => console.log('🔄 Reconnecting to MQTT Broker...'));
mqttClient.on('error', (err) => console.error('❌ MQTT Client Error:', err));
mqttClient.on('close', () => console.log('❌ Disconnected from MQTT Broker'));

// --- Main Message Handler ---
mqttClient.on('message', async (topic, payload) => {
  try {
    const data = JSON.parse(payload.toString());
    // Do not log every message to reduce console noise
    // console.log(`📨 Message received on ${topic}`); 

    if (topic === `${TOPIC_PREFIX}/sensor/state`) {
      await handleSensorData(data);
      checkSensorAlerts(data);
    } else if (topic === `${TOPIC_PREFIX}/sys/online`) {
      await handleOnlineStatus(data);
    } else if (topic === `${TOPIC_PREFIX}/device/state`) {
      await handleDeviceState(data);
    }

  } catch (error) {
    console.error('❌ Failed to process message:', error);
  }
});

// --- Database & Business Logic ---
async function handleDeviceState(data) {
  if (data.light !== undefined && data.light !== lastLightState) {
    const eventType = data.light === 'on' ? 'LIGHT_ON' : 'LIGHT_OFF';
    await logEvent(eventType, { state: data.light });
    lastLightState = data.light;
  }
  if (data.fan !== undefined && data.fan !== lastFanState) {
    const eventType = data.fan === 'on' ? 'FAN_ON' : 'FAN_OFF';
    await logEvent(eventType, { state: data.fan });
    lastFanState = data.fan;
  }
}
async function handleSensorData(data) {
  const { temp_c, hum_pct, gas, pressure, lux } = data;
  const query = 'INSERT INTO sensor_data(temperature, humidity, gas, pressure, lux) VALUES($1, $2, $3, $4, $5)';
  try {
    await pgPool.query(query, [temp_c, hum_pct, gas, pressure, lux]);
    console.log('💾 Sensor data saved to database.');
  } catch (err) {
    console.error('❌ Error saving sensor data:', err.stack);
  }
}

async function logEvent(type, details) {
  const query = 'INSERT INTO events(type, details) VALUES($1, $2)';
  try {
    await pgPool.query(query, [type, details]);
    console.log(`💾 Event '${type}' saved to database.`);
  } catch (err) {
    console.error(`❌ Error saving event '${type}':`, err.stack);
  }
}

async function handleOnlineStatus(data) {
    const isOnline = data.online === true;
    const eventType = isOnline ? 'DEVICE_ONLINE' : 'DEVICE_OFFLINE';
    await logEvent(eventType, data);

    if (isOnline) {
        sendTelegramAlert('✅ THIẾT BỊ TRỰC TUYẾN', 'Thiết bị IoT đã trực tuyến trở lại!');
    } else {
        sendTelegramAlert('🛑 THIẾT BỊ NGOẠI TUYẾN', 'Thiết bị IoT đã ngoại tuyến!\nLast Will Testament đã được kích hoạt.');
    }
}

// --- Alerting Logic (Complete Implementation) ---
function checkSensorAlerts(data) {
  const now = Date.now();
  const { temp_c, gas, lux } = data;

  // Temperature Alert
  if (temp_c >= TEMP_HIGH_C) {
    tempHighStreak++;
    if (tempHighStreak >= STREAK_NEEDED && (now - lastTempAlert) >= ALERT_COOLDOWN_MS) {
      const title = '🔥 CẢNH BÁO NHIỆT ĐỘ CAO';
      const message = `Nhiệt độ: ${temp_c}°C. Ngưỡng đã bị vượt qua!`;
      console.log(title, message);
      logEvent('ALERT_TEMP_HIGH', { temperature: temp_c });
      sendTelegramAlert(title, message);
      lastTempAlert = now; tempHighStreak = 0;
    }
  } else {
    tempHighStreak = 0;
  }

  // Gas Alert
  if (gas >= GAS_HIGH) {
    gasHighStreak++;
    if (gasHighStreak >= STREAK_NEEDED && (now - lastGasAlert) >= ALERT_COOLDOWN_MS) {
      const title = '☠️ CẢNH BÁO RÒ RỈ GAS';
      const message = `Mức Gas: ${gas}. Phát hiện nồng độ gas nguy hiểm!`;
      console.log(title, message);
      logEvent('ALERT_GAS_HIGH', { gas_level: gas });
      sendTelegramAlert(title, message);
      mqttClient.publish(CMD_TOPIC, JSON.stringify({ trigger_alert: 'blink' }), { qos: 1 });
      lastGasAlert = now; gasHighStreak = 0;
    }
  } else {
    gasHighStreak = 0;
  }

  // Low Light Alert
  if (lux <= LUX_LOW) {
    luxLowStreak++;
    if (luxLowStreak >= STREAK_NEEDED && (now - lastLuxAlert) >= ALERT_COOLDOWN_MS) {
        const title = '🤖 Chế Độ Đèn Tự Động';
        const message = 'Đã kích hoạt chế độ tự động bật/tắt đèn do trời tối.';
        console.log(title, message);
        logEvent('EVENT_AUTO_LIGHT', { lux: lux });
        sendTelegramAlert(title, message);
        mqttClient.publish(CMD_TOPIC, JSON.stringify({ auto_light: 'on' }), { qos: 1 });
        lastLuxAlert = now;
    }
  } else {
      luxLowStreak = 0;
  }
}

// --- Telegram Notification Function ---
async function sendTelegramAlert(title, message) {
    const botToken = process.env.TELEGRAM_BOT_TOKEN;
    const chatId = process.env.TELEGRAM_CHAT_ID;

    if (!botToken || !chatId || botToken === 'YOUR_TELEGRAM_BOT_TOKEN') {
        console.error('❌ Telegram Bot Token or Chat ID is not configured. Skipping notification.');
        return;
    }

    const fullMessage = `${title}\n\n${message}\n\n📍 Vị trí: Phòng Lab 1\n🕐 Thời gian: ${new Date().toLocaleString()}`;
    const url = `https://api.telegram.org/bot${botToken}/sendMessage`;

    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ chat_id: chatId, text: fullMessage, parse_mode: 'Markdown' })
        });
        
        if (response.ok) {
            console.log(`📤 Đã gửi cảnh báo Telegram: ${title}`);
        } else {
            console.error('❌ Gửi cảnh báo Telegram thất bại:', await response.text());
        }
    } catch (error) {
        console.error('❌ Lỗi gửi cảnh báo Telegram:', error.message);
    }
}

console.log('✅ IoT Data Service is running and ready to send alerts.');

// =================================================================
// API Server for Historical Data
// =================================================================
const app = express();
const apiPort = 3001;

// Middleware to enable CORS for dashboard access
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
    next();
});

app.get('/api/history', async (req, res) => {
    const { range = '24h', time } = req.query;
    let baseTime = time ? new Date(time) : new Date();

    console.log(`✅ API: Request for /api/history with range: ${range}, time: ${baseTime.toISOString()}`);

    let interval, date_trunc_unit, startTime;

    switch (range) {
        case '1h':
            interval = '1 hour';
            date_trunc_unit = 'minute';
            startTime = new Date(baseTime.getTime() - 60 * 60 * 1000);
            break;
        case '7d':
            interval = '7 days';
            date_trunc_unit = 'day';
            startTime = new Date(baseTime.getTime() - 7 * 24 * 60 * 60 * 1000);
            break;
        case '30d':
            interval = '1 month';
            date_trunc_unit = 'day';
            startTime = new Date(Date.UTC(baseTime.getUTCFullYear(), baseTime.getUTCMonth(), 1)); // Start of the selected month
            const endOfMonth = new Date(Date.UTC(baseTime.getUTCFullYear(), baseTime.getUTCMonth() + 1, 0, 23, 59, 59, 999)); // End of the selected month
            baseTime = endOfMonth; // Set baseTime to end of month for the query
            break;
        default: // 24h
            interval = '24 hours';
            date_trunc_unit = 'hour';
            startTime = new Date(baseTime.getTime() - 24 * 60 * 60 * 1000);
            break;
    }

    try {
        const historyQuery = `
            SELECT
                DATE_TRUNC($1, timestamp) as time_bucket,
                AVG(temperature) as avg_temp,
                AVG(humidity) as avg_hum,
                AVG(gas) as avg_gas,
                AVG(lux) as avg_lux
            FROM
                sensor_data
            WHERE
                timestamp BETWEEN $2 AND $3
            GROUP BY
                time_bucket
            ORDER BY
                time_bucket ASC;
        `;
        const { rows } = await pgPool.query(historyQuery, [date_trunc_unit, startTime, baseTime]);
        res.json(rows);
        console.log(`✅ API: Sent ${rows.length} records for range '${range}'.`);
    } catch (err) {
        console.error(`❌ API Error fetching history for range '${range}':`, err.stack);
        res.status(500).json({ error: 'Failed to fetch historical data' });
    }
});




const server = http.createServer(app);
server.listen(apiPort, () => {
    console.log(`✅ API server for historical data listening on http://localhost:${apiPort}`);
});
