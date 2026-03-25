## Local disk cache for AI server responses.
##
## Cached files are stored as JSON under  user://ai_cache/<md5_key>.json
## alongside a small metadata file        user://ai_cache/<md5_key>.meta
## that records the creation timestamp so TTL checks can be performed.
class_name AICache
extends Node

# ── Constants ────────────────────────────────────────────────────────────────

const CACHE_DIR: String = "user://ai_cache/"
const META_EXTENSION: String = ".meta"
const DATA_EXTENSION: String = ".json"

# ── Internal State ───────────────────────────────────────────────────────────

## In-memory index:  cache_key -> { "timestamp": float, "file": String }
var _index: Dictionary = {}

## Whether the cache directory has been verified / created.
var _dir_ready: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_cache_dir()
	_load_index()

# ── Public API ───────────────────────────────────────────────────────────────

## Persist a response dictionary to disk under the given cache_key.
func cache_response(cache_key: String, data: Dictionary) -> void:
	_ensure_cache_dir()

	var data_path: String = _key_to_data_path(cache_key)
	var meta_path: String = _key_to_meta_path(cache_key)

	# Write JSON data.
	var data_json: String = JSON.stringify(data, "\t")
	var data_file := FileAccess.open(data_path, FileAccess.WRITE)
	if data_file == null:
		push_warning("AICache: failed to open %s for writing (error %d)" % [data_path, FileAccess.get_open_error()])
		return
	data_file.store_string(data_json)
	data_file.close()

	# Write metadata (timestamp).
	var meta: Dictionary = {
		"timestamp": Time.get_unix_time_from_system(),
		"key": cache_key,
	}
	var meta_json: String = JSON.stringify(meta)
	var meta_file := FileAccess.open(meta_path, FileAccess.WRITE)
	if meta_file == null:
		push_warning("AICache: failed to write meta for key %s" % cache_key)
		return
	meta_file.store_string(meta_json)
	meta_file.close()

	# Update in-memory index.
	_index[cache_key] = {
		"timestamp": meta["timestamp"],
		"file": cache_key,
	}


## Retrieve a previously cached response.  Returns an empty Dictionary if
## the key is not found or the file cannot be read.
func get_cached_response(cache_key: String) -> Dictionary:
	var data_path: String = _key_to_data_path(cache_key)

	if not FileAccess.file_exists(data_path):
		return {}

	var data_file := FileAccess.open(data_path, FileAccess.READ)
	if data_file == null:
		return {}

	var json_string: String = data_file.get_as_text()
	data_file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("AICache: corrupt cache file %s" % data_path)
		return {}

	if json.data is Dictionary:
		return json.data
	return {}


## Check whether a cached entry exists and has not exceeded max_age_seconds.
func is_cache_valid(cache_key: String, max_age_seconds: float) -> bool:
	# Fast path: check in-memory index first.
	if _index.has(cache_key):
		var entry: Dictionary = _index[cache_key]
		var age: float = Time.get_unix_time_from_system() - entry.get("timestamp", 0.0)
		return age <= max_age_seconds

	# Fallback: read meta file from disk.
	var meta_path: String = _key_to_meta_path(cache_key)
	if not FileAccess.file_exists(meta_path):
		return false

	var meta_file := FileAccess.open(meta_path, FileAccess.READ)
	if meta_file == null:
		return false

	var json := JSON.new()
	if json.parse(meta_file.get_as_text()) != OK:
		meta_file.close()
		return false
	meta_file.close()

	if json.data is Dictionary:
		var timestamp: float = json.data.get("timestamp", 0.0)
		var disk_age: float = Time.get_unix_time_from_system() - timestamp
		# Populate index so future lookups are fast.
		_index[cache_key] = {"timestamp": timestamp, "file": cache_key}
		return disk_age <= max_age_seconds

	return false


## Delete all cached files and reset the in-memory index.
func clear_cache() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	_index.clear()
	print("AICache: cache cleared.")


## Return the total size in bytes of all files in the cache directory.
func get_cache_size() -> int:
	var total_size: int = 0
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return 0

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var file_path: String = CACHE_DIR + file_name
			var f := FileAccess.open(file_path, FileAccess.READ)
			if f != null:
				total_size += f.get_length()
				f.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	return total_size


## Remove the oldest entries until total cache size is below max_bytes.
## Pass 0 for max_bytes to skip (unlimited).
func enforce_size_limit(max_bytes: int) -> void:
	if max_bytes <= 0:
		return

	while get_cache_size() > max_bytes:
		var oldest_key: String = _find_oldest_key()
		if oldest_key.is_empty():
			break
		_remove_entry(oldest_key)

# ── Private Helpers ──────────────────────────────────────────────────────────

## Ensure the cache directory exists on disk.
func _ensure_cache_dir() -> void:
	if _dir_ready:
		return
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		var err := DirAccess.make_dir_recursive_absolute(CACHE_DIR)
		if err != OK:
			push_warning("AICache: could not create cache dir %s (error %d)" % [CACHE_DIR, err])
			return
	_dir_ready = true


## Scan existing cache files and populate the in-memory index.
func _load_index() -> void:
	var dir := DirAccess.open(CACHE_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(META_EXTENSION):
			var meta_path: String = CACHE_DIR + file_name
			var meta_file := FileAccess.open(meta_path, FileAccess.READ)
			if meta_file != null:
				var json := JSON.new()
				if json.parse(meta_file.get_as_text()) == OK and json.data is Dictionary:
					var key: String = json.data.get("key", "")
					if key != "":
						_index[key] = {
							"timestamp": json.data.get("timestamp", 0.0),
							"file": key,
						}
				meta_file.close()
		file_name = dir.get_next()
	dir.list_dir_end()


## Map a cache_key to its data file path.
func _key_to_data_path(cache_key: String) -> String:
	return CACHE_DIR + cache_key + DATA_EXTENSION


## Map a cache_key to its metadata file path.
func _key_to_meta_path(cache_key: String) -> String:
	return CACHE_DIR + cache_key + META_EXTENSION


## Find the cache_key with the oldest timestamp.
func _find_oldest_key() -> String:
	var oldest_key: String = ""
	var oldest_time: float = INF
	for key in _index:
		var entry: Dictionary = _index[key]
		var ts: float = entry.get("timestamp", INF)
		if ts < oldest_time:
			oldest_time = ts
			oldest_key = key
	return oldest_key


## Delete data + meta files for a single cache key.
func _remove_entry(cache_key: String) -> void:
	var data_path: String = _key_to_data_path(cache_key)
	var meta_path: String = _key_to_meta_path(cache_key)

	if FileAccess.file_exists(data_path):
		DirAccess.remove_absolute(data_path)
	if FileAccess.file_exists(meta_path):
		DirAccess.remove_absolute(meta_path)

	_index.erase(cache_key)
