
require('dotenv').config({ override: true });
const { Pool } = require('pg');

console.log('DEBUG: PGHOST=', process.env.PGHOST);
console.log('DEBUG: PGPORT=', process.env.PGPORT);

// If running locally against a Docker container, PGHOST is likely 'postgres'.
// We need to override it to 'localhost' and use the mapped port.
const isRunningLocally = process.env.PGHOST === 'postgres';
const dbHost = isRunningLocally ? 'localhost' : process.env.PGHOST;
const dbPort = isRunningLocally ? 5433 : process.env.PGPORT;

// --- Database Client Setup ---
const pgPool = new Pool({
  host: dbHost,
  port: dbPort,
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
  const batchSize = 1000; // Insert 1000 records at a time

  // Set time to 30 days ago from now
  let currentTime = new Date();
  currentTime.setDate(currentTime.getDate() - daysToGenerate);
  currentTime.setUTCHours(0, 0, 0, 0); // Start from the beginning of that day

  const now = new Date(); // Current time to stop generation

  console.log(`Target: ${totalPoints} data points across ${daysToGenerate} days, starting from ${currentTime.toUTCString()}`);

  try {
    await client.query('BEGIN'); // Start transaction

    // Clear old data to prevent runaway database growth during testing
    console.log('🗑️  Clearing all existing sensor and event data...');
    await client.query('TRUNCATE TABLE sensor_data, events RESTART IDENTITY;');
    console.log('✅ Tables cleared.');

    let values = [];
    for (let i = 0; i < totalPoints; i++) {
      // Stop if we've reached the current time
      if (currentTime > now) {
        break;
      }
      const timestamp = new Date(currentTime.getTime()); // Clone date object

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

      values.push(timestamp, temperature.toFixed(2), humidity.toFixed(2), Math.round(gas), pressure.toFixed(2), Math.round(lux));

      // Increment time for the next historical data point
      currentTime.setTime(currentTime.getTime() + (intervalMinutes * 60 * 1000));

      // Insert in batches
      if (values.length / 6 >= batchSize || (i + 1) === totalPoints) {
        const placeholders = values.map((_, index) => `$${index + 1}`).reduce((acc, val, index) => {
            return index % 6 === 0 ? [...acc, `(${val}, $${index + 2}, $${index + 3}, $${index + 4}, $${index + 5}, $${index + 6})`] : acc;
        }, []).join(', ');

        const query = `INSERT INTO sensor_data(timestamp, temperature, humidity, gas, pressure, lux) VALUES ${placeholders}`;
        await client.query(query, values);
        
        process.stdout.write(`\r💾 Inserted ${i + 1} of ${totalPoints} data points...`);
        values = []; // Reset for next batch
      }
    }
    await client.query('COMMIT'); // Commit transaction
    console.log(`\n✅ Successfully inserted ${totalPoints} fake data points into the 'sensor_data' table.`);

  } catch (error) {
    await client.query('ROLLBACK'); // Rollback on error
    console.error('\n❌ An error occurred during data generation:', error);
  } finally {
    client.release();
    await pgPool.end();
    console.log('🐘 Disconnected from PostgreSQL.');
  }
}

generateData();