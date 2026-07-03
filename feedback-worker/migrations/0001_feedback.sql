CREATE TABLE IF NOT EXISTS feedback (
  id TEXT PRIMARY KEY,
  app_id TEXT NOT NULL,
  app_name TEXT,
  app_version TEXT,
  app_build TEXT,
  bundle_id TEXT,
  platform TEXT,
  screen_name TEXT,
  text TEXT NOT NULL,
  device_json TEXT,
  screenshot_json TEXT,
  annotation_json TEXT,
  status TEXT NOT NULL DEFAULT 'new',
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_feedback_status_created_at ON feedback(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_app_created_at ON feedback(app_id, created_at DESC);

CREATE TABLE IF NOT EXISTS feedback_rate_limits (
  bucket_key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feedback_rate_limits_window ON feedback_rate_limits(window_start);
