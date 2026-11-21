// GENERERAD FIL - ändra tools/make_gfx.py och kör om den.
// Spritepekare, teckenkoder och kollisionsboxar.

.const SPR_RUN0     = 64
.const SPR_RUN1     = 65
.const SPR_JUMP     = 66
.const SPR_RUNL0    = 67
.const SPR_RUNL1    = 68
.const SPR_JUMPL    = 69
.const SPR_SHIP0    = 70
.const SPR_SHIP1    = 71
.const SPR_WALK0    = 72
.const SPR_WALK1    = 73
.const SPR_BAT0     = 74
.const SPR_BAT1     = 75
.const SPR_BULLET   = 76
.const SPR_BOOM0    = 77
.const SPR_BOOM1    = 78
.const SPR_FLOAT0   = 79
.const SPR_FLOAT1   = 80
.const SPR_HOP0     = 81
.const SPR_HOP1     = 82
.const SPR_SEEK0    = 83
.const SPR_SEEK1    = 84
.const SPR_FLAGBAR  = 85

.const CH_ROCK0    = 64
.const CH_ROCK1    = 65
.const CH_ROCK2    = 66
.const CH_ROCK3    = 67
.const CH_CEIL0    = 68
.const CH_CEIL1    = 69
.const CH_FLOOR0   = 70
.const CH_FLOOR1   = 71
.const CH_SPIKE    = 72

.const GFX_CHARS_LEN   = 72
.const GFX_SPRITES_LEN = 1408

// Kollisionsboxar i spritepixlar (inklusive), union av alla ramar
.const BOX_RUN_L = 2
.const BOX_RUN_R = 23
.const BOX_RUN_T = 2
.const BOX_RUN_B = 20
.const BOX_SHIP_L = 0
.const BOX_SHIP_R = 23
.const BOX_SHIP_T = 5
.const BOX_SHIP_B = 13
.const BOX_WALK_L = 2
.const BOX_WALK_R = 23
.const BOX_WALK_T = 9
.const BOX_WALK_B = 20
.const BOX_BAT_L = 0
.const BOX_BAT_R = 23
.const BOX_BAT_T = 0
.const BOX_BAT_B = 8
.const BOX_BULLET_L = 0
.const BOX_BULLET_R = 7
.const BOX_BULLET_T = 0
.const BOX_BULLET_B = 3
.const BOX_FLOAT_L = 2
.const BOX_FLOAT_R = 21
.const BOX_FLOAT_T = 0
.const BOX_FLOAT_B = 11
.const BOX_HOP_L = 0
.const BOX_HOP_R = 23
.const BOX_HOP_T = 10
.const BOX_HOP_B = 20
.const BOX_SEEK_L = 0
.const BOX_SEEK_R = 21
.const BOX_SEEK_T = 6
.const BOX_SEEK_B = 14

