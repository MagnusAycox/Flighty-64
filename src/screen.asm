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
.const HUD_LIVES = 22
.const HUD_HI    = 29

hudText:
    .byte 0, 1, COL_LIGHT_BLUE
    .text "SCORE"
    .byte 0
    .byte 0, 16, COL_LIGHT_BLUE
    .text "LIVES"
    .byte 0
    .byte 0, 26, COL_LIGHT_BLUE
    .text "HI"
    .byte 0
    .byte 0, HUD_SCORE, COL_WHITE
    .text "000000"
    .byte 0
    .byte 0, HUD_LIVES, COL_WHITE
    .text "0"
    .byte 0
    .byte 0, HUD_HI, COL_YELLOW
    .text "000000"
    .byte 0
    .byte $ff

drawHud:
    lda #<hudText
    ldx #>hudText
    jsr printList
    // fall igenom
hudUpdate:
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
