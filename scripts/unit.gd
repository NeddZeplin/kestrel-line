class_name Unit
extends Node3D
## One unit or squad. Holds state only; behaviour lives in game.gd, as in the prototype.

var uid := 0
var type := ""
var def: Dictionary
var side := "p"
var hp := 100.0
var max_hp := 100.0
var weapons: Array = []          # [{"w": weapon dict, "cd": float, "target": Unit}]
var p := Vector2.ZERO            # ground position (x, z)
var y := 0.0
var vel := Vector2.ZERO
var heading := 0.0               # radians; forward = (sin, cos)
var tur_yaw := 0.0
var air := false
var small := false
var alt := 0.0

var tur: Node3D
var rotors: Array = []
var tail_rotor: Node3D
var men: Array = []
var berm: Node3D

var path: Array = []
var moving := false
var still_t := 0.0
var dug_in := false
var halt := false
var dead := false
var variant := 0
var invested := 0
var kills := 0
var retarget := 0.0
var stuck_t := 0.0
var spotted := false
var dtarget: Unit
var wreck_t := 0.0
var smoke_t := 0.0


func setup(t: String, s: String, id: int) -> void:
	uid = id
	type = t
	side = s
	def = GameData.DEFS[t]
	air = def.get("air", false)
	small = def.get("small", false)
	alt = def.get("alt", 0.0)
	max_hp = def["hp"]
	hp = max_hp
	invested = def.get("cost", 0)
	heading = PI / 2.0 if s == "e" else -PI / 2.0
	retarget = randf() * 0.4
	variant = 0 if randf() < 0.65 else 1
	for k in def["weapons"]:
		var w: Dictionary = GameData.WEAP[k]
		weapons.append({"w": w, "cd": randf() * w["rof"], "target": null})


func max_range() -> float:
	var r := 0.0
	for e in weapons:
		r = maxf(r, e["w"]["range"])
	return r


func status() -> String:
	if moving: return "Moving"
	if halt: return "Engaging"
	if dug_in: return "Dug in"
	return "Holding" if side == "p" else "Advancing"
