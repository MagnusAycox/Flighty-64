// ===================================================================
// Monster, skott, kollisioner och sprite-uppbyggnad
// ===================================================================

// Kollisionsboxar per objekttyp (index = T_xxx), lite krympta
boxL:   .byte 0, BOX_WALK_L+2, BOX_BAT_L+2, BOX_SHIP_L, 0
// boxW/boxH = bredd-1 / höjd-1
boxW:   .byte 0, BOX_WALK_R-BOX_WALK_L-4, BOX_BAT_R-BOX_BAT_L-4, BOX_SHIP_R-BOX_SHIP_L, 0
boxT:   .byte 0, BOX_WALK_T+1, BOX_BAT_T+1, BOX_SHIP_T, 0
boxH:   .byte 0, BOX_WALK_B-BOX_WALK_T-1, BOX_BAT_B-BOX_BAT_T-1, BOX_SHIP_B-BOX_SHIP_T, 0
monColor:  .byte 0, COL_LIGHT_GREEN, COL_PURPLE, COL_LIGHT_GREY, COL_YELLOW
monPoints: .byte 0, $20, $40, 0, 0

// -------------------------------------------------------------------
// Skotten
// -------------------------------------------------------------------
bulletsUpdate:
    ldx #NUM_BUL-1
!loop:
    lda B_ON,x
    beq !next+
    lda B_XLO,x
    clc
    adc #BUL_SPEED
    sta B_XLO,x
    lda B_XHI,x
    adc #0
    sta B_XHI,x
    beq !inside+
    lda B_XLO,x
    cmp #<344
    bcs !off+
!inside:
    lda B_XLO,x             // träffar skottet berget?
    clc
    adc #6
    sta cxLo
    lda B_XHI,x
    adc #0
    sta cxHi
    jsr colAt
    lda B_Y,x
    cmp RING_CEILY,y
    bcc !off+
    clc
    adc #2
    cmp RING_FLOORY,y
    bcc !next+
!off:
    lda #0
    sta B_ON,x
!next:
    dex
    bpl !loop-
    rts

// -------------------------------------------------------------------
// Monstren
// -------------------------------------------------------------------
monstersUpdate:
    ldx #NUM_MON-1
!loop:
    lda M_TYPE,x
    beq !next+
    jsr updateMonster
!next:
    dex
    bpl !loop-
    rts

updateMonster:
    cmp #T_BOOM
    bne !move+
    dec M_TIMER,x
    bne !move+
    lda #T_NONE
    sta M_TYPE,x
    rts
!move:
    lda scrollSpeed
    clc
    adc M_SPEED,x
    sta tmp0
    lda M_XLO,x
    sec
    sbc tmp0
    sta M_XLO,x
    lda M_XHI,x
    sbc #0
    sta M_XHI,x
    bmi !remove+
    bne !inside+
    lda M_XLO,x
    cmp #4
    bcc !remove+
!inside:
    lda M_TYPE,x
    cmp #T_WALKER
    bne !+
    jmp walkerMove
!:  cmp #T_FLYER
    bne !+
    jmp flyerMove
!:  cmp #T_SHIP
    bne !+
    jmp shipMove
!:  rts
!remove:
    lda M_TYPE,x
    cmp #T_SHIP
    bne !+
    lda #0
    sta shipExists          // skeppet missades, ett nytt kommer
!:  lda #T_NONE
    sta M_TYPE,x
    rts

// Y = ringkolumn under monstrets mitt
monsterCol:
    lda M_XLO,x
    clc
    adc #12
    sta cxLo
    lda M_XHI,x
    adc #0
    sta cxHi
    jmp colAt

// Gående monster följer marken och ramlar ned i gropar
walkerMove:
    jsr monsterCol
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !fall+
    sec
    sbc #BOX_WALK_B+1
    cmp M_Y,x
    bcc !set+               // marken högre: kliv upp
    sta tmp0
    lda M_Y,x               // marken lägre: ramla
    clc
    adc #3
    cmp tmp0
    bcc !set+
    lda tmp0
!set:
    sta M_Y,x
    rts
!fall:
    lda M_Y,x
    clc
    adc #3
    sta M_Y,x
    cmp #PLAY_Y1
    bcc !done+
    lda #T_NONE
    sta M_TYPE,x
!done:
    rts

// Flygande monster: sinusvåg, håller sig inne i grottan
flyerMove:
    inc M_PHASE,x
    lda M_PHASE,x
    and #63
    tay
    lda sineTab,y
    clc
    adc M_BASEY,x
    sta M_Y,x
    jsr monsterCol
    lda RING_CEILY,y
    clc
    adc #1
    cmp M_Y,x
    bcc !+
    sta M_Y,x
    inc M_BASEY,x
!:  lda RING_FLOORY,y
    sec
    sbc #BOX_BAT_B+2
    cmp M_Y,x
    bcs !+
    sta M_Y,x
    dec M_BASEY,x
!:  rts

// Rymdskeppet står på marken
shipMove:
    jsr monsterCol
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !+
    sec
    sbc #BOX_SHIP_B+1
    sta M_Y,x
!:  rts

// -------------------------------------------------------------------
// Nya monster från höger
// -------------------------------------------------------------------
spawnUpdate:
    lda phase
    cmp #PH_LANDING
    bne !normal+
    lda landDelay
    bne !rts+
    lda shipExists
    bne !rts+
    jsr findSlot
    bcc !rts+
    lda #T_SHIP
    sta M_TYPE,x
    lda #1
    sta shipExists
    lda #0
    sta M_SPEED,x
    jsr placeRight
    lda #PLAY_Y1-BOX_SHIP_B-1-24
    sta M_Y,x
    jmp shipMove
!rts:
    rts

!normal:
    dec spawnTimer
    bne !rts-
    // tid till nästa: 90 - 5*svårighet + slump(0-31)
    lda difficulty
    asl
    asl
    clc
    adc difficulty
    sta tmp0
    lda #90
    sec
    sbc tmp0
    sta tmp0
    jsr rnd
    and #31
    clc
    adc tmp0
    sta spawnTimer

    jsr findSlot
    bcc !rts-
    jsr placeRight
    lda #1
    sta M_SPEED,x
    lda phase
    cmp #PH_FLY
    bne !walker+
    jsr rnd
    and #1
    clc
    adc #1
    sta M_SPEED,x
    jsr rnd
    bmi !walker+

    // flygande monster
    lda #T_FLYER
    sta M_TYPE,x
    jsr rnd
    sta M_PHASE,x
    ldy tmp4                // ringkolumn 40 (från placeRight)
    lda RING_CEILY,y
    clc
    adc RING_FLOORY,y
    ror
    sec
    sbc #24
    sta tmp0
    jsr rnd
    and #15
    clc
    adc tmp0
    sta M_BASEY,x
    jmp flyerMove

!walker:
    lda #T_WALKER
    sta M_TYPE,x
    lda #PLAY_Y0
    sta M_Y,x
    ldy tmp4
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !+
    sec
    sbc #BOX_WALK_B+1
    sta M_Y,x
!:  rts

// findSlot: C=1 och X = ledig slot, annars C=0
findSlot:
    ldx #NUM_MON-1
!loop:
    lda M_TYPE,x
    beq !found+
    dex
    bpl !loop-
    clc
    rts
!found:
    sec
    rts

// placeRight: x = 344 (precis utanför högerkanten), tmp4 = ringkolumn 40
placeRight:
    lda #<344
    sta M_XLO,x
    lda #>344
    sta M_XHI,x
    lda #0
    sta M_TIMER,x
    lda ringBase
    clc
    adc #40
    and #63
    sta tmp4
    rts

// -------------------------------------------------------------------
// Kollisioner
// -------------------------------------------------------------------
collisions:
    // ---- skott mot monster
    lda #NUM_BUL-1
    sta tmp5
!bloop:
    ldy tmp5
    lda B_ON,y
    beq !bnext+
    ldx #NUM_MON-1
!mloop:
    lda M_TYPE,x
    cmp #T_WALKER
    beq !test+
    cmp #T_FLYER
    bne !mnext+
!test:
    jsr monsterBoxA
    ldy tmp5
    lda B_XLO,y             // skottets högra kant
    clc
    adc #BOX_BULLET_R
    sta ovR
    lda B_XHI,y
    adc #0
    sta ovR+1
    lda B_Y,y
    clc
    adc #BOX_BULLET_B
    sta ovRY
    lda ovW
    clc
    adc #BOX_BULLET_R-BOX_BULLET_L
    sta ovW
    lda ovWY
    clc
    adc #BOX_BULLET_B-BOX_BULLET_T
    sta ovWY
    jsr overlap
    bcc !mnext+
    // träff!
    ldy tmp5
    lda #0
    sta B_ON,y
    jsr killMonster
    jmp !bnext+
!mnext:
    dex
    bpl !mloop-
!bnext:
    dec tmp5
    bpl !bloop-

    // ---- spelaren mot monster och skeppet
    lda pState
    bne !done+
    ldx #NUM_MON-1
!ploop:
    lda M_TYPE,x
    beq !pnext+
    cmp #T_BOOM
    beq !pnext+
    cmp #T_SHIP
    beq !ptest+
    lda invuln
    bne !pnext+
!ptest:
    jsr monsterBoxA
    jsr playerBoxB
    jsr overlap
    bcc !pnext+
    lda M_TYPE,x
    cmp #T_SHIP
    bne !hit+
    jmp boardShip
!hit:
    jsr killMonster
    jmp killPlayer
!pnext:
    dex
    bpl !ploop-
!done:
    rts

// Monster X blir en explosion
killMonster:
    ldy M_TYPE,x
    lda monPoints,y
    jsr addScore
    lda #T_BOOM
    sta M_TYPE,x
    lda #24
    sta M_TIMER,x
    lda #0
    sta M_SPEED,x
    lda #SFX_KILL
    jmp playSfx

// Box A = monster X (vänsterkant, bredd, överkant, höjd)
monsterBoxA:
    ldy M_TYPE,x
    lda M_XLO,x
    clc
    adc boxL,y
    sta ovL
    lda M_XHI,x
    adc #0
    sta ovL+1
    lda M_Y,x
    clc
    adc boxT,y
    sta ovLY
    lda boxW,y
    sta ovW
    lda boxH,y
    sta ovWY
    rts

// Box B = spelaren (högerkant, underkant), lägger till bredd/höjd
playerBoxB:
    lda phase
    cmp #PH_FLY
    beq !ship+
    lda px
    clc
    adc #P_RIGHT
    sta ovR
    lda #0
    sta ovR+1
    lda py
    clc
    adc #P_H-1
    sta ovRY
    lda ovW
    clc
    adc #P_RIGHT-P_LEFT
    sta ovW
    lda ovWY
    clc
    adc #P_H-1-P_TOP
    sta ovWY
    rts
!ship:
    lda px
    clc
    adc #S_RIGHT
    sta ovR
    lda #0
    adc #0
    sta ovR+1
    lda py
    clc
    adc #S_BOT
    sta ovRY
    lda ovW
    clc
    adc #S_RIGHT-S_LEFT
    sta ovW
    lda ovWY
    clc
    adc #S_BOT-S_TOP
    sta ovWY
    rts

// overlap: C=1 om boxarna överlappar.
// t = högerkant(B) - vänsterkant(A); överlapp om 0 <= t <= bredd(A)+bredd(B)-2
// (ovW/ovWY = (bredd(A)-1)+(bredd(B)-1), likadant för höjden)
overlap:
    lda ovR
    sec
    sbc ovL
    sta tmp0
    lda ovR+1
    sbc ovL+1
    bne !no+
    lda tmp0
    cmp ovW
    beq !+
    bcs !no+
!:  lda ovRY
    sec
    sbc ovLY
    bcc !no+
    cmp ovWY
    beq !yes+
    bcs !no+
!yes:
    sec
    rts
!no:
    clc
    rts

// -------------------------------------------------------------------
// Bygg sprite-skuggregistren (skrivs till VIC av applyFrame)
// -------------------------------------------------------------------
buildSprites:
    lda #0
    sta sprEnable
    sta sprMsb

    // ---- sprite 0: spelaren
    lda px
    sta sprX
    lda py
    sta sprY
    lda pState
    beq !alive+
    lda frameCount
    lsr
    lsr
    lsr
    and #1
    clc
    adc #SPR_BOOM0
    sta sprPtr
    lda #COL_YELLOW
    sta sprCol
    jmp !show+
!alive:
    lda phase
    cmp #PH_FLY
    bne !run+
    lda frameCount
    lsr
    lsr
    and #1
    clc
    adc #SPR_SHIP0
    sta sprPtr
    lda #COL_LIGHT_GREY
    sta sprCol
    jmp !blink+
!run:
    lda #COL_CYAN
    sta sprCol
    lda onGround
    bne !+
    lda #SPR_JUMP
    sta sprPtr
    jmp !blink+
!:  lda frameCount
    lsr
    lsr
    and #1
    clc
    adc #SPR_RUN0
    sta sprPtr
!blink:
    lda invuln              // blinka när man är odödlig
    beq !show+
    lda frameCount
    and #4
    bne !nosprite+
!show:
    lda #1
    sta sprEnable
!nosprite:

    // ---- sprite 1-2: skotten
    ldx #0
!loop:
    lda B_ON,x
    beq !next+
    lda B_XLO,x
    sta sprX+1,x
    lda B_Y,x
    sta sprY+1,x
    lda #SPR_BULLET
    sta sprPtr+1,x
    lda #COL_YELLOW
    sta sprCol+1,x
    lda bitTab+1,x
    ora sprEnable
    sta sprEnable
    lda B_XHI,x
    beq !next+
    lda bitTab+1,x
    ora sprMsb
    sta sprMsb
!next:
    inx
    cpx #NUM_BUL
    bne !loop-

    // ---- sprite 3-7: monster
    ldx #0
!loop:
    lda M_TYPE,x
    beq !next+
    tay
    lda monColor,y
    sta sprCol+3,x
    lda M_XLO,x
    sta sprX+3,x
    lda M_Y,x
    sta sprY+3,x
    lda frameCount
    lsr
    lsr
    lsr
    and #1
    sta tmp0
    cpy #T_WALKER
    bne !+
    lda #SPR_WALK0
    bne !anim+
!:  cpy #T_FLYER
    bne !+
    lda #SPR_BAT0
    bne !anim+
!:  cpy #T_SHIP
    bne !+
    lda #SPR_SHIP0
    sta sprPtr+3,x
    jmp !on+
!:  lda M_TIMER,x           // explosion
    lsr
    lsr
    and #1
    sta tmp0
    lda #SPR_BOOM0
!anim:
    clc
    adc tmp0
    sta sprPtr+3,x
!on:
    lda bitTab+3,x
    ora sprEnable
    sta sprEnable
    lda M_XHI,x
    beq !next+
    lda bitTab+3,x
    ora sprMsb
    sta sprMsb
!next:
    inx
    cpx #NUM_MON
    bne !loop-
    rts

bitTab: .byte $01, $02, $04, $08, $10, $20, $40, $80
