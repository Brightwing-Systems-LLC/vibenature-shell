class_name PixelNumber
extends Node2D

## A number in pixel digits: the bench's `ui/digits` sheet (ten frames, 0–9) when it
## exists, else a built-in 3×5 font with a one-pixel shadow.

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "011", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
}

var value := -1
var color := Color("fbff86")
var shadow := Color("2e222f")
var _sheet: Texture2D
var _digit_size := Vector2i(3, 5)


func _init() -> void:
	var meta := AssetLibrary.load_meta("ui", "digits")
	_sheet = AssetLibrary.load_texture("ui", "digits", "digits")
	if _sheet != null and meta.has("frame_w"):
		_digit_size = Vector2i(int(meta["frame_w"]), int(meta["frame_h"]))
	else:
		_sheet = null


## Returns true if the shown value changed (the caller redraws its window).
func set_value(new_value: int) -> bool:
	if new_value == value:
		return false
	value = new_value
	queue_redraw()
	return true


func _draw() -> void:
	if value < 0:
		return
	var x := 0
	for ch in str(value):
		if _sheet != null:
			var region := Rect2(int(ch) * _digit_size.x, 0, _digit_size.x, _digit_size.y)
			draw_texture_rect_region(_sheet, Rect2(x, 0, _digit_size.x, _digit_size.y), region)
		else:
			var glyph: Array = GLYPHS[ch]
			for row in glyph.size():
				var line := String(glyph[row])
				for column in line.length():
					if line[column] == "1":
						draw_rect(Rect2(x + column + 1, row + 1, 1, 1), shadow)
			for row in glyph.size():
				var line := String(glyph[row])
				for column in line.length():
					if line[column] == "1":
						draw_rect(Rect2(x + column, row, 1, 1), color)
		x += _digit_size.x + 1
