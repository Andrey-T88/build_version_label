@tool
extends Label

## BuildVersionLabel — drop this node in any scene and it prints the build version.
## No code is needed in the scene: the node reads config/build_info.json itself, which the addon
## writes on every editor run and on every export, so the numbers never depend on the platform.

const BV := preload("res://addons/build_version_label/build_version.gd")

func _ready() -> void:
	refresh()


## Prints the build this stamp belongs to. A packaged build carries only those numbers, so the
## pending counters an editor file also holds are filtered out before rendering.
func refresh() -> void:
	var info := BV.read()
	if info.is_empty():
		text = str(BV.setting(BV.SETTING_FALLBACK, BV.DEFAULT_FALLBACK))
	else:
		text = BV.render(BV.runtime_view(info))
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if not BV.read().is_empty():
		return PackedStringArray()
	var hint := "No %s yet. Running or exporting the project writes it automatically; " % BV.BUILD_INFO_PATH
	hint += "or create it by hand: {\"version_name\":\"1.0.0\",\"version_code\":1}"
	return PackedStringArray([hint])
