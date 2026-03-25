## AI server configuration resource.
## Holds all connection settings for the FastAPI AI backend.
## Attach to nodes via the inspector or load as a shared resource.
class_name AIConfig
extends Resource

# ── Server Connection ────────────────────────────────────────────────────────

## Base URL of the FastAPI AI server (no trailing slash).
@export var server_url: String = "http://localhost:8000"

## Claude API key provided by the player (sent to server via X-API-Key header).
## Empty means the server uses its own key (or no AI features).
@export var api_key: String = ""

## HTTP request timeout in seconds.
@export_range(1.0, 120.0, 0.5) var request_timeout: float = 5.0

## How long to wait before the very first health-check attempt on startup (seconds).
@export_range(0.0, 10.0, 0.5) var initial_connect_delay: float = 1.0

# ── Retry Policy ─────────────────────────────────────────────────────────────

## Maximum number of retry attempts for a failed request (0 = no retries).
@export_range(0, 10) var max_retries: int = 1

## Base delay between retries in seconds.  Actual delay uses exponential
## back-off: base_delay * 2^attempt  (capped at max_retry_delay).
@export_range(0.1, 10.0, 0.1) var retry_base_delay: float = 1.0

## Upper bound for the exponential back-off delay (seconds).
@export_range(1.0, 60.0, 1.0) var max_retry_delay: float = 16.0

# ── Request Queue ────────────────────────────────────────────────────────────

## Maximum number of concurrent HTTP requests the client may have in flight.
@export_range(1, 10) var max_concurrent_requests: int = 3

## Maximum number of requests waiting in the queue.  Requests beyond this
## limit are dropped and an ai_error signal is emitted.
@export_range(1, 100) var max_queue_size: int = 20

# ── Cache ────────────────────────────────────────────────────────────────────

## Whether response caching is enabled.
@export var cache_enabled: bool = true

## Default time-to-live for cached responses (seconds).
@export_range(1.0, 86400.0, 1.0) var cache_default_ttl: float = 300.0

## Maximum total cache size on disk (bytes).  0 = unlimited.
@export var cache_max_size_bytes: int = 10_485_760  # 10 MB

# ── Health Check ─────────────────────────────────────────────────────────────

## Interval between automatic health-check pings (seconds).  0 = disabled.
@export_range(0.0, 300.0, 1.0) var health_check_interval: float = 30.0

# ── Helpers ──────────────────────────────────────────────────────────────────

## Build a full URL from the base server_url and the given endpoint path.
func get_endpoint_url(endpoint: String) -> String:
	return server_url.rstrip("/") + "/" + endpoint.lstrip("/")


## Calculate the retry delay for the given attempt index (0-based).
func get_retry_delay(attempt: int) -> float:
	var delay: float = retry_base_delay * pow(2.0, float(attempt))
	return minf(delay, max_retry_delay)


# ── Settings Persistence ────────────────────────────────────────────────────

const SETTINGS_PATH: String = "user://ai_settings.json"

## Save user-facing settings (server URL + API key) to disk.
func save_settings() -> void:
	var data: Dictionary = {
		"server_url": server_url,
		"api_key": api_key,
	}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


## Load user-facing settings from disk.  Returns true if a file existed.
func load_settings() -> bool:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return false
	file.close()
	if json.data is not Dictionary:
		return false
	var data: Dictionary = json.data
	server_url = str(data.get("server_url", server_url))
	api_key = str(data.get("api_key", ""))
	return true
