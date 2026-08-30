extends Node
class_name DownloadManager
## GitHubReleases
## Minimal helper for fetching release info and downloading release assets
## from GitHub, including private repositories.
##
## Usage:
##   var gh = GitHubReleases.new()
##   add_child(gh)
##   gh.token = "ghp_yourPersonalAccessToken"   # leave "" for public repos
##   gh.owner = "your-org-or-username"
##   gh.repo  = "your-repo-name"
##
##   gh.release_fetched.connect(_on_release_fetched)
##   gh.get_latest_release()
##
## For private repos, your token needs the "repo" scope
## (classic PAT) or "Contents: Read-only" (fine-grained PAT).

const SAVE_PATH : String = "user://"
var last_asset_name : String

signal release_fetched(release_data: Dictionary)
signal releases_fetched(releases: Array)
signal fetch_failed(error_msg: String)
signal asset_download_progress(bytes_downloaded: int, bytes_total: int)
signal asset_downloaded(save_path: String)
signal asset_download_failed(error_msg: String)

const TOKEN : String = ""
const DELETE_ZIP_AFTER_EXTRACT : bool = true

var _api_request : HTTPRequest
var _download_request : HTTPRequest


func _ready() -> void:
	_api_request = HTTPRequest.new()
	add_child(_api_request)
	_api_request.request_completed.connect(_on_api_request_completed)

	_download_request = HTTPRequest.new()
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_request_completed)


func _headers() -> PackedStringArray:
	var headers : PackedStringArray = PackedStringArray([
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: Godot-Engine",
	])
	#if TOKEN != "":
		#headers.append("Authorization: Bearer " + TOKEN)
	return headers


## Fetch the single latest published release (not drafts/prereleases).
#func get_latest_release() -> void:
	#var url := "https://api.github.com/repos/plumoblong/unsubstantial/releases/latest"
	#_api_request.request(url, _headers(), HTTPClient.METHOD_GET)


## Fetch a specific release by tag, e.g. "v1.2.0".
func get_release_by_tag(tag: String) -> void:
	var url : String = "https://api.github.com/repos/plumoblong/unsubstantial/releases/tags/" + tag
	_api_request.request(url, _headers(), HTTPClient.METHOD_GET)


## Fetch all releases (paginated, up to `per_page` most recent).
func get_all_releases(per_page: int = 30) -> void:
	var url := "https://api.github.com/repos/plumoblong/unsubstantial/releases?per_page=" + str(per_page)
	_api_request.request(url, _headers(), HTTPClient.METHOD_GET)


func _on_api_request_completed(result: int, response_code: int, _head: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		fetch_failed.emit("HTTP request failed, result code:" + str(result))
		return

	var text : String = body.get_string_from_utf8()

	if response_code == 401:
		fetch_failed.emit("401 Unauthorized — token missing or invalid")
		return
	if response_code == 404:
		fetch_failed.emit("404 Not Found")
		return
	if response_code != 200:
		fetch_failed.emit("Unexpected response code " + str(response_code) + text)
		return

	var json : JSON = JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		fetch_failed.emit("Failed to parse JSON response.")
		return

	var data = json.get_data()
	if data is Array:
		releases_fetched.emit(data)
	else:
		release_fetched.emit(data)


## Download a specific release asset by its numeric asset ID.
## You get asset IDs from the "assets" array in a release response
## (each asset dict has an "id" field, "name", and "size").
## This uses the asset API endpoint, which is REQUIRED for private repos
## (the plain "browser_download_url" only works unauthenticated on public repos).
func download_asset(asset_id: int, asset_name : String) -> void:
	var url := "https://api.github.com/repos/plumoblong/unsubstantial/releases/assets/" + str(asset_id)
	var headers := PackedStringArray([
		"Accept: application/octet-stream",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: Godot-Engine",
	])
	#if token != "":
		#headers.append("Authorization: Bearer %s" % token)
	var path : String = SAVE_PATH + "/" + asset_name + ".zip"

	_download_request.download_file = path
	_download_request.request(url, headers, HTTPClient.METHOD_GET)
	
	last_asset_name = asset_name

func _on_download_request_completed(result: int, response_code: int, _head: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		asset_download_failed.emit("Download failed, result code: " + str(result))
		return
	if response_code != 200:
		asset_download_failed.emit("Unexpected response code " + str(response_code) + " while downloading asset.")
		return
	asset_downloaded.emit(_download_request.download_file)


func _process(_delta: float) -> void:
	# Optional: report progress on an active download.
	if _download_request.get_http_client_status() == HTTPClient.STATUS_BODY:
		var downloaded : int = _download_request.get_downloaded_bytes()
		var total : int = _download_request.get_body_size()
		if total > 0:
			asset_download_progress.emit(downloaded, total)
			
## Extracts the contents of a zip file into dest_dir, then deletes the zip file.
## Returns true on success, false on failure.
func extract_zip_and_delete(zip_path: String, dest_dir: String) -> bool:
	if not FileAccess.file_exists(zip_path):
		push_error("Zip file does not exist: %s" % zip_path)
		return false

	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		push_error("Failed to open zip file '%s': %s" % [zip_path, error_string(err)])
		return false

	# Make sure destination directory exists
	var dir_err := DirAccess.make_dir_recursive_absolute(dest_dir)
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		push_error("Failed to create destination directory '%s': %s" % [dest_dir, error_string(dir_err)])
		reader.close()
		return false

	var files: PackedStringArray = reader.get_files()

	for file_path in files:
		var full_path := dest_dir.path_join(file_path)

		# Directory entries in zips usually end with "/"
		if file_path.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(full_path)
			continue

		# Ensure parent directories exist before writing the file
		var parent_dir := full_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(parent_dir):
			DirAccess.make_dir_recursive_absolute(parent_dir)

		var file_data: PackedByteArray = reader.read_file(file_path)

		var out_file := FileAccess.open(full_path, FileAccess.WRITE)
		if out_file == null:
			push_error("Failed to create file '%s': %s" % [full_path, error_string(FileAccess.get_open_error())])
			reader.close()
			return false

		out_file.store_buffer(file_data)
		out_file.close()

	reader.close()

	# Delete the zip file after successful extraction
	var del_err := DirAccess.remove_absolute(zip_path)
	if del_err != OK:
		push_error("Failed to delete zip file '%s': %s" % [zip_path, error_string(del_err)])
		return false

	return true
