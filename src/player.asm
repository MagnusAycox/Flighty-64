// ===================================================================
// Spelaren: gubben som springer/hoppar och rymdskeppet
// ===================================================================

playerUpdate:
    lda invuln
    beq !+
    dec invuln
!:  lda pState
    beq !alive+

    // ---- spelaren exploderar
    dec deathTimer
    bne !rts+
    dec lives
    beq !over+
    jmp respawn
!over:
    jmp startGameOver
!rts:
    rts

!alive:
    lda joy                 // åt vilket håll tittar gubben?
    and #JOY_RIGHT
    beq !+
    lda #0
    sta facing
!:  lda joy
    and #JOY_LEFT
    beq !+
    lda #1
    sta facing
!:  jsr fireCheck
    lda phase
    cmp #PH_FLY
    bcc playerRun           // PH_RUN / PH_LANDING
    beq !fly+
    jmp playerDock
!fly:
    jmp playerFly

// -------------------------------------------------------------------
// Springfasen
// -------------------------------------------------------------------
playerRun:
    // 1) en vägg som scrollar in knuffar gubben bakåt
    lda px
    clc
    adc #P_RIGHT
    jsr wallCheckAt
    bcc !nopush+
    lda px
    sec
    sbc scrollSpeed
    sta px
!nopush:
    lda px
    cmp #P_MIN_X
    bcs !+
    jmp killPlayer          // krossad mot vänsterkanten
!:
    // 2) joystick höger/vänster
    lda joy
    and #JOY_RIGHT
    beq !noR+
    lda px
    cmp #P_MAX_X
    bcs !noR+
    clc
    adc #2
    sta px
    clc
    adc #P_RIGHT
    jsr wallCheckAt
    bcc !noR+
    dec px
    dec px
!noR:
    lda joy
    and #JOY_LEFT
    beq !noL+
    lda px
    cmp #P_MIN_X+4
    bcc !noL+
    sec
    sbc #2
    sta px
    clc
    adc #P_LEFT
    jsr wallCheckAt
    bcc !noL+
    inc px
    inc px
!noL:
    // 3) hopp (joystick upp)
    lda onGround
    beq !nojump+
    lda joy
    and #JOY_UP
    beq !nojump+
    lda #JUMP_LO
    sta vyLo
    lda #JUMP_HI
    sta vyHi
    lda #0
    sta onGround
    lda #SFX_JUMP
    jsr playSfx
!nojump:
    // släpper man upp tidigt blir hoppet lägre
    lda joy
    and #JOY_UP
    bne !+
    lda vyHi
    bpl !+
    cmp #$fe
    bcs !+
    lda #$fe
    sta vyHi
    lda #0
    sta vyLo
!:
    // 4) gravitation
    lda vyLo
    clc
    adc #GRAVITY
    sta vyLo
    lda vyHi
    adc #0
    sta vyHi
    bmi !+
    cmp #MAX_FALL
    bcc !+
    lda #MAX_FALL
    sta vyHi
    lda #0
    sta vyLo
!:  lda pyLo
    clc
    adc vyLo
    sta pyLo
    lda py
    adc vyHi
    sta py

    // föll ned i en grop?
    cmp #PLAY_Y1-20
    bcc !+
    jmp killPlayer
!:
    // 5) golv och tak
    jsr probeColumns
    lda #0
    sta onGround
    lda vyHi
    bmi !up+
    lda py
    clc
    adc #P_H
    cmp floorTop
    bcc !vdone+             // fötterna ovanför golvet
    sec
    sbc floorTop
    cmp #9
    bcs !vdone+             // långt in i en vägg: inte landning
    lda floorTop
    sec
    sbc #P_H
    sta py
    lda #0
    sta pyLo
    sta vyLo
    sta vyHi
    lda #1
    sta onGround
    rts
!up:
    lda py
    clc
    adc #P_TOP
    cmp ceilBot
    bcs !vdone+
    lda ceilBot             // slog i taket
    sec
    sbc #P_TOP
    sta py
    lda #0
    sta vyHi
    sta vyLo
!vdone:
    rts

// wallCheckAt: A = sprite-x att kontrollera. C=1 om det är vägg där
// (golvet högre än fötterna eller taket lägre än huvudet).
wallCheckAt:
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda py
    clc
    adc #P_H
    sta tmp0
    lda RING_FLOORY,y
    cmp tmp0
    bcc !blocked+
    lda py
    clc
    adc #P_TOP
    cmp RING_CEILY,y
    bcc !blocked+
    clc
    rts
!blocked:
    sec
    rts

// -------------------------------------------------------------------
// Flygfasen
// -------------------------------------------------------------------
playerFly:
    lda joy
    and #JOY_UP
    beq !+
    lda py
    cmp #S_MIN_Y+2
    bcc !+
    dec py
    dec py
!:  lda joy
    and #JOY_DOWN
    beq !+
    lda py
    cmp #S_MAX_Y
    bcs !+
    inc py
    inc py
!:  lda joy
    and #JOY_LEFT
    beq !+
    lda px
    cmp #26
    bcc !+
    dec px
    dec px
!:  lda joy
    and #JOY_RIGHT
    beq !+
    lda px
    cmp #200
    bcs !+
    inc px
    inc px
!:
    lda invuln
    bne !safe+
    lda phase
    cmp #PH_DOCK
    beq !safe+
    lda px
    clc
    adc #S_LEFT
    jsr shipHitsWall
    bcs !crash+
    lda px
    clc
    adc #S_RIGHT
    jsr shipHitsWall
    bcs !crash+
!safe:
    rts
!crash:
    jmp killPlayer

// C=1 om skeppet (på kolumnen vid sprite-x A) nuddar tak eller golv
shipHitsWall:
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda py
    clc
    adc #S_TOP
    cmp RING_CEILY,y
    bcc !hit+
    lda py
    clc
    adc #S_BOT
    cmp RING_FLOORY,y
    bcs !hit+
    clc
    rts
!hit:
    sec
    rts

// -------------------------------------------------------------------
// Skjuta
// -------------------------------------------------------------------
// Skottets riktning beror på vad man gör:
//   springfasen, på marken:  rakt fram eller bakåt (dit gubben tittar)
//   springfasen, i luften:   rakt upp, eller snett upp om man håller
//                            höger/vänster
//   flygfasen:               fram, snett upp (joystick upp) eller
//                            snett ned (joystick ned)
shotDX: .byte 6, 256-6, 0,     4, 256-4, 6,     4, 4
shotDY: .byte 0, 0,     256-6, 256-4, 256-4, 0, 256-4, 4
shotXO: .byte 16, 0,    8,     14, 2,     20,    18, 18
shotYO: .byte 9, 9,     256-4, 0,  0,     8,     4,  11

fireCheck:
    lda fireCool
    beq !+
    dec fireCool
    rts
!:  lda joy
    and #JOY_FIRE
    beq !done+
    lda phase
    cmp #PH_DOCK
    beq !done+
    ldy #0
    lda B_ON
    beq !free+
    iny
    lda B_ON+1
    bne !done+
!free:
    lda phase
    cmp #PH_FLY
    bne !run+
    ldx #SHOT_FLY
    lda joy
    and #JOY_UP
    beq !+
    ldx #SHOT_FLYUP
!:  lda joy
    and #JOY_DOWN
    beq !go+
    ldx #SHOT_FLYDOWN
    bne !go+
!run:
    ldx facing              // SHOT_RIGHT / SHOT_LEFT
    lda onGround
    bne !go+
    ldx #SHOT_UP
    lda joy
    and #JOY_RIGHT
    beq !+
    ldx #SHOT_UPRIGHT
!:  lda joy
    and #JOY_LEFT
    beq !go+
    ldx #SHOT_UPLEFT
!go:
    lda #1
    sta B_ON,y
    lda #10
    sta fireCool
    lda shotDX,x
    sta B_DX,y
    lda shotDY,x
    sta B_DY,y
    lda py
    clc
    adc shotYO,x
    sta B_Y,y
    lda px
    clc
    adc shotXO,x
    sta B_XLO,y
    lda #0
    adc #0
    sta B_XHI,y
    lda #SFX_SHOOT
    jsr playSfx
!done:
    rts

// -------------------------------------------------------------------
// Död och återupplivning
// -------------------------------------------------------------------
killPlayer:
    lda pState
    bne !done+
    lda #1
    sta pState
    lda #64
    sta deathTimer
    lda #SFX_DEATH
    jsr playSfx
!done:
    rts

respawn:
    lda #0
    sta pState
    sta vyLo
    sta vyHi
    sta pyLo
    lda #120
    sta invuln
    lda phase
    cmp #PH_FLY
    bcs !fly+

    // hitta en kolumn med fast mark
    lda #56
    sta px
!try:
    jsr probeColumns
    lda tmp2
    cmp #PIT_Y
    beq !next+
    lda tmp3
    cmp #PIT_Y
    bne !found+
!next:
    lda px
    clc
    adc #8
    sta px
    cmp #168
    bcc !try-
!found:
    lda floorTop
    sec
    sbc #P_H
    sta py
    lda #1
    sta onGround
    rts

!fly:
    lda #48
    sta px
    lda #60
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda RING_CEILY,y
    clc
    adc RING_FLOORY,y
    ror                     // medelvärde av tak och golv
    sec
    sbc #10
    sta py
    rts

// -------------------------------------------------------------------
// Kliv in i rymdskeppet (X = monsterslot med skeppet)
// -------------------------------------------------------------------
boardShip:
    lda #T_NONE
    sta M_TYPE,x
    lda #0
    sta shipExists
    lda M_Y,x
    sta py
    lda M_XLO,x
    cmp #24
    bcs !+
    lda #24
!:  sta px
    lda #PH_FLY
    sta phase
    lda #0
    sta wave
    sta waveCol
    lda #60
    sta invuln
    sta spawnTimer
    lda #0
    sta onGround
    sta vyLo
    sta vyHi
    jsr setGenFly
    jsr setFlyColors
    lda #CAVE_CR_FLY
    jsr setCaveColors
    jsr setMaxMon
    jsr showWaveMsg
    lda #$50
    jsr addScore
    lda #$50
    jsr addScore
    lda #SFX_PICKUP
    jmp playSfx

// -------------------------------------------------------------------
// Landning efter flygfasen. Först flyger man fritt (utan att kunna
// krocka) medan marken planar ut, sedan landar autopiloten skeppet
// och nästa nivå börjar.
// -------------------------------------------------------------------
.const DOCK_X = 60

playerDock:
    lda landDelay
    beq !auto+
    jmp playerFly
!auto:
    lda px
    cmp #DOCK_X
    beq !y+
    bcc !right+
    dec px
    jmp !y+
!right:
    inc px
!y:
    lda px
    clc
    adc #12
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !wait+
    sec
    sbc #S_BOT+1
    sta tmp0
    lda py
    cmp tmp0
    beq !down+
    bcc !lower+
    dec py
    rts
!lower:
    inc py
!wait:
    rts
!down:
    lda px
    cmp #DOCK_X
    bne !wait-
    // framme: kliv ur skeppet
nextLevel:
    lda level
    cmp #99
    bcs !+
    inc level
!:  lda #PH_RUN
    sta phase
    lda #0
    sta wave
    sta waveCol
    sta facing
    sta vyLo
    sta vyHi
    sta pyLo
    lda #1
    sta onGround
    lda py
    sec
    sbc #P_H-S_BOT-1        // gubben står där skeppet stod
    sta py
    lda #60
    sta invuln
    sta spawnTimer
    jsr setGenRun
    jsr setRunColors
    lda #CAVE_CR_RUN
    jsr setCaveColors
    jsr setMaxMon
    lda #SFX_PICKUP
    jsr playSfx
    jmp showWaveMsg
