// ===================================================================
// Monster, skott, kollisioner och sprite-uppbyggnad
// ===================================================================

// Tabeller per objekttyp (index = T_xxx):
//   0 -, 1 gående, 2 fladdermus, 3 skepp, 4 explosion,
//   5 svävare, 6 hoppare, 7 sökmina
// Kollisionsboxar (lite krympta). boxW/boxH = bredd-1 / höjd-1
boxL:   .byte 0, BOX_WALK_L+2, BOX_BAT_L+2, BOX_SHIP_L, 0
        .byte BOX_FLOAT_L+2, BOX_HOP_L+2, BOX_SEEK_L+2
boxW:   .byte 0, BOX_WALK_R-BOX_WALK_L-4, BOX_BAT_R-BOX_BAT_L-4, BOX_SHIP_R-BOX_SHIP_L, 0
        .byte BOX_FLOAT_R-BOX_FLOAT_L-4, BOX_HOP_R-BOX_HOP_L-4, BOX_SEEK_R-BOX_SEEK_L-4
boxT:   .byte 0, BOX_WALK_T+1, BOX_BAT_T+1, BOX_SHIP_T, 0
        .byte BOX_FLOAT_T+1, BOX_HOP_T+1, BOX_SEEK_T+1
boxH:   .byte 0, BOX_WALK_B-BOX_WALK_T-1, BOX_BAT_B-BOX_BAT_T-1, BOX_SHIP_B-BOX_SHIP_T, 0
        .byte BOX_FLOAT_B-BOX_FLOAT_T-2, BOX_HOP_B-BOX_HOP_T-1, BOX_SEEK_B-BOX_SEEK_T-2
monColor:   .byte 0, COL_LIGHT_GREEN, COL_PURPLE, COL_LIGHT_GREY, COL_YELLOW
            .byte COL_LIGHT_BLUE, COL_ORANGE, COL_RED
monPoints:  .byte 0, $20, $40, 0, 0, $30, $30, $50
monSprite:  .byte 0, SPR_WALK0, SPR_BAT0, SPR_SHIP0, SPR_BOOM0
            .byte SPR_FLOAT0, SPR_HOP0, SPR_SEEK0
monHostile: .byte 0, 1, 1, 0, 0, 1, 1, 1

// Rörelserutin per typ (adress-1 för rts-hopp)
moveTab:    .word noMove-1, walkerMove-1, flyerMove-1, shipMove-1
            .word noMove-1, floaterMove-1, hopperMove-1, seekerMove-1
// Startrutin per typ
spawnTab:   .word noMove-1, spawnWalker-1, spawnFlyer-1, noMove-1
            .word noMove-1, spawnFloater-1, spawnHopper-1, spawnSeeker-1

// Vilka monster som kommer i varje våg (4 vågor x 4 val per fas)
spawnTypes:
    // springfasen
    .byte T_WALKER,  T_WALKER,  T_WALKER,  T_WALKER     // våg 1: gående
    .byte T_FLOATER, T_FLOATER, T_FLOATER, T_WALKER     // våg 2: svävare
    .byte T_HOPPER,  T_HOPPER,  T_WALKER,  T_FLOATER    // våg 3: hoppare
    .byte T_WALKER,  T_FLOATER, T_HOPPER,  T_HOPPER     // våg 4: blandat
    // flygfasen
    .byte T_FLYER,   T_FLYER,   T_FLYER,   T_FLYER      // våg 1: fladdermöss
    .byte T_FLYER,   T_FLYER,   T_WALKER,  T_WALKER     // våg 2: + gående
    .byte T_SEEKER,  T_SEEKER,  T_FLOATER, T_FLYER      // våg 3: sökminor
    .byte T_SEEKER,  T_FLYER,   T_HOPPER,  T_FLOATER    // våg 4: blandat

// -------------------------------------------------------------------
// Skotten (kan gå åt alla håll: B_DX/B_DY)
// -------------------------------------------------------------------
bulletsUpdate:
    ldx #NUM_BUL-1
!loop:
    lda B_ON,x
    beq !next+
    ldy #0                  // x += dx (med tecken)
    lda B_DX,x
    bpl !+
    dey
!:  clc
    adc B_XLO,x
    sta B_XLO,x
    tya
    adc B_XHI,x
    sta B_XHI,x
    bmi !off+               // utanför vänsterkanten
    bne !hi+
    lda B_XLO,x
    cmp #4
    bcc !off+
    bcs !y+
!hi:
    lda B_XLO,x
    cmp #<344
    bcs !off+               // utanför högerkanten
!y:
    lda B_Y,x               // y += dy
    clc
    adc B_DY,x
    sta B_Y,x
    cmp #PLAY_Y0-4
    bcc !off+
    cmp #PLAY_Y1
    bcs !off+
    lda B_XLO,x             // träffar skottet berget?
    clc
    adc #4
    sta cxLo
    lda B_XHI,x
    adc #0
    sta cxHi
    jsr colAt
    lda B_Y,x
    cmp RING_CEILY,y
    bcc !off+
    clc
    adc #3
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
    lda M_TYPE,x            // hoppa till typens rörelserutin
    asl
    tay
    lda moveTab+1,y
    pha
    lda moveTab,y
    pha
noMove:
    rts
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

// Svävare: håller sig en bit ovanför marken och guppar upp och ned.
// M_BASEY = höjd över marken, M_TIMER = y utan gupp
floaterMove:
    inc M_PHASE,x
    jsr monsterCol
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !bob+               // över en grop: behåll höjden
    sec
    sbc M_BASEY,x
    sec
    sbc #BOX_FLOAT_B+1
    cmp M_TIMER,x
    beq !bob+
    bcs !lower+
    dec M_TIMER,x
    jmp !bob+
!lower:
    inc M_TIMER,x
!bob:
    sty tmp1
    lda M_PHASE,x
    lsr
    and #63
    tay
    lda sineTab,y
    lsr
    lsr                     // 0-10
    clc
    adc M_TIMER,x
    sec
    sbc #5
    sta M_Y,x
    ldy tmp1
    lda RING_CEILY,y        // inte upp i taket
    cmp M_Y,x
    bcc !+
    sta M_Y,x
    inc M_TIMER,x
!:  rts

// Hoppare: studsar fram längs marken. M_VY = hastighet*4, M_TIMER = paus
hopperMove:
    lda M_VY,x
    clc
    adc #1                  // gravitation
    bmi !+
    cmp #20
    bcc !+
    lda #20
!:  sta M_VY,x
    cmp #$80                // y += vy/4 (aritmetiskt skift)
    ror
    cmp #$80
    ror
    clc
    adc M_Y,x
    sta M_Y,x
    jsr monsterCol
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !pit+
    sec
    sbc #BOX_HOP_B+1
    sta tmp0                // y när den står på marken
    lda M_VY,x
    bmi !done+              // på väg upp
    lda M_Y,x
    cmp tmp0
    bcc !done+              // fortfarande i luften
    lda tmp0
    sta M_Y,x
    lda #0
    sta M_VY,x
    dec M_TIMER,x
    bne !done+
    jsr rnd                 // hoppa!
    and #7
    clc
    adc #14
    eor #$ff
    clc
    adc #1
    sta M_VY,x
    jsr rnd
    and #15
    clc
    adc #10
    sta M_TIMER,x
!done:
    rts
!pit:
    lda M_Y,x
    cmp #PLAY_Y1
    bcc !done-
    lda #T_NONE
    sta M_TYPE,x
    rts

// Sökmina: glider långsamt mot skeppets höjd
seekerMove:
    inc M_PHASE,x
    lda M_PHASE,x
    and #1
    bne !clamp+
    lda py
    cmp M_Y,x
    beq !clamp+
    bcc !up+
    inc M_Y,x
    jmp !clamp+
!up:
    dec M_Y,x
!clamp:
    jsr monsterCol
    lda RING_CEILY,y
    clc
    adc #1
    sec
    sbc #BOX_SEEK_T
    cmp M_Y,x
    bcc !+
    sta M_Y,x
!:  lda RING_FLOORY,y
    sec
    sbc #BOX_SEEK_B+1
    cmp M_Y,x
    bcs !+
    sta M_Y,x
!:  rts

// -------------------------------------------------------------------
// Nya monster från höger
// -------------------------------------------------------------------

// maxMon = min(NUM_MON, nivå + våg/2 + 1)
setMaxMon:
    lda wave
    lsr
    sec
    adc level
    cmp #NUM_MON+1
    bcc !+
    lda #NUM_MON
!:  sta maxMon
    rts

// A = antal levande monster (inte explosioner eller skeppet)
countMonsters:
    lda #0
    sta tmp1
    ldy #NUM_MON-1
!loop:
    lda M_TYPE,y
    tax
    lda monHostile,x
    beq !next+
    inc tmp1
!next:
    dey
    bpl !loop-
    lda tmp1
    rts

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
    cmp #PH_DOCK
    beq !rts-
    dec spawnTimer
    bne !rts-
    // tid till nästa: 84 - 8*min(nivå,6) - 6*våg + slump(0-31)
    lda level
    cmp #6
    bcc !+
    lda #6
!:  asl
    asl
    asl
    sta tmp0
    lda wave
    asl
    clc
    adc wave
    asl
    clc
    adc tmp0
    sta tmp0
    lda #84
    sec
    sbc tmp0
    sta tmp0
    jsr rnd
    and #31
    clc
    adc tmp0
    sta spawnTimer

    jsr countMonsters       // redan fullt?
    cmp maxMon
    bcs !rts-
    jsr findSlot
    bcc !rts-
    jsr placeRight

    // välj typ ur vågtabellen
    lda phase
    cmp #PH_FLY
    lda #0
    bcc !+
    lda #16
!:  sta tmp0
    lda wave
    asl
    asl
    clc
    adc tmp0
    sta tmp0
    jsr rnd
    and #3
    clc
    adc tmp0
    tay
    lda spawnTypes,y
    sta M_TYPE,x
    lda #1
    sta M_SPEED,x
    jsr rnd
    sta M_PHASE,x
    lda M_TYPE,x            // typens startrutin
    asl
    tay
    lda spawnTab+1,y
    pha
    lda spawnTab,y
    pha
    rts

spawnWalker:
    lda phase
    cmp #PH_FLY
    bne !+
    jsr rnd
    and #1
    clc
    adc #1
    sta M_SPEED,x
!:  lda #PLAY_Y0
    sta M_Y,x
    ldy tmp4
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !+
    sec
    sbc #BOX_WALK_B+1
    sta M_Y,x
!:  rts

spawnFlyer:
    jsr rnd
    and #1
    clc
    adc #1
    sta M_SPEED,x
    ldy tmp4
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

spawnFloater:
    jsr rnd
    and #1
    sta M_SPEED,x           // 0-1: långsam
    lda phase
    cmp #PH_FLY
    beq !fly+
    jsr rnd                 // springfasen: lågt (skjut rakt fram)
    bmi !high+              // eller högt (skjut uppåt)
    and #3
    clc
    adc #2
    jmp !set+
!high:
    and #15
    clc
    adc #26
    jmp !set+
!fly:
    jsr rnd
    and #63
    clc
    adc #20
!set:
    sta M_BASEY,x
    ldy tmp4
    lda #PLAY_Y0+40
    sta tmp0
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !+
    sec
    sbc M_BASEY,x
    sec
    sbc #BOX_FLOAT_B+1
    sta tmp0
!:  lda tmp0
    sta M_TIMER,x
    sta M_Y,x
    jmp floaterMove

spawnHopper:
    lda #0
    sta M_VY,x
    lda #8
    sta M_TIMER,x
    lda #PLAY_Y0
    sta M_Y,x
    ldy tmp4
    lda RING_FLOORY,y
    cmp #PIT_Y
    beq !+
    sec
    sbc #BOX_HOP_B+1
    sta M_Y,x
!:  rts

spawnSeeker:
    ldy tmp4
    lda RING_CEILY,y
    clc
    adc RING_FLOORY,y
    ror
    sec
    sbc #10
    sta M_Y,x
    jmp seekerMove

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
    sta M_VY,x
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
    ldy M_TYPE,x
    lda monHostile,y
    beq !mnext+
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
    lda phase
    cmp #PH_DOCK
    beq !done+
    ldx #NUM_MON-1
!ploop:
    lda M_TYPE,x
    cmp #T_SHIP
    beq !ptest+
    tay
    lda monHostile,y
    beq !pnext+
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
    bcs !ship+
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
    bcc !run+
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
    lda facing              // spegelvänd gubbe när han tittar åt vänster
    beq !+
    lda #SPR_RUNL0-SPR_RUN0
!:  sta tmp0
    lda onGround
    bne !+
    lda #SPR_JUMP
    clc
    adc tmp0
    sta sprPtr
    jmp !blink+
!:  lda frameCount
    lsr
    lsr
    and #1
    clc
    adc #SPR_RUN0
    adc tmp0
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
    // animationsram 0/1
    lda frameCount
    lsr
    lsr
    lsr
    cpy #T_BOOM
    bne !+
    lda M_TIMER,x
    lsr
    lsr
!:  cpy #T_HOPPER
    bne !+
    lda M_VY,x              // hoppare: ram 1 i luften
    beq !+
    lda #1
!:  and #1
    clc
    adc monSprite,y
    sta sprPtr+3,x
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
