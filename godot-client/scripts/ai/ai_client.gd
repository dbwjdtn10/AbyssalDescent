## Singleton autoload that communicates with the FastAPI AI server.
##
## Register this script as an autoload named "AIClient" in
## Project -> Project Settings -> Autoload.
##
## Usage example:
##   AIClient.dungeon_generated.connect(_on_dungeon_generated)
##   AIClient.generate_dungeon(1, 0.5, 1, [], [], 42)
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal dungeon_generated(data: Dictionary)
signal npc_response_received(data: Dictionary)
signal npc_state_received(data: Dictionary)
signal item_generated(data: Dictionary)
signal quest_generated(data: Dictionary)
signal difficulty_adapted(data: Dictionary)
signal server_health_checked(is_healthy: bool)
signal ai_error(endpoint: String, error: String)

# ── Configuration ────────────────────────────────────────────────────────────

## AI configuration resource.  Assign in the inspector or leave null to use
## defaults created at runtime.
@export var config: AIConfig = null

# ── Internal Types ───────────────────────────────────────────────────────────

## Metadata attached to every queued / in-flight request.
class _RequestInfo:
	var endpoint: String
	var method: String  # "GET" or "POST"
	var body: Dictionary
	var callback: Callable
	var attempt: int = 0

# ── Internal State ───────────────────────────────────────────────────────────

## Pool of reusable HTTPRequest nodes.
var _http_pool: Array[HTTPRequest] = []

## Requests currently in flight (HTTPRequest node -> _RequestInfo).
var _active_requests: Dictionary = {}

## FIFO queue of _RequestInfo objects waiting to be dispatched.
var _request_queue: Array = []

## Reference to the cache node (sibling or child – resolved in _ready).
var _cache: AICache = null

## Reference to the fallback data provider.
var _fallback: AIFallback = null

## Whether the server was reachable on the last health check.
var _server_healthy: bool = false

## Timer used for periodic health checks.
var _health_timer: Timer = null

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Create a default config if none was assigned in the editor.
	if config == null:
		config = AIConfig.new()

	# Load saved settings (server URL + API key) from disk.
	config.load_settings()

	# Ensure helper nodes exist.
	_cache = AICache.new()
	_cache.name = "AICache"
	add_child(_cache)

	_fallback = AIFallback.new()
	_fallback.name = "AIFallback"
	add_child(_fallback)

	# Pre-create the HTTP request pool.
	for i in range(config.max_concurrent_requests):
		var http := HTTPRequest.new()
		http.name = "HTTPRequest_%d" % i
		http.timeout = config.request_timeout
		add_child(http)
		_http_pool.append(http)

	# Periodic health check.
	if config.health_check_interval > 0.0:
		_health_timer = Timer.new()
		_health_timer.name = "HealthTimer"
		_health_timer.wait_time = config.health_check_interval
		_health_timer.autostart = false
		_health_timer.timeout.connect(_on_health_timer_timeout)
		add_child(_health_timer)

		# Delay the first ping slightly so the rest of the scene tree is ready.
		await get_tree().create_timer(config.initial_connect_delay).timeout
		check_health()
		_health_timer.start()


# ── Public API ───────────────────────────────────────────────────────────────

## POST /api/dungeon/generate
func generate_dungeon(
	floor_num: int,
	difficulty,  # accepts String enum ("easy","normal","hard","nightmare","abyss") or float (0.0-1.0)
	player_level: int,
	player_inventory: Array,
	visited_room_types: Array,
	seed_val: int
) -> void:
	var body: Dictionary = {
		"floor_number": floor_num,
		"difficulty": _difficulty_to_enum(difficulty),
		"player_level": player_level,
		"player_inventory": player_inventory,
		"visited_room_types": visited_room_types,
		"seed": seed_val,
	}

	# If server is known to be offline, skip HTTP and use fallback immediately.
	if not _server_healthy and _fallback != null:
		var fallback_data: Dictionary = _fallback.get_fallback_dungeon(floor_num)
		if not fallback_data.is_empty():
			# Use call_deferred so the signal connection happens before emission.
			call_deferred("_emit_dungeon_fallback", fallback_data)
			return

	_post_request("api/dungeon/generate", body, _on_dungeon_generated)


## POST /api/npc/chat
func chat_with_npc(
	npc_id: String,
	player_message: String,
	player_state: Dictionary,
	conversation_history: Array
) -> void:
	var body: Dictionary = {
		"npc_id": npc_id,
		"player_message": player_message,
		"player_state": player_state,
		"conversation_history": conversation_history,
	}
	_post_request("api/npc/chat", body, _on_npc_response)


## GET /api/npc/{npc_id}/state
func get_npc_state(npc_id: String) -> void:
	var endpoint: String = "api/npc/%s/state" % npc_id
	_get_request(endpoint, _on_npc_state)


## POST /api/content/item
func generate_item(
	floor_number: int,
	rarity: String,
	item_type: String,
	context: Dictionary
) -> void:
	var body: Dictionary = {
		"floor_number": floor_number,
		"rarity": rarity,
		"item_type": item_type,
		"context": context,
	}
	_post_request("api/content/item", body, _on_item_generated)


## POST /api/content/quest
func generate_quest(
	trigger: String,
	npc_id: String,
	player_state: Dictionary
) -> void:
	var body: Dictionary = {
		"trigger": trigger,
		"npc_id": npc_id,
		"player_state": player_state,
	}
	_post_request("api/content/quest", body, _on_quest_generated)


## POST /api/dungeon/adapt
func adapt_difficulty(player_history: Dictionary) -> void:
	_post_request("api/dungeon/adapt", player_history, _on_difficulty_adapted)


## POST /api/game/analyze — full game state analysis (quest triggers + difficulty + tips)
signal game_state_analyzed(data: Dictionary)

func analyze_game_state(game_state: Dictionary) -> void:
	_post_request("api/game/analyze", game_state, _on_game_state_analyzed)

func _on_game_state_analyzed(data: Dictionary) -> void:
	game_state_analyzed.emit(data)


## Convert float difficulty (0.0-1.0) to server enum string.
static func _difficulty_to_enum(value) -> String:
	if value is String:
		return value
	var f: float = float(value)
	if f <= 0.2:
		return "easy"
	elif f <= 0.4:
		return "normal"
	elif f <= 0.6:
		return "hard"
	elif f <= 0.8:
		return "nightmare"
	else:
		return "abyss"


## GET /api/health
func check_health() -> void:
	_get_request("api/health", _on_health_checked)


# ── Response Callbacks (map parsed JSON to signals) ──────────────────────────

func _on_dungeon_generated(data: Dictionary) -> void:
	dungeon_generated.emit(data)


func _emit_dungeon_fallback(data: Dictionary) -> void:
	dungeon_generated.emit(data)

func _on_npc_response(data: Dictionary) -> void:
	npc_response_received.emit(data)

func _on_npc_state(data: Dictionary) -> void:
	npc_state_received.emit(data)

func _on_item_generated(data: Dictionary) -> void:
	item_generated.emit(data)

func _on_quest_generated(data: Dictionary) -> void:
	quest_generated.emit(data)

func _on_difficulty_adapted(data: Dictionary) -> void:
	difficulty_adapted.emit(data)

func _on_health_checked(data: Dictionary) -> void:
	_server_healthy = data.get("status", "") == "ok" or data.get("healthy", false)
	server_health_checked.emit(_server_healthy)


# ── Request Dispatch (internal) ──────────────────────────────────────────────

## Enqueue a POST request.
func _post_request(endpoint: String, body: Dictionary, callback: Callable) -> void:
	var info := _RequestInfo.new()
	info.endpoint = endpoint
	info.method = "POST"
	info.body = body
	info.callback = callback
	_enqueue(info)


## Enqueue a GET request.
func _get_request(endpoint: String, callback: Callable) -> void:
	var info := _RequestInfo.new()
	info.endpoint = endpoint
	info.method = "GET"
	info.body = {}
	info.callback = callback
	_enqueue(info)


## Add a request to the queue and try to flush.
func _enqueue(info: _RequestInfo) -> void:
	if _request_queue.size() >= config.max_queue_size:
		push_warning("AIClient: request queue full – dropping request to %s" % info.endpoint)
		ai_error.emit(info.endpoint, "Request queue full")
		return
	_request_queue.append(info)
	_flush_queue()


## Dispatch as many queued requests as the pool allows.
func _flush_queue() -> void:
	while _request_queue.size() > 0:
		var http := _get_available_http()
		if http == null:
			break  # All pool slots occupied; wait for completions.
		var info: _RequestInfo = _request_queue.pop_front()
		_dispatch(http, info)


## Find an HTTPRequest node that is not currently in use.
func _get_available_http() -> HTTPRequest:
	for http in _http_pool:
		if not _active_requests.has(http):
			return http
	return null


## Actually fire the HTTP request.
func _dispatch(http: HTTPRequest, info: _RequestInfo) -> void:
	var url: String = config.get_endpoint_url(info.endpoint)

	# Prepare headers.
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])

	# Include client API key if configured.
	if not config.api_key.is_empty():
		headers.append("X-API-Key: %s" % config.api_key)

	# Store tracking info BEFORE calling request() so the completion
	# handler can look it up.
	var callback_info: Dictionary = {
		"endpoint": info.endpoint,
		"method": info.method,
		"body": info.body,
		"callback": info.callback,
		"attempt": info.attempt,
		"http": http,
	}
	_active_requests[http] = callback_info

	# Connect the completion signal for this specific request.
	# We use a lambda so we can forward callback_info.
	var _on_done := func(result: int, response_code: int, resp_headers: PackedStringArray, resp_body: PackedByteArray) -> void:
		_on_request_completed(result, response_code, resp_headers, resp_body, callback_info)

	# Ensure no leftover connections from a previous request cycle.
	if http.request_completed.is_connected(_on_done):
		http.request_completed.disconnect(_on_done)

	# We must use a one-shot connection so it auto-disconnects after firing.
	http.request_completed.connect(_on_done, CONNECT_ONE_SHOT)

	var err: Error
	if info.method == "POST":
		var json_body: String = JSON.stringify(info.body)
		err = http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	else:
		err = http.request(url, headers, HTTPClient.METHOD_GET)

	if err != OK:
		push_warning("AIClient: HTTPRequest.request() failed for %s (Error %d)" % [url, err])
		_active_requests.erase(http)
		_handle_failure(callback_info, "HTTPRequest.request() returned error %d" % err)


# ── Response Handling ────────────────────────────────────────────────────────

func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	callback_info: Dictionary
) -> void:
	var http: HTTPRequest = callback_info["http"]
	_active_requests.erase(http)

	# Flush any waiting requests now that a slot opened up.
	_flush_queue.call_deferred()

	var endpoint: String = callback_info["endpoint"]
	var callback: Callable = callback_info["callback"]

	# ── Network-level failure ────────────────────────────────────────────
	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg: String = _result_to_string(result)
		push_warning("AIClient: network error for %s – %s" % [endpoint, error_msg])
		_handle_failure(callback_info, error_msg)
		return

	# ── HTTP error status ────────────────────────────────────────────────
	if response_code < 200 or response_code >= 300:
		var http_error_msg: String = "HTTP %d" % response_code
		push_warning("AIClient: server returned %s for %s" % [http_error_msg, endpoint])
		_handle_failure(callback_info, http_error_msg)
		return

	# ── Parse JSON body ──────────────────────────────────────────────────
	var json_string: String = body.get_string_from_utf8()
	var json := JSON.new()
	var parse_err := json.parse(json_string)
	if parse_err != OK:
		push_warning("AIClient: JSON parse error for %s – %s" % [endpoint, json.get_error_message()])
		_handle_failure(callback_info, "JSON parse error: %s" % json.get_error_message())
		return

	var data: Dictionary = {}
	var parsed = json.data
	if parsed is Dictionary:
		data = parsed
	else:
		data = {"result": parsed}

	# ── Cache the successful response ────────────────────────────────────
	if config.cache_enabled and _cache != null:
		var cache_key: String = _build_cache_key(endpoint, callback_info.get("body", {}))
		_cache.cache_response(cache_key, data)

	# ── Deliver to caller ────────────────────────────────────────────────
	if callback.is_valid():
		callback.call(data)


# ── Failure / Retry Handling ─────────────────────────────────────────────────

func _handle_failure(callback_info: Dictionary, error_msg: String) -> void:
	var attempt: int = callback_info.get("attempt", 0)
	var endpoint: String = callback_info["endpoint"]

	# Retry if we have attempts remaining.
	if attempt < config.max_retries:
		var delay: float = config.get_retry_delay(attempt)
		push_warning("AIClient: retrying %s in %.1fs (attempt %d/%d)" % [endpoint, delay, attempt + 1, config.max_retries])

		var retry_info := _RequestInfo.new()
		retry_info.endpoint = endpoint
		retry_info.method = callback_info["method"]
		retry_info.body = callback_info["body"]
		retry_info.callback = callback_info["callback"]
		retry_info.attempt = attempt + 1

		# Wait then re-enqueue.
		await get_tree().create_timer(delay).timeout
		_enqueue(retry_info)
		return

	# All retries exhausted – try cache, then fallback.
	push_warning("AIClient: all retries exhausted for %s" % endpoint)
	ai_error.emit(endpoint, error_msg)

	var callback: Callable = callback_info["callback"]
	var fallback_data: Dictionary = _get_fallback_for(endpoint, callback_info.get("body", {}))

	if not fallback_data.is_empty() and callback.is_valid():
		callback.call(fallback_data)


## Try to return cached data first, then static fallback data.
func _get_fallback_for(endpoint: String, body: Dictionary) -> Dictionary:
	# 1. Attempt cache.
	if config.cache_enabled and _cache != null:
		var cache_key: String = _build_cache_key(endpoint, body)
		if _cache.is_cache_valid(cache_key, config.cache_default_ttl):
			var cached := _cache.get_cached_response(cache_key)
			if not cached.is_empty():
				push_warning("AIClient: serving cached response for %s" % endpoint)
				return cached

	# 2. Static fallback.
	if _fallback == null:
		return {}

	if endpoint.begins_with("api/dungeon/generate"):
		var floor_num: int = body.get("floor_number", 1)
		return _fallback.get_fallback_dungeon(floor_num)

	if endpoint.begins_with("api/npc/chat"):
		var npc_id: String = body.get("npc_id", "unknown")
		return _fallback.get_fallback_npc_response(npc_id)

	if endpoint.find("/state") != -1 and endpoint.begins_with("api/npc/"):
		# Extract npc_id from "api/npc/<id>/state".
		var parts := endpoint.split("/")
		var state_npc_id: String = parts[2] if parts.size() > 2 else "unknown"
		return _fallback.get_fallback_npc_response(state_npc_id)

	if endpoint.begins_with("api/content/item"):
		var rarity: String = body.get("rarity", "common")
		return _fallback.get_fallback_item(rarity)

	if endpoint.begins_with("api/content/quest"):
		return _fallback.get_fallback_quest()

	if endpoint.begins_with("api/dungeon/adapt"):
		return {"difficulty_multiplier": 1.0, "fallback": true}

	if endpoint.begins_with("api/health"):
		return {"status": "offline", "fallback": true}

	return {}


# ── Helpers ──────────────────────────────────────────────────────────────────

## Build a deterministic cache key from endpoint + request body.
func _build_cache_key(endpoint: String, body: Dictionary) -> String:
	var raw: String = endpoint
	if not body.is_empty():
		raw += "|" + JSON.stringify(body)
	return raw.md5_text()


## Convert an HTTPRequest.Result enum value to a human-readable string.
func _result_to_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_SUCCESS:
			return "Success"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "Chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "No response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Body size limit exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Body decompression failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Redirect limit reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "Request timed out"
		_:
			return "Unknown error (%d)" % result


func _on_health_timer_timeout() -> void:
	check_health()


## Returns true if the server was healthy on the last check.
func is_server_healthy() -> bool:
	return _server_healthy
