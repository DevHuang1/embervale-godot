@tool
extends EditorPlugin

## === RevenueCatBridge — Android plugin packaging ===
##
## Registers the prebuilt Kotlin AAR with the Android exporter and declares the
## RevenueCat SDK the exported app must resolve from Maven Central. The AAR
## itself is compiled from `android-plugin/revenuecat_bridge` (see that
## module's README-comment in build.gradle for the pinned versions).

const PLUGIN_NAME := "RevenueCatBridge"
## The addon's own directory under `res://addons/`. Godot resolves every
## non-absolute library path against `res://addons/`, so this prefix must match
## the folder name.
const PLUGIN_DIRECTORY := "revenuecat_bridge"
const REVENUECAT_VERSION := "10.22.1"
const MAVEN_CENTRAL := "https://repo1.maven.org/maven2"

var _export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return PLUGIN_NAME

	## Paths are resolved against `res://addons/`, per the v2 plugin contract.
	func _get_android_libraries(_platform: EditorExportPlatform,
			debug: bool) -> PackedStringArray:
		var flavour := "debug" if debug else "release"
		return PackedStringArray([
			"%s/bin/%s/%s-%s.aar" % [PLUGIN_DIRECTORY, flavour, PLUGIN_DIRECTORY, flavour],
		])

	func _get_android_dependencies(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.revenuecat.purchases:purchases:%s" % REVENUECAT_VERSION])

	func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform,
			_debug: bool) -> PackedStringArray:
		return PackedStringArray([MAVEN_CENTRAL])
