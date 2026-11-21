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
    jsr fireCheck
    lda phase
    cmp #PH_FLY
    bne playerRun
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
fireCheck:
    lda fireCool
    beq !+
    dec fireCool
    rts
!:  lda joy
    and #JOY_FIRE
    beq !done+
    ldy #0
    lda B_ON
    beq !free+
    iny
    lda B_ON+1
    bne !done+
!free:
    lda #1
    sta B_ON,y
    lda #10
    sta fireCool
    lda phase
    cmp #PH_FLY
    beq !ship+
    lda py
    clc
    adc #9
    sta B_Y,y
    lda px
    clc
    adc #16
    jmp !snd+
!ship:
    lda py
    clc
    adc #8
    sta B_Y,y
    lda px
    clc
    adc #20
!snd:
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
    beq !fly+

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
    lda #60
    sta invuln
    lda #0
    sta onGround
    sta vyLo
    sta vyHi
    jsr setGenFly
    jsr setFlyColors
    lda #CAVE_CR_FLY
    jsr setCaveColors
    lda #$50
    jsr addScore
    lda #$50
    jsr addScore
    lda #SFX_PICKUP
    jmp playSfx
