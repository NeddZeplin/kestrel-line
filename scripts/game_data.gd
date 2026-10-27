class_name GameData
extends RefCounted
## Units, weapons and waves, ported from the browser prototype. Ranges (m) and speeds (m/s) are
## game-scaled: relative performance is realistic, absolute distances are compressed.

const WEAP := {
	"mg": {"name": "7.62 mm MG", "range": 300.0, "rof": 0.35, "dmg": 5.0, "pen": 3.0, "acc": [0.7, 0.25], "fx": "tracer", "air": 0.3},
	"rpg": {"name": "84 mm rocket", "range": 170.0, "rof": 7.0, "dmg": 55.0, "pen": 45.0, "acc": [0.65, 0.3], "fx": "rocket", "speed": 120.0, "soft": 0.4},
	"atgm": {"name": "ATGM", "range": 650.0, "min": 60.0, "rof": 9.0, "dmg": 140.0, "pen": 110.0, "acc": [0.9, 0.8], "fx": "missile", "speed": 170.0, "soft": 0.3, "air": 0.5},
	"mortar": {"name": "81 mm mortar", "range": 900.0, "min": 120.0, "rof": 6.0, "dmg": 45.0, "pen": 15.0, "splash": 24.0, "disp": 20.0, "fx": "mortar", "indirect": true, "top": true, "threat": 0.5},
	"tankgun": {"name": "120 mm gun", "range": 520.0, "rof": 5.5, "dmg": 110.0, "pen": 90.0, "acc": [0.92, 0.5], "fx": "sabot", "speed": 1100.0, "soft": 0.35},
	"coax": {"name": "Coax MG", "range": 300.0, "rof": 0.35, "dmg": 5.0, "pen": 3.0, "acc": [0.65, 0.25], "fx": "tracer", "air": 0.15},
	"sam": {"name": "SHORAD missile", "range": 600.0, "rof": 3.5, "dmg": 150.0, "pen": 50.0, "acc": [0.88, 0.72], "fx": "sam", "speed": 300.0, "air_only": true},
	"hmg": {"name": "12.7 mm HMG", "range": 340.0, "rof": 0.35, "dmg": 8.0, "pen": 10.0, "acc": [0.6, 0.22], "fx": "tracer", "air": 0.3},
	"autocannon": {"name": "30 mm autocannon", "range": 420.0, "rof": 0.7, "dmg": 16.0, "pen": 28.0, "acc": [0.7, 0.3], "fx": "heavy", "air": 0.3},
	"ifv_atgm": {"name": "Turret ATGM", "range": 500.0, "min": 60.0, "rof": 16.0, "dmg": 120.0, "pen": 85.0, "acc": [0.85, 0.7], "fx": "missile", "speed": 160.0, "soft": 0.3},
	"helo_atgm": {"name": "Air-launched ATGM", "range": 700.0, "rof": 7.0, "dmg": 140.0, "pen": 110.0, "acc": [0.85, 0.75], "fx": "missile", "speed": 190.0, "soft": 0.3},
	"helo_gun": {"name": "30 mm chain gun", "range": 420.0, "rof": 0.5, "dmg": 12.0, "pen": 20.0, "acc": [0.6, 0.3], "fx": "heavy"},
}

## Loitering munition impact: top attack against side armour.
const DRONE_HIT := {"dmg": 100.0, "pen": 70.0, "top": true, "soft": 0.6}

const DEFS := {
	"rifle": {"name": "Rifle squad", "glyph": "inf", "hp": 100.0, "armor": [0.0, 0.0], "speed": 7.0, "move": "foot", "weapons": ["mg", "rpg"], "cost": 60, "small": true, "men": 4, "model": "squad", "role": "MG for infantry, rockets for close armor"},
	"atgm": {"name": "ATGM team", "glyph": "at", "hp": 60.0, "armor": [0.0, 0.0], "speed": 6.5, "move": "foot", "weapons": ["atgm"], "cost": 140, "small": true, "men": 2, "model": "atgm_team", "role": "Long-range tank killer"},
	"mortar": {"name": "Mortar team", "glyph": "mortar", "hp": 60.0, "armor": [0.0, 0.0], "speed": 6.0, "move": "foot", "weapons": ["mortar"], "cost": 150, "small": true, "men": 2, "model": "mortar_team", "role": "Indirect fire on anything spotted"},
	"mbt": {"name": "Main battle tank", "glyph": "armor", "hp": 300.0, "armor": [80.0, 35.0], "speed": 13.0, "move": "track", "weapons": ["tankgun", "coax"], "cost": 320, "model": "tank", "role": "Mobile reserve, strong frontal armor"},
	"shorad": {"name": "SHORAD vehicle", "glyph": "ada", "hp": 140.0, "armor": [20.0, 12.0], "speed": 14.0, "move": "wheel", "weapons": ["sam", "hmg"], "cost": 190, "model": "shorad", "role": "Shoots down drones and helicopters"},
	"einf": {"name": "Infantry squad", "glyph": "inf", "hp": 100.0, "armor": [0.0, 0.0], "speed": 9.0, "move": "foot", "weapons": ["mg", "rpg"], "reward": 18, "leak": 1, "small": true, "men": 4, "model": "squad"},
	"tech": {"name": "Technical", "glyph": "recon", "hp": 70.0, "armor": [6.0, 6.0], "speed": 18.0, "move": "wheel", "weapons": ["hmg"], "reward": 20, "leak": 1, "model": "technical"},
	"ifv": {"name": "IFV", "glyph": "mech", "hp": 180.0, "armor": [30.0, 15.0], "speed": 14.0, "move": "track", "weapons": ["autocannon", "ifv_atgm"], "reward": 50, "leak": 2, "model": "ifv"},
	"embt": {"name": "Main battle tank", "glyph": "armor", "hp": 300.0, "armor": [75.0, 32.0], "speed": 12.5, "move": "track", "weapons": ["tankgun", "coax"], "reward": 90, "leak": 4, "model": "tank"},
	"drone": {"name": "Loitering munition", "glyph": "uav", "hp": 18.0, "armor": [0.0, 0.0], "speed": 34.0, "move": "air", "alt": 35.0, "weapons": [], "reward": 12, "leak": 1, "model": "drone", "air": true},
	"helo": {"name": "Attack helicopter", "glyph": "rotary", "hp": 220.0, "armor": [12.0, 12.0], "speed": 36.0, "move": "air", "alt": 55.0, "weapons": ["helo_atgm", "helo_gun"], "reward": 120, "leak": 3, "model": "helo", "air": true},
}

const PLAYER_KEYS := ["rifle", "atgm", "mortar", "mbt", "shorad"]
const VALUE := {"mbt": 3.0, "embt": 3.0, "helo": 3.0, "ifv": 2.2, "shorad": 2.0, "atgm": 2.0, "tech": 1.5, "mortar": 1.5, "drone": 1.3, "rifle": 1.0, "einf": 1.0}

## How strongly each movement class avoids anti-tank and anti-personnel fire when routing.
const MOVE_W := {"foot": {"at": 0.6, "ap": 3.0}, "track": {"at": 6.0, "ap": 0.3}, "wheel": {"at": 4.5, "ap": 2.5}}

const START_SUPPLY := 900
const HQ_INTEGRITY := 20
const DEPLOY_R := 520.0

## Hollow Valley waves: [type, count] groups, each group 12 s after the last, units 3.5 s apart.
const WAVES := [
	[["einf", 3]],
	[["einf", 3], ["tech", 2]],
	[["einf", 4], ["ifv", 2]],
	[["tech", 3], ["ifv", 2], ["drone", 3]],
	[["embt", 2], ["einf", 4], ["ifv", 2]],
	[["drone", 5], ["ifv", 3], ["helo", 1]],
	[["embt", 3], ["ifv", 3], ["einf", 5]],
	[["embt", 4], ["ifv", 4], ["einf", 6], ["drone", 6], ["helo", 2]],
]
