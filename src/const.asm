// ===================================================================
// Flighty 64 - konstanter, minneslayout och variabler
// ===================================================================
//
// Minneskarta (VIC-bank 0, $0000-$3fff):
//   $0400-$07ff  Skärm A (dubbelbuffring)
//   $0801-$1fff  BASIC-start + programkod
//   $2000-$27ff  Teckenset (tecken 0-63 kopieras från ROM, 64+ egna)
//   $2800-$2bff  Skärm B (dubbelbuffring)
//   $3000-$33ff  Sprites + tabeller
//   $c000-$c1ff  Variabler/tabeller som inte behöver laddas
//
// BASIC- och KERNAL-ROM slås av ($01 = $35), så hela zero page är vår.
// ===================================================================

.const SCREEN_A   = $0400
.const SCREEN_B   = $2800
.const CHARSET    = $2000
.const COLORRAM   = $d800
.const SCREEN_B_OFS_HI = $24      // >(SCREEN_B - SCREEN_A)
.const COLOR_OFS_HI    = $d4      // >(COLORRAM - SCREEN_A)

.const D018_A     = $18           // skärm $0400, tecken $2000
.const D018_B     = $a8           // skärm $2800, tecken $2000
.const D016_MENU  = $08           // 40 kolumner, multicolor av (text i alla färger)
.const D016_HUD   = $00           // 38 kolumner, multicolor av, ingen scroll
.const D016_GAME  = $10           // 38 kolumner, multicolor på (+ finscroll)

// Spelfält
.const PLAY_TOP   = 2             // första teckenraden i grottan
.const PLAY_ROWS  = 23            // antal rader i grottan (rad 2-24)
.const PLAY_Y0    = 66            // sprite-y för grottans överkant (50+8*2)
.const PLAY_Y1    = 250           // sprite-y för grottans underkant
.const PIT_Y      = $ff           // "golv" i en grop

// Raster-IRQ
.const IRQ_LINE_BOTTOM = 251
.const IRQ_LINE_TOP    = 63

// Spel-tillstånd
.const ST_MENU     = 0
.const ST_PLAY     = 1
.const ST_GAMEOVER = 2

// Faser
.const PH_RUN      = 0            // gubben springer
.const PH_LANDING  = 1            // rymdskeppet väntar på marken
.const PH_FLY      = 2            // vi flyger rymdskeppet

.const RUN_LEN     = 384          // antal kolumner innan rymdskeppet dyker upp

// Joystick-bitar (efter eor #$ff)
.const JOY_UP    = $01
.const JOY_DOWN  = $02
.const JOY_LEFT  = $04
.const JOY_RIGHT = $08
.const JOY_FIRE  = $10

// Färger
.const COL_BLACK      = 0
.const COL_WHITE      = 1
.const COL_RED        = 2
.const COL_CYAN       = 3
.const COL_PURPLE     = 4
.const COL_GREEN      = 5
.const COL_BLUE       = 6
.const COL_YELLOW     = 7
.const COL_ORANGE     = 8
.const COL_BROWN      = 9
.const COL_LIGHT_RED  = 10
.const COL_DARK_GREY  = 11
.const COL_GREY       = 12
.const COL_LIGHT_GREEN= 13
.const COL_LIGHT_BLUE = 14
.const COL_LIGHT_GREY = 15

.const CAVE_CR_RUN = 8 + COL_GREEN    // färg-RAM i grottan (multicolor-bit + färg)
.const CAVE_CR_FLY = 8 + COL_CYAN

// Spelare
.const P_LEFT     = 6             // kroppens box relativt spritens x/y
.const P_RIGHT    = 17
.const P_TOP      = 2
.const P_H        = 21            // fötterna ligger på y+21
.const P_MIN_X    = 18            // tryckt längre åt vänster = krossad
.const P_MAX_X    = 190
.const GRAVITY    = $38           // 8.8 fixtal, ca 0.22 px/frame^2
.const JUMP_HI    = $fb           // hopphastighet -4.25 px/frame
.const JUMP_LO    = $c0
.const MAX_FALL   = 5

// Skeppet
.const S_LEFT     = BOX_SHIP_L + 2
.const S_RIGHT    = BOX_SHIP_R - 1
.const S_TOP      = BOX_SHIP_T + 1
.const S_BOT      = BOX_SHIP_B
.const S_MIN_Y    = PLAY_Y0 - 4
.const S_MAX_Y    = PLAY_Y1 - 16

// Objekt
.const NUM_MON    = 5             // monster-slottar (sprite 3-7)
.const NUM_BUL    = 2             // skott (sprite 1-2)
.const BUL_SPEED  = 7

.const T_NONE     = 0
.const T_WALKER   = 1
.const T_FLYER    = 2
.const T_SHIP     = 3
.const T_BOOM     = 4

// Ljudeffekter
.const SFX_SHOOT  = 0
.const SFX_JUMP   = 1
.const SFX_KILL   = 2
.const SFX_DEATH  = 3
.const SFX_PICKUP = 4
.const SFX_BLIP   = 5

// -------------------------------------------------------------------
// Zero page
// -------------------------------------------------------------------
.const textPtr     = $02          // 2 byte
.const scrPtr      = $04          // 2 byte
.const scrPtrB     = $06          // 2 byte
.const colPtr2     = $08          // 2 byte
.const colPtr      = $0a          // 2 byte
.const tmp0        = $0c
.const tmp1        = $0d
.const tmp2        = $0e
.const tmp3        = $0f
.const frameFlag   = $10
.const irqStage    = $11
.const gameState   = $12
.const phase       = $13
.const fine        = $14
.const scrollSpeed = $15
.const ringBase    = $16
.const needCopy    = $17
.const dispBuf     = $18
.const nextD016    = $19
.const nextD018    = $1a
.const hudD016     = $1b
.const joy         = $1c
.const joyPrev     = $1d
.const joyNew      = $1e
.const rngLo       = $1f
.const rngHi       = $20
.const px          = $21
.const py          = $22
.const pyLo        = $23
.const vyLo        = $24
.const vyHi        = $25
.const onGround    = $26
.const pState      = $27
.const deathTimer  = $28
.const invuln      = $29
.const lives       = $2a
.const score       = $2b          // 3 byte BCD, mest signifikant först
.const distLo      = $2e
.const distHi      = $2f
.const pendingSwap = $30
.const pendingD018 = $31
.const pendingD016 = $32
.const newColIdx   = $33
.const genPtr      = $34
.const gCeil       = $35
.const gFloor      = $36
.const gSeg        = $37
.const gPit        = $38
.const gPitCool    = $39
.const spawnTimer  = $3a
.const difficulty  = $3b
.const landDelay   = $3c
.const shipExists  = $3d
.const frameCount  = $3e
.const cxLo        = $3f
.const cxHi        = $40
.const floorTop    = $41
.const ceilBot     = $42
.const dcCeil      = $43
.const dcFloor     = $44
.const dcSeed      = $45
.const dcFtop      = $46
.const ovL         = $47          // 2 byte
.const ovR         = $49          // 2 byte
.const ovW         = $4b
.const ovLY        = $4c
.const ovRY        = $4d
.const ovWY        = $4e
.const goTimer     = $4f
.const hsPos       = $50
.const hsLast      = $51
.const nameCursor  = $52
.const nameBuf     = $53          // 3 byte (index i bokstavstabellen)
.const repeatTimer = $56
.const printColor  = $57
.const menuTimer   = $58
.const clearColor  = $59
.const tmp4        = $5a
.const tmp5        = $5b
.const fireCool    = $5c
.const sprEnable   = $5d
.const sprMsb      = $5e
.const rndCnt      = $5f
.const genFMin     = $60
.const genFMax     = $61
.const genCMin     = $62
.const genCMax     = $63
.const genGap      = $64          // max ceil+floor (=PLAY_ROWS - minsta öppning)
.const gCeilT      = $65          // flygfasen: mål för taket
.const gFloorT     = $66          // flygfasen: mål för golvet
.const sprX        = $68          // 8 byte
.const sprY        = $70          // 8 byte
.const sprPtr      = $78          // 8 byte
.const sprCol      = $80          // 8 byte

// -------------------------------------------------------------------
// Tabeller i RAM (initieras av koden)
// -------------------------------------------------------------------
.const RING_CEIL   = $c000        // 64 kolumner: antal takrader
.const RING_FLOOR  = $c040        // 64 kolumner: antal golvrader (0 = grop)
.const RING_CEILY  = $c080        // takets underkant i sprite-y
.const RING_FLOORY = $c0c0        // golvets överkant i sprite-y ($ff = grop)

.const M_TYPE      = $c100
.const M_XLO       = $c108
.const M_XHI       = $c110
.const M_Y         = $c118
.const M_SPEED     = $c120
.const M_BASEY     = $c128
.const M_PHASE     = $c130
.const M_TIMER     = $c138

.const B_ON        = $c140
.const B_XLO       = $c142
.const B_XHI       = $c144
.const B_Y         = $c146

.const SFX_TIMER   = $c150
.const SFX_FREQ    = $c153
.const SFX_DELTA   = $c156
.const SFX_WAVE    = $c159
