// ===================================================================
// Raster-avbrott
//
//  Linje 251 (under spelfältet): HUD-raden får ingen finscroll,
//                                signalera ny bildruta till huvudloopen.
//  Linje 63  (i den tomma rad 1): byt skärmbuffert och sätt finscroll
//                                för grottan.
// ===================================================================

irq:
    pha
    txa
    pha
    tya
    pha
    lda #$ff
    sta $d019               // kvittera
    lda irqStage
    bne irqTop

    // ---- nederkant
    lda hudD016
    sta $d016
    inc frameFlag
    lda #IRQ_LINE_TOP
    sta $d012
    lda #1
    sta irqStage
    jmp irqExit

    // ---- överkant (före första grottraden)
irqTop:
    lda nextD018
    sta $d018
    lda nextD016
    sta $d016
    lda #IRQ_LINE_BOTTOM
    sta $d012
    lda #0
    sta irqStage

irqExit:
    pla
    tay
    pla
    tax
    pla
nmi:
    rti

// -------------------------------------------------------------------
// Skriv skuggregistren till VIC. Körs direkt efter waitFrame (i vblank).
// -------------------------------------------------------------------
applyFrame:
    lda pendingSwap
    beq !noswap+
    lda #0
    sta pendingSwap
    lda dispBuf
    eor #1
    sta dispBuf
    lda #2                  // börja förbereda nästa dolda buffert
    sta needCopy
!noswap:
    lda pendingD016
    sta nextD016
    lda pendingD018
    sta nextD018

    ldx #7
!loop:
    lda sprPtr,x
    sta SCREEN_A+$3f8,x
    sta SCREEN_B+$3f8,x
    lda sprCol,x
    sta $d027,x
    dex
    bpl !loop-

    ldx #0
    ldy #0
!loop:
    lda sprX,x
    sta $d000,y
    lda sprY,x
    sta $d001,y
    iny
    iny
    inx
    cpx #8
    bne !loop-
    lda sprMsb
    sta $d010
    lda sprEnable
    sta $d015
    rts
