@tool
extends EditorPlugin

const SourceExport := preload("res://addons/content_pack_source_export/source_export.gd")
var _source_export: EditorExportPlugin


func _enter_tree() -> void:
	_source_export = SourceExport.new()
	add_export_plugin(_source_export)


func _exit_tree() -> void:
	remove_export_plugin(_source_export)
	_source_export = null
