
require('dotenv').config({ override: true });
const { Pool } = require('pg');

console.log('DEBUG: PGHOST=', process.env.PGHOST);
console.log('DEBUG: PGPORT=', process.env.PGPORT);

// --- Database Client Setup ---
const pgPool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  database: process.env.PGDATABASE,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
});

/**
 * Generates and inserts a high volume of fake sensor data.
 */
async function generateData() {
  console.log('🐘 Connecting to PostgreSQL...');
  const client = await pgPool.connect();
  console.log('✅ Connection successful. Generating high-volume fake data...');

  const daysToGenerate = 30; // Generate data for the last 30 full days
  const intervalMinutes = 0.5; // Two data points every minute
  const totalPoints = (daysToGenerate * 24 * 60) / intervalMinutes;

  // Set time to 30 days ago from now
  let currentTime = new Date();
  currentTime.setDate(currentTime.getDate() - daysToGenerate);
  currentTime.setUTCHours(0, 0, 0, 0); // Start from the beginning of that day

  const now = new Date(); // Current time to stop generation

  console.log(`Target: ${totalPoints} data points across ${daysToGenerate} days, starting from ${currentTime.toUTCString()}`);

  try {
    // Clear old data to prevent runaway database growth during testing
    console.log('🗑️  Clearing all existing sensor and event data...');
    await client.query('TRUNCATE TABLE sensor_data, events RESTART IDENTITY;');
    console.log('✅ Tables cleared.');

    for (let i = 0; i < totalPoints; i++) {
      // Stop if we've reached the current time
      if (currentTime > now) {
        break;
      }

      // Simulate daily cycles for more realistic data
      const hourOfDay = currentTime.getUTCHours();
      const minuteOfHour = currentTime.getUTCMinutes();
      // Calculate dayCycleSin based on current time, not decrementing time
      const dayCycleSin = Math.sin((hourOfDay * 3600 + minuteOfHour * 60) / 86400 * 2 * Math.PI);

      // Temp: Warmer during the day
      const temperature = 24 + (dayCycleSin * 6) + (Math.random() * 1.5 - 0.75);
      // Humidity: More humid at night
      const humidity = 65 - (dayCycleSin * 10) + (Math.random() * 5 - 2.5);
      // Gas: Mostly stable with some random spikes
      const gas = 350 + Math.random() * 150;
      // Pressure: Realistic atmospheric pressure with some fluctuations
      const pressure = 1000 + (dayCycleSin * 10) + (Math.random() * 10 - 5); // Around 995-1005 hPa
      // Lux: High during the day (1270-2000), lower at night (200-1000)
      const lux = (dayCycleSin > 0.1) ? (1200 + (dayCycleSin * 700) + Math.random() * 100) : (200 + Math.random() * 800);

      const query = 'INSERT INTO sensor_data(timestamp, temperature, humidity, gas, pressure, lux) VALUES($1, $2, $3, $4, $5, $6)';
      await client.query(query, [currentTime, temperature.toFixed(2), humidity.toFixed(2), Math.round(gas), pressure.toFixed(2), Math.round(lux)]);

      // Increment time for the next historical data point
      currentTime.setTime(currentTime.getTime() + (intervalMinutes * 60 * 1000));

      // Log progress
      if ((i + 1) % 1000 === 0) { // Log every 1000 points
        process.stdout.write(`\r💾 Inserted ${i + 1} of ${totalPoints} data points... Current Time: ${currentTime.toISOString()}`);
      }
    }
    console.log(`\n✅ Successfully inserted ${totalPoints} fake data points into the 'sensor_data' table.`);

  } catch (error) {
    console.error('\n❌ An error occurred during data generation:', error);
  } finally {
    client.release();
    await pgPool.end();
    console.log('🐘 Disconnected from PostgreSQL.');
  }
}

generateData();