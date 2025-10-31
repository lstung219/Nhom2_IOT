// IoT Alert System with Telegram Integration
const mqtt = require('mqtt');

// Configuration
const MQTT_URL = 'wss://broker.hivemq.com:8884/mqtt'; // Use secure public HiveMQ broker
const NS = 'lstiot/lab/room1'; // Namespace should match firmware

const TELEGRAM_BOT_TOKEN = '8414677035:AAFHOUtn3iqlQjItseRsVHUCreu86TPVTDI';
const TELEGRAM_CHAT_ID = '1429518902';
const TELEGRAM_API_URL = 'https://api.telegram.org';

// Alert thresholds
const TEMP_HIGH_C = 35.0;
const GAS_HIGH = 1800;
const LUX_LOW = 500; // New threshold for low light
const ALERT_COOLDOWN_MS = 10000; // 10 seconds for demo

let lastTempAlert = 0;
let lastGasAlert = 0;
let lastLuxAlert = 0;
let tempHighStreak = 0;
let gasHighStreak = 0;
let luxLowStreak = 0;
const STREAK_NEEDED = 5; // Reduced for demo

console.log('🚨 Hệ Thống Cảnh Báo IoT Đang Khởi Động...');
console.log('📡 Đang kết nối đến MQTT Broker:', MQTT_URL);
console.log('🤖 Telegram API:', TELEGRAM_API_URL);
console.log('');

const options = {
  clientId: 'iot-alert-system-' + Math.random().toString(16).substr(2, 8),
  clean: true,
  connectTimeout: 4000,
  reconnectPeriod: 1000,
};

const client = mqtt.connect(MQTT_URL, options);

client.on('connect', () => {
  console.log('✅ Đã kết nối đến MQTT Broker');
  // Subscribe to sensor and system topics
  client.subscribe(`${NS}/sensor/state`, { qos: 1 });
  client.subscribe(`${NS}/sys/online`, { qos: 1 });
});

client.on('message', (topic, payload) => {
  try {
    const data = JSON.parse(payload.toString());
    
    if (topic === `${NS}/sensor/state`) {
      checkSensorAlerts(data);
    } else if (topic === `${NS}/sys/online`) {
      checkOnlineStatus(data);
    }
  } catch (error) {
    console.error('❌ Lỗi xử lý tin nhắn:', error);
  }
});

client.on('error', (error) => {
  console.error('❌ Lỗi MQTT Client:', error);
});

client.on('close', () => {
  console.log('❌ Đã ngắt kết nối khỏi MQTT Broker');
});

client.on('reconnect', () => {
  console.log('🔄 Đang kết nối lại đến MQTT Broker...');
});


// Check sensor data for alerts
function checkSensorAlerts(data) {
    const now = Date.now();
    const { temp_c, gas, lux } = data; // Added lux
    
    // Temperature alert
    if (temp_c >= TEMP_HIGH_C) {
        tempHighStreak++;
        console.log(`🌡️ Phát hiện nhiệt độ cao: ${temp_c}°C (chuỗi: ${tempHighStreak}/${STREAK_NEEDED})`);
        
        if (tempHighStreak >= STREAK_NEEDED && (now - lastTempAlert) >= ALERT_COOLDOWN_MS) {
            sendTelegramAlert('🔥 CẢNH BÁO NHIỆT ĐỘ CAO', `Nhiệt độ: ${temp_c}°C\nNgưỡng đã bị vượt qua trong ${STREAK_NEEDED} lần đọc liên tiếp!`);
            lastTempAlert = now;
            tempHighStreak = 0;
        }
    } else {
        if (tempHighStreak > 0) {
            console.log(`🌡️ Nhiệt độ đã ổn định: ${temp_c}°C`);
        }
        tempHighStreak = 0;
    }
    
    // Gas alert
    if (gas >= GAS_HIGH) {
        gasHighStreak++;
        console.log(`💨 Phát hiện mức gas cao: ${gas} (chuỗi: ${gasHighStreak}/${STREAK_NEEDED})`);
        
        if (gasHighStreak >= STREAK_NEEDED && (now - lastGasAlert) >= ALERT_COOLDOWN_MS) {
            sendTelegramAlert('☠️ CẢNH BÁO RÒ RỈ GAS', `Mức Gas: ${gas}\nPhát hiện nồng độ gas nguy hiểm!\nSơ tán ngay lập tức!`);
            
            // Send command to blink alert light on device
            console.log('✅ Gas cao, gửi lệnh chớp đèn cảnh báo...');
            const command = { trigger_alert: 'blink' };
            client.publish(`${NS}/device/cmd`, JSON.stringify(command), { qos: 1 });

            lastGasAlert = now;
            gasHighStreak = 0;
        }
    } else {
        if (gasHighStreak > 0) {
            console.log(`💨 Mức gas đã ổn định: ${gas}`);
        }
        gasHighStreak = 0;
    }

    // Auto-light mode trigger
    if (lux <= LUX_LOW) {
        luxLowStreak++;
        console.log(`💡 Phát hiện ánh sáng yếu: ${lux} (chuỗi: ${luxLowStreak}/${STREAK_NEEDED})`);
        
        if (luxLowStreak >= STREAK_NEEDED && (now - lastLuxAlert) >= ALERT_COOLDOWN_MS) {
            console.log('✅ Ánh sáng yếu, gửi lệnh bật chế độ tự động...');
            const command = { auto_light: 'on' };
            client.publish(`${NS}/device/cmd`, JSON.stringify(command), { qos: 1 });

            // Also send a Telegram notification that auto mode was enabled
            sendTelegramAlert('🤖 Chế Độ Đèn Tự Động', 'Đã kích hoạt chế độ tự động bật/tắt đèn do trời tối.');

            lastLuxAlert = now;
            // We don't reset the streak here, to avoid re-sending the command over and over.
            // It will only be sent again after the light level goes up and comes back down.
        }
    } else {
        if (luxLowStreak > 0) {
            console.log(`💡 Mức sáng đã ổn định: ${lux}`);
        }
        luxLowStreak = 0; // Reset streak when light is sufficient
    }
}

// Check device online status
function checkOnlineStatus(data) {
    if (data.online === false) {
        sendTelegramAlert('🛑 THIẾT BỊ NGOẠI TUYẾN', 'Thiết bị IoT đã ngoại tuyến!\nLast Will Testament đã được kích hoạt.');
    } else if (data.online === true) {
        sendTelegramAlert('✅ THIẾT BỊ TRỰC TUYẾN', 'Thiết bị IoT đã trực tuyến trở lại!');
    }
}

// Send alert to Telegram
async function sendTelegramAlert(title, message) {
    const fullMessage = `${title}\n\n${message}\n\n📍 Vị trí: Phòng Lab 1\n🕐 Thời gian: ${new Date().toLocaleString()}`;
    
    try {
        const response = await fetch(`${TELEGRAM_API_URL}/bot${TELEGRAM_BOT_TOKEN}/sendMessage`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                chat_id: TELEGRAM_CHAT_ID,
                text: fullMessage,
                parse_mode: 'Markdown'
            })
        });
        
        if (response.ok) {
            console.log(`📤 Đã gửi cảnh báo Telegram: ${title}`);
        } else {
            console.error('❌ Gửi cảnh báo Telegram thất bại:', response.statusText);
        }
    } catch (error) {
        console.error('❌ Lỗi gửi cảnh báo Telegram:', error.message);
    }
}



console.log('🎯 Hệ Thống Cảnh Báo đang chạy...');
console.log('🔍 Đang theo dõi các ngưỡng:');
console.log(`├── Nhiệt độ: >${TEMP_HIGH_C}°C`);
console.log(`├── Mức Gas: >${GAS_HIGH}`);
console.log(`├── Mức Sáng: <${LUX_LOW}`);
console.log(`├── Yêu cầu chuỗi: ${STREAK_NEEDED}`);
console.log(`└── Thời gian chờ: ${ALERT_COOLDOWN_MS/1000}s`);
console.log('');