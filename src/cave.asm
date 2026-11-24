// ===================================================================
// Grottan: generator, ringbuffert och scrollning
//
// Varje kolumn i grottan beskrivs av antal takrader och golvrader.
// De senaste 64 kolumnerna ligger i en ringbuffert. Skärmkolumn x
// motsvarar ring[(ringBase + x) & 63].
// ===================================================================

initGenerator:
    lda #2
    sta gCeil
    lda #3
    sta gFloor
    lda #44                 // lugn start
    sta gSeg
    lda #0
    sta gPit
    lda #16
    sta gPitCool
    // fall igenom
setGenRun:
    lda #2
    sta genFMin
    lda #8
    sta genFMax
    lda #2
    sta genCMin
    lda #7
    sta genCMax
    lda #PLAY_ROWS-10       // minst 10 rader öppning
    sta genGap
    rts

setGenFly:
    lda #1
    sta genFMin
    lda #9
    sta genFMax
    lda #1
    sta genCMin
    lda #9
    sta genCMax
    lda #PLAY_ROWS-7        // minst 7 rader öppning
    sta genGap
    lda #1
    sta gSeg
    rts

// -------------------------------------------------------------------
// genColumn: skapa nästa kolumn i ring[genPtr & 63]. Bevarar X.
// -------------------------------------------------------------------
genColumn:
    lda gPit
    beq !nopit+
    dec gPit
    lda #0
    sta tmp0
    jmp !store+
!nopit:
    lda gPitCool
    beq !+
    dec gPitCool
!:  dec gSeg
    bne !keep+
    jsr newSegment
!keep:
    lda phase
    cmp #PH_FLY
    bne !+
    jsr flyStep
!:  lda gFloor
    sta tmp0
!store:
    lda genPtr
    and #63
    tay
    lda gCeil
    sta RING_CEIL,y
    asl
    asl
    asl
    clc
    adc #PLAY_Y0
    sta RING_CEILY,y
    lda tmp0
    sta RING_FLOOR,y
    beq !pit+
    asl
    asl
    asl
    sta tmp1
    lda #PLAY_Y1
    sec
    sbc tmp1
    sta RING_FLOORY,y
    jmp !done+
!pit:
    lda #PIT_Y
    sta RING_FLOORY,y
!done:
    inc genPtr
    rts

// -------------------------------------------------------------------
// newSegment: välj hur grottan ska se ut de närmaste kolumnerna
// -------------------------------------------------------------------
newSegment:
    lda phase
    cmp #PH_LANDING
    beq !land+
    cmp #PH_DOCK
    bne !+
!land:
    jmp segLanding
!:  cmp #PH_FLY
    bne !+
    jmp segFly
!:

    // ---- springfasen: längre segment, gropar och trappsteg
    jsr rnd
    and #7
    clc
    adc #3
    sta gSeg                // 3-10 kolumner
    jsr rnd
    and #7
    jsr runAction
    jsr rnd                 // och ibland ändras taket också
    and #3
    bne !+
    jmp ceilDown
!:  cmp #1
    bne !+
    jmp ceilUp
!:  rts

runAction:
    cmp #2
    bcc floorUp
    cmp #4
    bcc floorDown
    cmp #5
    bcc ceilDown
    cmp #6
    bcc ceilUp
    cmp #7
    bcc makePit
    jsr floorUp             // högt trappsteg (2 rader)
    jmp floorUp

floorUp:
    lda gFloor
    cmp genFMax
    bcs !done+
    clc
    adc gCeil
    cmp genGap
    bcs !done+
    inc gFloor
!done:
    rts

floorDown:
    lda genFMin
    cmp gFloor
    bcs !done+              // gFloor <= min
    dec gFloor
!done:
    rts

ceilDown:                   // taket växer nedåt
    lda gCeil
    cmp genCMax
    bcs !done+
    clc
    adc gFloor
    cmp genGap
    bcs !done+
    inc gCeil
!done:
    rts

ceilUp:
    lda genCMin
    cmp gCeil
    bcs !done+
    dec gCeil
!done:
    rts

makePit:
    lda gPitCool
    bne !done+
    lda wave                // inga gropar i början av en nivå
    bne !ok+
    lda waveCol
    cmp #40
    bcc !done+
!ok:
    jsr rnd
    and #1
    clc
    adc #3
    sta gPit                // 3-4 kolumner bred
    lda #14
    sta gPitCool
!done:
    rts

// Landningszonen: platt mark för rymdskeppet
segLanding:
    lda #3
    sta gSeg
    lda gFloor
    cmp #3
    beq !ceil+
    bcc !up+
    dec gFloor
    jmp !ceil+
!up:
    inc gFloor
!ceil:
    lda gCeil
    cmp #2
    beq !done+
    bcc !up+
    dec gCeil
    rts
!up:
    inc gCeil
!done:
    rts

    // ---- flygfasen: välj ett nytt mål för tak och golv. Tunneln
    // glider mot målet ett steg varannan kolumn (flyStep).
segFly:
    jsr rnd
    and #7
    clc
    adc #4
    sta gSeg                // 4-11 kolumner
    jsr rnd
    and #7
    clc
    adc #1
    sta gCeilT              // tak 1-8 rader
    jsr rnd
    and #3
    clc
    adc #8
    sta tmp1                // öppning 8-11 rader
    lda level
    cmp #3
    bcc !+
    dec tmp1                // senare nivåer: smalare
!:  lda #PLAY_ROWS
    sec
    sbc gCeilT
    sec
    sbc tmp1
    sta gFloorT
    rts

flyStep:
    lda genPtr
    and #1
    bne !done+
    lda gCeil
    cmp gCeilT
    beq !floor+
    bcc !grow+
    dec gCeil
    jmp !floor+
!grow:
    clc
    adc gFloor
    cmp genGap
    bcs !floor+
    inc gCeil
!floor:
    lda gFloor
    cmp gFloorT
    beq !done+
    bcc !grow+
    dec gFloor
    rts
!grow:
    clc
    adc gCeil
    cmp genGap
    bcs !done+
    inc gFloor
!done:
    rts

// -------------------------------------------------------------------
// colAt: vilken ringkolumn ligger under sprite-x (cxLo/cxHi)?
// Ut: Y = ringindex. Förstör cxLo/cxHi. Bevarar X.
// -------------------------------------------------------------------
colAt:
    lda cxLo
    sec
    sbc #24
    sta cxLo
    lda cxHi
    sbc #0
    sta cxHi
    lda cxLo
    sec
    sbc fine
    sta cxLo
    lda cxHi
    sbc #0
    bmi !neg+
    lsr
    ror cxLo
    lsr
    ror cxLo
    lsr
    ror cxLo
    lda cxLo
    cmp #41
    bcc !ok+
    lda #40
!ok:
    clc
    adc ringBase
    and #63
    tay
    rts
!neg:
    lda ringBase
    and #63
    tay
    rts

// -------------------------------------------------------------------
// probeColumns: titta på kolumnerna under spelarens vänstra och högra
// kant. Ut: floorTop = högsta golvet, ceilBot = lägsta taket,
//           tmp2 = golv vänster, tmp3 = golv höger
// -------------------------------------------------------------------
probeColumns:
    lda px
    clc
    adc #P_LEFT
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda RING_FLOORY,y
    sta floorTop
    sta tmp2
    lda RING_CEILY,y
    sta ceilBot
    lda px
    clc
    adc #P_RIGHT
    sta cxLo
    lda #0
    sta cxHi
    jsr colAt
    lda RING_FLOORY,y
    sta tmp3
    cmp floorTop
    bcs !+
    sta floorTop
!:  lda RING_CEILY,y
    cmp ceilBot
    bcc !+
    sta ceilBot
!:  rts

// -------------------------------------------------------------------
// worldStep: flytta världen scrollSpeed pixlar åt vänster
// -------------------------------------------------------------------
worldStep:
    lda fine
    sec
    sbc scrollSpeed
    bcs !nowrap+
    adc #8                  // carry är 0 här
    sta fine
    lda needCopy            // (ska redan vara klar)
    beq !+
    jsr copyFinish
!:  inc ringBase
    lda genPtr
    sta newColIdx
    jsr genColumn
    lda #1
    sta pendingSwap
    lda dispBuf
    bne !toA+
    lda #D018_B
    bne !set+
!toA:
    lda #D018_A
!set:
    sta pendingD018
    jsr columnPassed
    jmp !done+
!nowrap:
    sta fine
!done:
    lda fine
    ora #D016_GAME
    sta pendingD016
    rts

// En kolumn har passerat: poäng, vågor och fasbyten
columnPassed:
    lda #$01
    jsr addScore
    lda landDelay
    beq !+
    dec landDelay
!:  lda phase
    cmp #PH_RUN
    beq !count+
    cmp #PH_FLY
    bne !done+
!count:
    inc waveCol
    lda waveCol
    cmp #WAVE_LEN
    bne !done+
    lda #0
    sta waveCol
    inc wave
    lda wave
    cmp #NUM_WAVES
    beq !phaseEnd+
    jsr setMaxMon           // ny våg: nya monster, fler monster
    jmp showWaveMsg
!phaseEnd:
    lda #NUM_WAVES-1
    sta wave
    lda phase
    cmp #PH_RUN
    bne !dock+
    lda #PH_LANDING         // dags för rymdskeppet
    sta phase
    lda #8
    sta landDelay
    lda #<msgShip
    ldx #>msgShip
    jmp showMsg
!dock:
    lda #PH_DOCK            // flygfasen klar: landa
    sta phase
    lda #48                 // marken hinner plana ut innan landningen
    sta landDelay
    lda #1
    sta gSeg
    lda level               // nästa nivå ovanifrån: hoppa i stället
    clc
    adc #1
    jsr isTdLevel
    beq !jump+
    lda #<msgDock
    ldx #>msgDock
    jmp showMsg
!jump:
    lda #<msgJump
    ldx #>msgJump
    jmp showMsg
!done:
    rts

// addScore: lägg till BCD-värdet i A till poängen
addScore:
    sed
    clc
    adc score+2
    sta score+2
    lda score+1
    adc #0
    sta score+1
    lda score
    adc #0
    sta score
    cld
    rts
