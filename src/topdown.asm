// ===================================================================
// Nivå 3: banan ovanifrån
//
//  * Banan byggs av block (2x2 tecken) rad för rad och ligger i en
//    ringbuffert med 64 teckenrader (MAP_RING). Skärmrad 2 visar
//    världsrad tdWrow, rad 3 visar tdWrow-1 osv.
//  * Banan scrollar nedåt när spelaren går uppåt i övre delen av
//    skärmen (TD_SCROLL_Y). Finscroll med $d011 (0-7), grovscroll med
//    dubbelbuffring precis som grottan, fast med rader i stället för
//    kolumner.
//  * HUD-raden står still: rasteravbrottet sätter spelplanens $d011
//    först på linje 63 (64 när finscrollen är 7, så att yscroll aldrig
//    matchar linjen den skrivs på). Spelplanen visas i 24-radsläge så
//    att den halva rad som scrollar in längst ned döljs av ramen.
//  * Nivån börjar med ett fallskärmshopp: fallskärmen är fyra vita
//    hires-sprites och gubben i selen tre hires-sprites (en färg var)
//    på samma koordinater.
// ===================================================================

// Världsrad -> adress i ringbufferten
ringLo:
.for (var i=0; i<64; i++) {
    .byte <(MAP_RING + i*40)
}
ringHi:
.for (var i=0; i<64; i++) {
    .byte >(MAP_RING + i*40)
}

// Spelarens skott: upp, vänster, höger, snett upp-vänster, snett upp-höger
.const TDSHOT_UP = 0
.const TDSHOT_L  = 1
.const TDSHOT_R  = 2
.const TDSHOT_UL = 3
.const TDSHOT_UR = 4
tdShotDX: .byte 0,     256-6, 6, 256-4, 4
tdShotDY: .byte 256-6, 0,     0, 256-4, 256-4
tdShotXO: .byte 8,     0,     16, 2,    14
tdShotYO: .byte 256-6, 8,     8, 256-2, 256-2

// Spelarens kropp (för krockar med träd och sandsäckar)
.const TD_FOOT_L = 6
.const TD_FOOT_R = 17
.const TD_FOOT_T = 4
.const TD_FOOT_B = 16

// -------------------------------------------------------------------
// Rasteravbrottet (anropas från irqTop på linje 61): spelplanens $d011
// -------------------------------------------------------------------
tdRasterTop:
    ldx #63
    lda nextD011
    and #7
    cmp #7
    bne !+
    inx                     // yscroll 7 matchar linje 63: vänta en linje
!:  lda #COL_GREEN          // spelplanens bakgrund (gräs)
!wait:
    cpx $d012
    bne !wait-
    sta $d021               // i vänsterkanten, innan bilden ritas
    lda nextD011
    sta $d011
    rts

// -------------------------------------------------------------------
// Starta nivå 3 (anropas från startLevel eller från flygfasens slut)
// -------------------------------------------------------------------
tdStart:
    lda #$10                // spelplanens $d011 direkt (24 rader, yscroll 0)
    sta pendingD011
    sta nextD011
    lda #0
    sta $d015
    sta sprEnable
    sta B_ON
    sta B_ON+1
    sta wave
    sta tdRows
    sta tdFine
    sta dispBuf
    sta needCopy
    sta pendingSwap
    sta tdHalf
    sta tdGren
    sta tdGenRow
    sta pState
    sta fireCool
    sta pxHi
    sta sprXexp
    sta sprYexp
    sta sprPrio
    sta hudMsgTimer
    ldx #NUM_MON-1
!loop:
    sta M_TYPE,x
    dex
    bpl !loop-
    lda #1
    sta tdOn
    lda #IRQ_LINE_TD
    sta irqTopLine
    lda #COL_LIGHT_GREEN
    sta $d022
    lda #COL_BROWN
    sta $d023

    lda #TD_CR
    jsr clearGameScreens
    jsr tdObjectsInit
    lda #22                 // skärm A visar världsrad 22 överst
    sta bufTop

    // generatorn: öppen mark där fallskärmen landar
    lda #10
    sta tdPath
    lda #TD_INTRO_MT
    sta tdIntroRows
    jsr tdSetDensity
    ldx #24                 // världsrad 0-23
!gen:
    jsr tdGenRowNext
    dex
    bne !gen-
    lda #22
    sta tdWrow

    // skärm A: rad 2-24 visar världsrad 22..0
    lda #2
    sta tmp4
!draw:
    ldx tmp4
    lda rowLo,x
    sta scrPtr
    lda rowHi,x
    sta scrPtr+1
    lda #24
    sec
    sbc tmp4
    jsr tdCopyRingRow
    inc tmp4
    lda tmp4
    cmp #25
    bne !draw-

    // skärm B = skärm A en rad nedåt + världsrad 23 överst
    lda #23
    sta tdNewRow
    lda #2
    sta needCopy
    jsr tdCopyFinish

    lda #D018_A
    sta pendingD018
    lda #TD_D016
    sta pendingD016
    lda #$10                // 24 rader, yscroll 0
    sta pendingD011
    sta nextD011
    lda #D016_MENU          // HUD i 40 kolumner som spelplanen (samma ram)
    sta hudD016

    // fallskärmshoppet
    lda #TDS_INTRO
    sta tdState
    lda #160
    sta px
    lda #104
    sta py
    lda #120
    sta invuln
    jsr drawHud
    jsr showDropMsg
    jmp tdBuildSprites

// Hindrens täthet ökar för varje våg
tdSetDensity:
    lda wave
    asl
    asl
    sta tmp0
    asl
    clc
    adc tmp0                // 12 * våg
    clc
    adc #40
    sta tdDens
    rts

// -------------------------------------------------------------------
// En bildruta på nivå 3 (hoppas hit från gameLoop efter applyFrame)
// -------------------------------------------------------------------
tdFrame:
    jsr tdCopyStep
    jsr soundUpdate
    jsr readJoy
    lda gameState
    cmp #ST_GAMEOVER
    bne !+
    jmp gameOverTick
!:  jsr tdUpdate
    jsr tdBuildSprites
    jsr hudUpdate
    jmp gameLoop

tdUpdate:
    lda invuln
    beq !+
    dec invuln
!:  lda tdState
    cmp #TDS_INTRO
    bne !+
    jmp tdIntro
!:  cmp #TDS_LAND
    bne !+
    jmp tdLand
!:  cmp #TDS_CLEAR
    beq !clear+
    lda pState              // spelar (eller vid porten)
    beq !alive+
    jsr tdDying
    jmp !objects+
!alive:
    jsr tdPlayer
    jsr tdCrateCheck
    lda invuln
    bne !+
    jsr tdOnWire            // taggtråd!
    bcc !+
    jsr tdKillPlayer
!:  jsr tdThrowCheck
    jsr tdFire
!objects:
    jsr tdBullets
    jmp tdObjectsUpdate
!clear:
    jsr tdBullets
    jsr tdObjectsUpdate
    dec tdTimer
    bne !rts+
    lda level               // vidare till nästa nivå
    cmp #99
    bcs !+
    inc level
!:  jmp beginCave
!rts:
    rts

// -------------------------------------------------------------------
// Fallskärmshoppet: gubben sjunker, kan styra lite i sidled
// -------------------------------------------------------------------
tdIntro:
    lda joy
    and #JOY_LEFT
    beq !+
    lda px
    cmp #48
    bcc !+
    dec px
!:  lda joy
    and #JOY_RIGHT
    beq !+
    lda px
    cmp #248
    bcs !+
    inc px
!:  lda frameCount         // sjunker en pixel varannan bildruta
    and #1
    bne !rts+
    inc py
    lda py
    cmp #TD_LAND_Y
    bcc !rts+
    lda #TDS_LAND           // landat
    sta tdState
    lda #24
    sta tdTimer
    lda #SFX_JUMP
    jsr playSfx
!rts:
    rts

// Fallskärmen faller ihop, sedan börjar våg 1
tdLand:
    dec tdTimer
    bne !rts+
    lda #TDS_PLAY
    sta tdState
    jmp showWaveMsg
!rts:
    rts

// -------------------------------------------------------------------
// Spelaren: åtta riktningar, krockar med hinder, scrollar banan
// -------------------------------------------------------------------
tdPlayer:
    lda joy
    and #JOY_LEFT
    beq !noL+
    lda pxHi
    bne !+
    lda px
    cmp #TD_MIN_X+1
    bcc !noL+
!:  jsr tdDecX
    jsr tdBlocked
    bcc !noL+
    jsr tdIncX
!noL:
    lda joy
    and #JOY_RIGHT
    beq !noR+
    lda pxHi
    beq !+
    lda px
    cmp #<TD_MAX_X
    bcs !noR+
!:  jsr tdIncX
    jsr tdBlocked
    bcc !noR+
    jsr tdDecX
!noR:
    lda joy
    and #JOY_UP
    beq !noU+
    dec py                  // prova att gå uppåt
    jsr tdBlocked
    bcs !undoU+
    lda py
    cmp #TD_SCROLL_Y
    bcs !noU+
    inc py                  // högt upp: banan scrollar i stället
    jsr tdCanScroll
    bcs !noU+               // (muren är framme)
    jsr tdScroll
    jmp !noU+
!undoU:
    inc py
!noU:
    lda joy
    and #JOY_DOWN
    beq !noD+
    lda joy                 // fire + ned = granat, gubben står kvar
    and #JOY_FIRE
    bne !noD+
    lda py
    cmp #TD_MAX_Y
    bcs !noD+
    inc py
    jsr tdBlocked
    bcc !noD+
    dec py
!noD:
    rts

tdIncX:
    inc px
    bne !+
    inc pxHi
!:  rts

tdDecX:
    lda px
    bne !+
    dec pxHi
!:  dec px
    rts

// tdBlocked: C=1 om någon av fötternas hörn står på ett hinder
tdBlocked:
    lda #TD_FOOT_L
    ldy #TD_FOOT_T
    jsr tdSolidAt
    bcs !yes+
    lda #TD_FOOT_R
    ldy #TD_FOOT_T
    jsr tdSolidAt
    bcs !yes+
    lda #TD_FOOT_L
    ldy #TD_FOOT_B
    jsr tdSolidAt
    bcs !yes+
    lda #TD_FOOT_R
    ldy #TD_FOOT_B
    jsr tdSolidAt
!yes:
    rts

// tdSolidAt: A = x-offset, Y = y-offset från spelarens sprite. C=1 om hinder.
tdSolidAt:
    clc
    adc px
    sta cxLo
    lda pxHi
    adc #0
    sta cxHi
    tya
    clc
    adc py
    jsr tdCharAt
    cmp #TD_SOLID_FIRST
    rts

// -------------------------------------------------------------------
// tdCharAt: tecknet i banan under sprite-koordinaten (cxLo/cxHi, A=y)
// -------------------------------------------------------------------
tdCharAt:
    clc
    adc #1                  // spriten visas från linjen efter y
    sta tmp0
    lda #TD_TOP_LINE
    clc
    adc tdFine
    sta tmp1                // rasterlinjen där skärmrad 2 börjar
    lda tmp0
    sec
    sbc tmp1
    bcc !above+
    lsr
    lsr
    lsr
    sta tmp1                // rader under rad 2
    lda tdWrow
    sec
    sbc tmp1
    jmp !row+
!above:
    lda tdWrow              // ovanför rad 2: raden som scrollar in
    clc
    adc #1
!row:
    sta tdLastRow
    and #63
    tay
    lda ringLo,y
    sta tdPtr
    lda ringHi,y
    sta tdPtr+1
    lda cxLo                // kolumn = (x - 24) / 8
    sec
    sbc #24
    sta tmp1
    lda cxHi
    sbc #0
    bmi !left+
    lsr
    ror tmp1
    lsr
    ror tmp1
    lsr
    ror tmp1
    lda tmp1
    cmp #40
    bcc !ok+
    lda #39
!ok:
    sta tdLastCol
    tay
    lda (tdPtr),y
    rts
!left:
    ldy #0
    sty tdLastCol
    lda (tdPtr),y
    rts

// -------------------------------------------------------------------
// tdScroll: banan rör sig en pixel nedåt
// -------------------------------------------------------------------
tdScroll:
    jsr tdShiftObjects
    inc tdFine
    lda tdFine
    cmp #8
    bcc !set+
    lda needCopy            // (ska redan vara klar)
    beq !+
    jsr tdCopyFinish
!:  lda #0
    sta tdFine
    inc tdWrow
    lda tdGenRow            // = tdWrow+1: ritas överst i nästa buffert
    sta tdNewRow
    jsr tdGenRowNext
    lda #1
    sta pendingSwap
    lda dispBuf
    bne !toA+
    lda #D018_B
    bne !sw+
!toA:
    lda #D018_A
!sw:
    sta pendingD018
    jsr tdRowPassed
!set:
    lda tdFine
    ora #$10                // DEN, 24 rader
    sta pendingD011
    rts

// En ny rad har scrollat in: poäng och vågor
tdRowPassed:
    lda #$01
    jsr addScore
    inc tdRows
    lda tdRows
    cmp #TD_WAVE_ROWS
    bne !rts+
    lda #0
    sta tdRows
    inc wave
    lda wave
    cmp #NUM_WAVES
    beq !clear+
    jsr tdSetDensity
    jmp showWaveMsg
!clear:
    lda #NUM_WAVES-1        // sista vågen klar: muren med porten byggs
    sta wave
    lda tdGateGen
    bne !rts+
    lda #1
    sta tdGateGen
!rts:
    rts

// -------------------------------------------------------------------
// Generatorn: nästa världsrad (tdGenRow) i ringbufferten.
// Varannan rad börjar en ny blockrad; först skrivs blockens nedre halva
// (den hamnar längre ned på skärmen), sedan den övre. Bevarar X.
// -------------------------------------------------------------------
tdGenRowNext:
    stx tmp5
    lda tdGenRow
    and #63
    tay
    lda ringLo,y
    sta colPtr
    lda ringHi,y
    sta colPtr+1
    lda tdHalf
    bne !top+
    jsr tdNewMetaRow
    ldx #0
    ldy #0
!loop:
    stx tmp3
    lda TD_META,x
    tax
    lda mtBL,x
    sta (colPtr),y
    iny
    lda mtBR,x
    sta (colPtr),y
    iny
    ldx tmp3
    inx
    cpx #20
    bne !loop-
    lda #1
    sta tdHalf
    jmp !done+
!top:
    ldx #0
    ldy #0
!loop:
    stx tmp3
    lda TD_META,x
    tax
    lda mtTL,x
    sta (colPtr),y
    iny
    lda mtTR,x
    sta (colPtr),y
    iny
    ldx tmp3
    inx
    cpx #20
    bne !loop-
    lda #0
    sta tdHalf
!done:
    inc tdGenRow
    ldx tmp5
    rts

// tdNewMetaRow: välj 20 block till TD_META.
// En stig (5 block bred) slingrar sig uppåt och hålls alltid fri.
tdNewMetaRow:
    lda tdIntroRows
    beq !normal+
    dec tdIntroRows
    ldx #19                 // landningsplatsen: gräs, träd bara i kanterna
!loop:
    jsr rnd
    and #1
    sta TD_META,x
    dex
    bpl !loop-
    jsr rnd
    bpl !+
    lda #MT_TREE
    sta TD_META
!:  jsr rnd
    bpl !+
    lda #MT_TREE
    sta TD_META+19
!:  rts

!normal:
    lda tdGateGen           // muren med porten
    beq !+
    jmp tdGateMetaRow
!:  jsr rnd                 // stigen vandrar
    and #3
    beq !left+
    cmp #1
    bne !keep+
    lda tdPath
    cmp #15
    bcs !keep+
    inc tdPath
    jmp !keep+
!left:
    lda tdPath
    cmp #4
    bcc !keep+
    dec tdPath
!keep:
    ldx #19
!col:
    txa                     // på stigen (|x - stig| <= 2): gräs
    sec
    sbc tdPath
    clc
    adc #2
    cmp #5
    bcc !grass+
    jsr rnd
    cmp tdDens
    bcs !grass+
    jsr rnd
    cmp #80
    bcc !sand+
    lda #MT_TREE
    bne !put+
!sand:
    lda #MT_SANDBAG
    bne !put+
!grass:
    jsr rnd
    and #1                  // MT_GRASS0 / MT_GRASS1
!put:
    sta TD_META,x
    dex
    bpl !col-

    lda tdCrateCool         // lådor (från våg 2) och taggtråd (våg 4)
    beq !+
    dec tdCrateCool
!:  lda tdWireCool
    beq !+
    dec tdWireCool
!:  lda wave
    beq !done+
    lda tdCrateCool
    bne !wire+
    jsr rnd
    cmp #20
    bcs !wire+
    jsr rnd
    and #3
    clc
    adc tdPath
    sec
    sbc #1
    tax
    lda #MT_CRATE
    sta TD_META,x
    lda #14
    sta tdCrateCool
!wire:
    lda wave
    cmp #3
    bcc !done+
    lda tdWireCool
    bne !done+
    jsr rnd
    cmp #80
    bcs !done+
    lda #3
    sta tdWireCool
    ldx #19                 // stängsel överallt utom på stigen
!col:
    txa
    sec
    sbc tdPath
    clc
    adc #2
    cmp #5
    bcc !+
    lda #MT_WIRE
    sta TD_META,x
!:  dex
    bpl !col-
    ldx #0                  // sista blocket i varje stängsel: stolpe till höger
!col:
    lda TD_META,x
    cmp #MT_WIRE
    bne !next+
    cpx #19
    beq !end+
    lda TD_META+1,x
    cmp #MT_WIRE
    beq !next+
!end:
    lda #MT_WIRE_END
    sta TD_META,x
!next:
    inx
    cpx #20
    bne !col-
!done:
    rts

// Muren: låda + gräs, sedan murens nedre rad (med porten), övre rad,
// och sedan bara mur
tdGateMetaRow:
    lda tdGateGen
    cmp #4
    bcs !wall+
    ldx #19                 // gräs (första raden med en låda på stigen)
!loop:
    jsr rnd
    and #1
    sta TD_META,x
    dex
    bpl !loop-
    lda tdGateGen
    cmp #1
    bne !+
    ldx tdPath
    lda #MT_CRATE
    sta TD_META,x
!:  inc tdGateGen
    rts
!wall:
    ldx #19
    lda tdGateGen
    cmp #4
    bne !top+
    lda #MT_WALL_B
!loop:
    sta TD_META,x
    dex
    bpl !loop-
    lda #MT_GATE_BL
    sta TD_META+9
    lda #MT_GATE_BR
    sta TD_META+10
    lda tdGenRow            // portens nedersta världsrad
    sta tdGateRow
    inc tdGateGen
    rts
!top:
    lda #MT_WALL
!loop:
    sta TD_META,x
    dex
    bpl !loop-
    lda tdGateGen
    cmp #5
    bne !rts+
    lda #MT_GATE_TL
    sta TD_META+9
    lda #MT_GATE_TR
    sta TD_META+10
    inc tdGateGen
!rts:
    rts

// tdCopyRingRow: A = världsrad, scrPtr = skärmrad (40 tecken)
tdCopyRingRow:
    and #63
    tax
    lda ringLo,x
    sta tdPtr
    lda ringHi,x
    sta tdPtr+1
    ldy #39
!loop:
    lda (tdPtr),y
    sta (scrPtr),y
    dey
    bpl !loop-
    rts

// -------------------------------------------------------------------
// Vertikal grovscroll: den synliga skärmen kopieras en rad nedåt till
// den dolda, i två halvor, och sedan ritas den nya raden överst.
// -------------------------------------------------------------------
.const TD_HALF = 13             // rad 3-13 i första halvan, 14-24 i andra

tdCopyStep:
    lda needCopy
    bne !+
    rts
!:  cmp #2
    bne !second+
    ldx dispBuf             // den dolda bufferten visar en rad längre fram
    lda bufTop,x
    clc
    adc #1
    pha
    txa
    eor #1
    tax
    pla
    sta bufTop,x
    dec needCopy
    lda dispBuf
    bne !fromB+
    jmp tdA2B_top
!fromB:
    jmp tdB2A_top
!second:
    dec needCopy
    lda dispBuf
    bne !fromB+
    jsr tdA2B_bot
    lda #<(SCREEN_B + 2*40)
    sta scrPtr
    lda #>(SCREEN_B + 2*40)
    sta scrPtr+1
    jmp !draw+
!fromB:
    jsr tdB2A_bot
    lda #<(SCREEN_A + 2*40)
    sta scrPtr
    lda #>(SCREEN_A + 2*40)
    sta scrPtr+1
!draw:
    lda tdNewRow
    jmp tdCopyRingRow

tdCopyFinish:
    lda needCopy
    beq !done+
    jsr tdCopyStep
    jmp tdCopyFinish
!done:
    rts

tdA2B_top:
    ldx #39
!loop:
.for (var r=3; r<TD_HALF+1; r++) {
    lda SCREEN_A + (r-1)*40,x
    sta SCREEN_B + r*40,x
}
    dex
    bmi !done+
    jmp !loop-
!done:
    rts

tdA2B_bot:
    ldx #39
!loop:
.for (var r=TD_HALF+1; r<25; r++) {
    lda SCREEN_A + (r-1)*40,x
    sta SCREEN_B + r*40,x
}
    dex
    bmi !done+
    jmp !loop-
!done:
    rts

tdB2A_top:
    ldx #39
!loop:
.for (var r=3; r<TD_HALF+1; r++) {
    lda SCREEN_B + (r-1)*40,x
    sta SCREEN_A + r*40,x
}
    dex
    bmi !done+
    jmp !loop-
!done:
    rts

tdB2A_bot:
    ldx #39
!loop:
.for (var r=TD_HALF+1; r<25; r++) {
    lda SCREEN_B + (r-1)*40,x
    sta SCREEN_A + r*40,x
}
    dex
    bmi !done+
    jmp !loop-
!done:
    rts

// -------------------------------------------------------------------
// Skjuta: upp, vänster, höger, snett upp-vänster/höger
// -------------------------------------------------------------------
tdFire:
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
    ldx #TDSHOT_UP
    lda joy
    and #JOY_LEFT
    beq !+
    ldx #TDSHOT_L
    lda joy
    and #JOY_UP
    beq !go+
    ldx #TDSHOT_UL
    bne !go+
!:  lda joy
    and #JOY_RIGHT
    beq !go+
    ldx #TDSHOT_R
    lda joy
    and #JOY_UP
    beq !go+
    ldx #TDSHOT_UR
!go:
    lda #1
    sta B_ON,y
    lda #9
    sta fireCool
    lda tdShotDX,x
    sta B_DX,y
    lda tdShotDY,x
    sta B_DY,y
    lda py
    clc
    adc tdShotYO,x
    sta B_Y,y
    lda px
    clc
    adc tdShotXO,x
    sta B_XLO,y
    lda pxHi
    adc #0
    sta B_XHI,y
    lda #SFX_SHOOT
    jsr playSfx
!done:
    rts

// Skotten flyger över hindren och försvinner utanför skärmen
tdBullets:
    ldx #NUM_BUL-1
!loop:
    lda B_ON,x
    beq !next+
    ldy #0
    lda B_DX,x
    bpl !+
    dey
!:  clc
    adc B_XLO,x
    sta B_XLO,x
    tya
    adc B_XHI,x
    sta B_XHI,x
    bmi !off+
    bne !hi+
    lda B_XLO,x
    cmp #4
    bcc !off+
    bcs !y+
!hi:
    lda B_XLO,x
    cmp #<344
    bcs !off+
!y:
    lda B_Y,x
    clc
    adc B_DY,x
    sta B_Y,x
    cmp #TD_TOP_LINE-8
    bcc !off+
    cmp #240
    bcc !next+
!off:
    lda #0
    sta B_ON,x
!next:
    dex
    bpl !loop-
    rts

// -------------------------------------------------------------------
// Sprites på nivå 3
// -------------------------------------------------------------------
tdBuildSprites:
    lda #0
    sta vsN
    sta sprXexp
    sta sprYexp
    sta sprPrio
    lda tdState
    cmp #TDS_PLAY
    bcc !chute+
    jmp !ground+

    // ---- fallskärmen: kupolen = 4 hires-sprites, gubben = 3 hires-lager
    //      på samma koordinater, skuggan. Sorteras uppifrån av multiplexern.
!chute:
    lda #0
    sta vsTXH
    sta vsTM
    ldx #0
!loop:
    lda px                  // kupolen: x-12 / x+12, y-41 / y-20
    clc
    adc canopyDX,x
    sta vsTX
    lda py
    clc
    adc canopyDY,x
    sta tmp0
    lda tdState             // landat: kupolen sjunker ihop
    cmp #TDS_LAND
    bne !+
    lda #24
    sec
    sbc tdTimer
    asl
    clc
    adc tmp0
    sta tmp0
!:  lda tmp0
    sta vsTY
    lda canopyPtr,x
    sta vsTP
    lda #COL_WHITE
    sta vsTC
    jsr vsPush
    inx
    cpx #4
    bne !loop-
    lda px
    sta vsTX
    lda py
    sta vsTY
    lda tdState
    cmp #TDS_LAND
    beq !landed+
    ldx #0                  // gubben i selen
!loop:
    lda jumperPtr,x
    sta vsTP
    lda jumperCol,x
    sta vsTC
    jsr vsPush
    inx
    cpx #3
    bne !loop-
    lda #TD_LAND_Y          // skuggan: närmar sig gubben när han sjunker
    sec
    sbc py
    lsr
    clc
    adc px
    sta vsTX
    lda #TD_LAND_Y+14
    sta vsTY
    lda #SPR_TD_SHADOW
    sta vsTP
    lda #COL_BLACK
    sta vsTC
    lda #1
    sta vsTM
    jsr vsPush
    jmp tdMuxPrepare
!landed:
    lda #SPR_TD_PLAYER0
    sta vsTP
    lda #COL_CYAN
    sta vsTC
    lda #1
    sta vsTM
    jsr vsPush
    jmp tdMuxPrepare

    // ---- på marken
!ground:
    lda px
    sta vsTX
    lda pxHi
    sta vsTXH
    lda py
    sta vsTY
    lda #1
    sta vsTM
    lda pState
    beq !alive+
    lda #COL_YELLOW         // explosion
    sta vsTC
    lda frameCount
    lsr
    lsr
    lsr
    and #1
    clc
    adc #SPR_BOOM0
    sta vsTP
    jsr vsPush
    jmp !rest+
!alive:
    lda invuln              // blinkar när han inte kan skadas
    beq !+
    lda frameCount
    and #4
    bne !rest+
!:  lda joy                 // gångbilder när han rör sig
    and #JOY_UP+JOY_DOWN+JOY_LEFT+JOY_RIGHT
    beq !+
    lda frameCount
    lsr
    lsr
    lsr
    and #1
!:  clc
    adc #SPR_TD_PLAYER0
    sta vsTP
    lda #COL_CYAN
    sta vsTC
    jsr vsPush
!rest:
    jsr tdPushObjects
    jmp tdMuxPrepare

jumperPtr:  .byte SPR_JUMPER_K, SPR_JUMPER_S, SPR_JUMPER_C
jumperCol:  .byte COL_BLACK, COL_LIGHT_RED, COL_CYAN
canopyPtr:  .byte SPR_CANOPY_TL, SPR_CANOPY_TR, SPR_CANOPY_BL, SPR_CANOPY_BR
canopyDX:   .byte 256-12, 12, 256-12, 12
canopyDY:   .byte 256-41, 256-41, 256-20, 256-20
