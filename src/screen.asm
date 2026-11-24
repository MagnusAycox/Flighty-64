// ===================================================================
// Skärmrutiner: text, rensning, HUD, dubbelbuffrad scroll
// ===================================================================

.encoding "screencode_upper"

// Radadresser för skärm A (för B adderas SCREEN_B_OFS_HI till hi-byten)
rowLo:
.for (var r=0; r<25; r++) {
    .byte <(SCREEN_A + r*40)
}
rowHi:
.for (var r=0; r<25; r++) {
    .byte >(SCREEN_A + r*40)
}

// -------------------------------------------------------------------
// printText: skriver ett textblock till båda skärmbuffertarna.
// Blockformat: rad, kolumn, färg, text..., 0
// In: textPtr pekar på blocket. Ut: textPtr pekar på nästa block.
// -------------------------------------------------------------------
printText:
    ldy #0
    lda (textPtr),y         // rad
    tax
    iny
    lda (textPtr),y         // kolumn
    clc
    adc rowLo,x
    sta scrPtr
    sta scrPtrB
    sta colPtr2
    lda rowHi,x
    adc #0
    sta scrPtr+1
    clc
    adc #SCREEN_B_OFS_HI
    sta scrPtrB+1
    lda scrPtr+1
    clc
    adc #COLOR_OFS_HI
    sta colPtr2+1
    iny
    lda (textPtr),y         // färg
    sta printColor
    lda textPtr
    clc
    adc #3
    sta textPtr
    bcc !+
    inc textPtr+1
!:  ldy #0
!loop:
    lda (textPtr),y
    beq !done+
    sta (scrPtr),y
    sta (scrPtrB),y
    lda printColor
    sta (colPtr2),y
    iny
    bne !loop-
!done:
    iny
    tya
    clc
    adc textPtr
    sta textPtr
    bcc !+
    inc textPtr+1
!:  rts

// printList: skriv block tills första byten är $ff. In: A/X = lo/hi
printList:
    sta textPtr
    stx textPtr+1
!loop:
    ldy #0
    lda (textPtr),y
    cmp #$ff
    beq !done+
    jsr printText
    jmp !loop-
!done:
    rts

// -------------------------------------------------------------------
// Rensa båda skärmarna, färg-RAM = clearColor
// -------------------------------------------------------------------
clearScreens:
    ldx #0
!loop:
    lda #32
    sta SCREEN_A,x
    sta SCREEN_A+250,x
    sta SCREEN_A+500,x
    sta SCREEN_A+750,x
    sta SCREEN_B,x
    sta SCREEN_B+250,x
    sta SCREEN_B+500,x
    sta SCREEN_B+750,x
    lda clearColor
    sta COLORRAM,x
    sta COLORRAM+250,x
    sta COLORRAM+500,x
    sta COLORRAM+750,x
    inx
    cpx #250
    bne !loop-
    rts

// Rensa för spel: HUD-raderna vita, grottan med färg A (multicolor)
clearGameScreens:
    pha
    lda #COL_WHITE
    sta clearColor
    jsr clearScreens
    pla
    // fall igenom
setCaveColors:              // A = färg-RAM-värde för rad 2-24
    ldx #0
!loop:
    sta COLORRAM+80,x
    sta COLORRAM+80+230,x
    sta COLORRAM+80+460,x
    sta COLORRAM+80+690,x
    inx
    cpx #230
    bne !loop-
    rts

// -------------------------------------------------------------------
// HUD (rad 0)
// -------------------------------------------------------------------
.const HUD_SCORE = 7
.const HUD_LEVEL = 17
.const HUD_WAVE  = 20
.const HUD_LIVES = 28
.const HUD_HI    = 33

// SCORE 000000 LV 01-1 LIVES 3 HI 000000  (kolumn 1-38)
hudText:
    .byte 0, 1, COL_LIGHT_BLUE
    .text "SCORE"
    .byte 0
    .byte 0, 14, COL_LIGHT_BLUE
    .text "LV"
    .byte 0
    .byte 0, 22, COL_LIGHT_BLUE
    .text "LIVES"
    .byte 0
    .byte 0, 30, COL_LIGHT_BLUE
    .text "HI"
    .byte 0
    .byte 0, HUD_SCORE, COL_WHITE
    .text "000000"
    .byte 0
    .byte 0, HUD_LEVEL, COL_GREEN
    .text "00-0"
    .byte 0
    .byte 0, HUD_LIVES, COL_WHITE
    .text "0"
    .byte 0
    .byte 0, HUD_HI, COL_YELLOW
    .text "000000"
    .byte 0
    .byte $ff

// Meddelanden som tillfälligt ersätter HUD-raden
.const MSG_LEVEL = 17
.const MSG_WAVE  = 26
msgWave:
    .byte 0, 11, COL_YELLOW
    .text "LEVEL 00  WAVE 0"
    .byte 0
    .byte $ff
msgShip:
    .byte 0, 8, COL_YELLOW
    .text "THE SPACESHIP IS NEAR!"
    .byte 0
    .byte $ff
msgDock:
    .byte 0, 12, COL_YELLOW
    .text "PREPARE TO LAND"
    .byte 0
    .byte $ff

msgJump:
    .byte 0, 12, COL_YELLOW
    .text "PREPARE TO JUMP"
    .byte 0
    .byte $ff
msgDrop:
    .byte 0, 11, COL_YELLOW
    .text "LEVEL 00  DROP ZONE"
    .byte 0
    .byte $ff
msgClear:
    .byte 0, 14, COL_YELLOW
    .text "STAGE CLEAR!"
    .byte 0
    .byte $ff

// Nivå 3: GRENADE i stället för HI
.const HUD_GREN = 38
hudTextTd:
    .byte 0, 30, COL_LIGHT_BLUE
    .text "GRENADE"
    .byte 0
    .byte 0, HUD_GREN, COL_YELLOW
    .text "0"
    .byte 0
    .byte $ff

// showMsg: visa blocklistan A/X på HUD-raden i ca 2,5 sekunder
showMsg:
    jsr clearHudRow
    jsr printList
    lda #125
    sta hudMsgTimer
    rts

// Töm HI-fältet (kolumn 30-39) i båda buffertarna
clearHiField:
    ldx #9
    lda #32
!loop:
    sta SCREEN_A+30,x
    sta SCREEN_B+30,x
    dex
    bpl !loop-
    rts

// "LEVEL nn  DROP ZONE"
showDropMsg:
    lda #<msgDrop
    ldx #>msgDrop
    jsr showMsg
    ldx #17
    jmp putLevel

// "LEVEL nn  WAVE n"
showWaveMsg:
    lda #<msgWave
    ldx #>msgWave
    jsr showMsg
    ldx #MSG_LEVEL
    jsr putLevel
    lda wave
    clc
    adc #$31
    sta SCREEN_A+MSG_WAVE
    sta SCREEN_B+MSG_WAVE
    rts

// putLevel: skriv nivån med två siffror på rad 0, kolumn X
putLevel:
    lda level
    ldy #$30
!loop:
    cmp #10
    bcc !done+
    sbc #10
    iny
    jmp !loop-
!done:
    ora #$30
    sta SCREEN_A+1,x
    sta SCREEN_B+1,x
    tya
    sta SCREEN_A,x
    sta SCREEN_B,x
    rts

// clearHudRow: töm rad 0 i båda buffertarna (bevarar A och X)
clearHudRow:
    pha
    txa
    pha
    ldx #39
    lda #32
!loop:
    sta SCREEN_A,x
    sta SCREEN_B,x
    dex
    bpl !loop-
    pla
    tax
    pla
    rts

drawHud:
    jsr clearHudRow
    lda #<hudText
    ldx #>hudText
    jsr printList
    lda tdOn
    beq !+
    jsr clearHiField
    lda #<hudTextTd
    ldx #>hudTextTd
    jsr printList
!:  // fall igenom
hudUpdate:
    lda hudMsgTimer         // visas ett meddelande?
    beq !normal+
    dec hudMsgTimer
    bne !rts+
    jmp drawHud
!rts:
    rts
!normal:
    ldx #HUD_LEVEL
    jsr putLevel
    lda wave
    clc
    adc #$31
    sta SCREEN_A+HUD_WAVE
    sta SCREEN_B+HUD_WAVE

    ldx #0
    ldy #0
!loop:
    lda score,x
    lsr
    lsr
    lsr
    lsr
    ora #$30
    sta SCREEN_A+HUD_SCORE,y
    sta SCREEN_B+HUD_SCORE,y
    iny
    lda score,x
    and #$0f
    ora #$30
    sta SCREEN_A+HUD_SCORE,y
    sta SCREEN_B+HUD_SCORE,y
    iny
    inx
    cpx #3
    bne !loop-

    lda lives
    ora #$30
    sta SCREEN_A+HUD_LIVES
    sta SCREEN_B+HUD_LIVES

    lda tdOn                // nivå 3: antal granater i stället för HI
    beq !hi+
    lda tdGren
    ora #$30
    sta SCREEN_A+HUD_GREN
    sta SCREEN_B+HUD_GREN
    rts
!hi:

    // HI = max(poäng, bästa i listan)
    lda score
    cmp hsScore
    bcc !table+
    bne !own+
    lda score+1
    cmp hsScore+1
    bcc !table+
    bne !own+
    lda score+2
    cmp hsScore+2
    bcc !table+
!own:
    lda #<score
    sta tmp0
    lda #>score
    sta tmp1
    jmp !show+
!table:
    lda #<hsScore
    sta tmp0
    lda #>hsScore
    sta tmp1
!show:
    ldx #0
    ldy #0
!loop:
    lda (tmp0),y
    lsr
    lsr
    lsr
    lsr
    ora #$30
    sta SCREEN_A+HUD_HI,x
    sta SCREEN_B+HUD_HI,x
    inx
    lda (tmp0),y
    and #$0f
    ora #$30
    sta SCREEN_A+HUD_HI,x
    sta SCREEN_B+HUD_HI,x
    inx
    iny
    cpy #3
    bne !loop-
    rts

// -------------------------------------------------------------------
// Dubbelbuffrad grovscroll.
// Den synliga bufferten kopieras ett tecken åt vänster till den dolda,
// i två halvor fördelade på två bildrutor. Sedan ritas den nya
// kolumnen längst till höger.
// -------------------------------------------------------------------
.const HALF = 12            // rad 0-11 i första halvan, 12-22 i andra

copyStep:
    lda needCopy
    bne !+
    rts
!:  cmp #2
    bne !second+
    dec needCopy
    lda dispBuf
    bne !fromB+
    jmp copyA2B_top
!fromB:
    jmp copyB2A_top
!second:
    dec needCopy
    lda dispBuf
    bne !fromB+
    jsr copyA2B_bot
    lda #<(SCREEN_B + PLAY_TOP*40 + 39)
    sta colPtr
    lda #>(SCREEN_B + PLAY_TOP*40 + 39)
    sta colPtr+1
    jmp !draw+
!fromB:
    jsr copyB2A_bot
    lda #<(SCREEN_A + PLAY_TOP*40 + 39)
    sta colPtr
    lda #>(SCREEN_A + PLAY_TOP*40 + 39)
    sta colPtr+1
!draw:
    ldy newColIdx
    jmp drawRingColumn

// Kör klart en eventuellt påbörjad kopiering
copyFinish:
    lda needCopy
    beq !done+
    jsr copyStep
    jmp copyFinish
!done:
    rts

copyA2B_top:
    ldx #0
!loop:
.for (var r=0; r<HALF; r++) {
    lda SCREEN_A + (PLAY_TOP+r)*40 + 1,x
    sta SCREEN_B + (PLAY_TOP+r)*40,x
}
    inx
    cpx #39
    beq !done+
    jmp !loop-
!done:
    rts

copyA2B_bot:
    ldx #0
!loop:
.for (var r=HALF; r<PLAY_ROWS; r++) {
    lda SCREEN_A + (PLAY_TOP+r)*40 + 1,x
    sta SCREEN_B + (PLAY_TOP+r)*40,x
}
    inx
    cpx #39
    beq !done+
    jmp !loop-
!done:
    rts

copyB2A_top:
    ldx #0
!loop:
.for (var r=0; r<HALF; r++) {
    lda SCREEN_B + (PLAY_TOP+r)*40 + 1,x
    sta SCREEN_A + (PLAY_TOP+r)*40,x
}
    inx
    cpx #39
    beq !done+
    jmp !loop-
!done:
    rts

copyB2A_bot:
    ldx #0
!loop:
.for (var r=HALF; r<PLAY_ROWS; r++) {
    lda SCREEN_B + (PLAY_TOP+r)*40 + 1,x
    sta SCREEN_A + (PLAY_TOP+r)*40,x
}
    inx
    cpx #39
    beq !done+
    jmp !loop-
!done:
    rts

// -------------------------------------------------------------------
// drawRingColumn: rita kolumnen ring[Y & 63] med början på colPtr
// (colPtr = adress till grottans översta rad i önskad kolumn)
// -------------------------------------------------------------------
drawRingColumn:
    tya
    and #63
    tay
    lda RING_CEIL,y
    sta dcCeil
    lda RING_FLOOR,y
    sta dcFloor
    tya
    eor #$15
    sta dcSeed
    // fall igenom

// drawColumn: dcCeil = takrader, dcFloor = golvrader (0 = grop)
drawColumn:
    lda #PLAY_ROWS
    sec
    sbc dcFloor
    sta dcFtop              // första golvraden
    ldx #0
!row:
    txa
    clc
    adc #1
    cmp dcCeil
    bcc !rock+              // r+1 < tak
    beq !ceilEdge+          // r+1 = tak -> takkant
    cpx dcFtop
    bcc !empty+
    beq !floorEdge+
!rock:
    txa
    eor dcSeed
    and #3
    ora #CH_ROCK0
    bne !put+
!ceilEdge:
    lda dcSeed
    and #1
    ora #CH_CEIL0
    bne !put+
!floorEdge:
    txa
    eor dcSeed
    and #1
    ora #CH_FLOOR0
    bne !put+
!empty:
    lda dcFloor             // grop: piggar i botten
    bne !blank+
    cpx #PLAY_ROWS-1
    bne !blank+
    lda #CH_SPIKE
    bne !put+
!blank:
    lda #32
!put:
    ldy #0
    sta (colPtr),y
    lda colPtr
    clc
    adc #40
    sta colPtr
    bcc !+
    inc colPtr+1
!:  inx
    cpx #PLAY_ROWS
    bne !row-
    rts
