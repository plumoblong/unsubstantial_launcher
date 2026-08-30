extends Control

@export var gh : DownloadManager
var chosen_version : Version  # set from your version-picker UI

@onready var version_choose : OptionButton = get_node("Panel/Container/VersionChoose")
@onready var change_log_text : RichTextLabel = get_node("Panel/ChangeLog/Text")

@export var versions : Array[Version]

func _ready() -> void:
	gh.release_fetched.connect(_on_release_fetched)
	gh.asset_downloaded.connect(_on_asset_downloaded)
	
func _on_button_pressed() -> void:
	if chosen_version == null:
		push_error("No version selected.")
		return
	gh.get_release_by_tag(chosen_version.tag)

func _on_release_fetched(data: Dictionary) -> void:
	
	chosen_version = versions[version_choose.selected]
	
	print(data["tag_name"])
	# Assumes each release has one downloadable asset (e.g. a single zip).
	# If a release can have several assets, filter/pick the right one here
	# instead of downloading all of them.
	for asset in data["assets"]:
		print(asset["name"], asset["id"], asset["size"])
		gh.download_asset(asset["id"], data["tag_name"])


func _on_asset_downloaded(save_path: String) -> void:
	gh.extract_zip_and_delete(save_path, gh.SAVE_PATH + "/" + gh.last_asset_name)

func _get_version_changelog(version : int) -> String:
	return versions[version].change_log


func _on_version_choose_item_selected(index: int) -> void:
	change_log_text.text = _get_version_changelog(index)
