@tool
extends Label

## BuildVersionLabel — drop this node in any scene and it prints the build version.
## No code is needed in the scene: the node reads config/build_info.json itself.

const BV := preload("res://addons/build_version_label/build_version.gd")

func _ready() -> void:
	refresh()


func refresh() -> void:
	var info := BV.read()
	if info.is_empty():
		text = str(BV.setting(BV.SETTING_FALLBACK, BV.DEFAULT_FALLBACK))
	else:
		text = BV.render(info)
	update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if not BV.read().is_empty():
		return PackedStringArray()
	var hint := "No %s yet. An Android export writes it automatically; " % BV.BUILD_INFO_PATH
	hint += "for other platforms create it by hand: {\"version_name\":\"1.0.0\",\"version_code\":1}"
	return PackedStringArray([hint])
