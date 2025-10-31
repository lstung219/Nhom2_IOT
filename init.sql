
CREATE TABLE IF NOT EXISTS sensor_data (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    temperature NUMERIC(5, 2),
    humidity NUMERIC(5, 2),
    gas INT,
    pressure NUMERIC(7, 2),
    lux INT
);

-- Create a table to log important system events and alerts
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    type VARCHAR(50) NOT NULL, -- e.g., 'ALERT_TEMP_HIGH', 'DEVICE_OFFLINE'
    details JSONB -- Store the full event payload for context
);

-- Create indexes on the timestamp columns for faster queries
CREATE INDEX IF NOT EXISTS idx_sensor_data_timestamp ON sensor_data(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);

-- Insert a confirmation event to verify initialization
INSERT INTO events (type, details) VALUES ('SYSTEM_INIT', '{"message": "Database initialized successfully"}');


