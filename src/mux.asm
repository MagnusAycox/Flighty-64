// ===================================================================
// Sprite-multiplexer för nivå 3
//
//  Spelet lägger upp till 16 "virtuella" sprites i VS_-tabellerna varje
//  bildruta (vsPush). tdMuxPrepare sorterar dem uppifrån och ned:
//    * de 8 översta skrivs till VIC i vblank (via skuggregistren, som
//      vanligt i applyFrame)
//    * resten återanvänder hårdvarusprite (k & 7) längre ned på skärmen:
//      ett raster-avbrott på linjen efter att den förra spriten i samma
//      hårdvarusprite har ritats klart skriver om x, y, pekare, färg,
//      multicolor- och x-bit. Spriten måste ligga minst 24 linjer under
//      den förra i samma hårdvarusprite, annars visas den inte denna
//      bildruta.
//  Schemat byggs i huvudloopen (mp_) och kopieras till de aktiva
//  tabellerna (ma_) i vblank, så avbrotten aldrig läser halvfärdiga data.
// ===================================================================

.const VS_MAX     = 16
.const VS_Y       = $cc00
.const VS_XL      = $cc10
.const VS_XH      = $cc20
.const VS_P       = $cc30
.const VS_C       = $cc40
.const VS_M       = $cc50         // 1 = multicolor
.const VS_ORD     = $cc60         // sorterad ordning (index)
.const MP_LINE    = $cc70         // schema (byggs i huvudloopen), 8 platser
.const MP_HW      = $cc78
.const MP_X       = $cc80
.const MP_XH      = $cc88
.const MP_Y       = $cc90
.const MP_P       = $cc98
.const MP_C       = $cca0
.const MP_M       = $cca8
.const MA_LINE    = $ccb0         // schema som avbrotten läser
.const MA_HW      = $ccb8
.const MA_X       = $ccc0
.const MA_XH      = $ccc8
.const MA_Y       = $ccd0
.const MA_P       = $ccd8
.const MA_C       = $cce0
.const MA_M       = $cce8
.const HW_LASTY   = $ccf0         // y för sprite som senast lades i varje hårdvarusprite
.const VS_SY      = $cd80         // y sorterad (följer VS_ORD)

// vsPush: lägg till en virtuell sprite.
// In: vsTX/vsTXH (x), vsTY (y), vsTP (pekare), vsTC (färg), vsTM (1 = multicolor)
// Bevarar X och Y.
vsPush:
    stx mxSaveX
    ldx vsN
    cpx #VS_MAX
    bcs !full+
    lda vsTY
    sta VS_Y,x
    sta VS_SY,x
    txa
    sta VS_ORD,x
    lda vsTX
    sta VS_XL,x
    lda vsTXH
    sta VS_XH,x
    lda vsTP
    sta VS_P,x
    lda vsTC
    sta VS_C,x
    lda vsTM
    sta VS_M,x
    inc vsN
!full:
    ldx mxSaveX
    rts

// -------------------------------------------------------------------
// tdMuxPrepare: sortera och bygg skuggregister + schema
// -------------------------------------------------------------------
tdMuxPrepare:
    ldx #1                  // insättningssortering på y (stabil), direkt
!outer:                     // på (VS_SY, VS_ORD) som vsPush fyllt i
    cpx vsN
    bcs !sorted+
    lda VS_SY,x
    cmp VS_SY-1,x           // redan i ordning? (vanligast)
    bcs !next+
    sta mxKeyY
    adc #1                  // (C=0) y+1: flytta de som är > y
    sta mxJ
    lda VS_ORD,x
    sta mxKey
    txa
    tay
!inner:
    lda VS_SY-1,y
    cmp mxJ
    bcc !place+
    sta VS_SY,y
    lda VS_ORD-1,y
    sta VS_ORD,y
    dey
    bne !inner-
!place:
    lda mxKeyY
    sta VS_SY,y
    lda mxKey
    sta VS_ORD,y
!next:
    inx
    bne !outer-
!sorted:

    // de 8 första: skuggregistren
    lda #0
    sta sprEnable
    sta sprMsb
    sta sprMC
    sta mpN
    ldx #0
!loop:
    cpx vsN
    bcs !rest+
    cpx #8
    bcs !rest+
    ldy VS_ORD,x
    lda VS_XL,y
    sta sprX,x
    lda VS_Y,y
    sta sprY,x
    sta HW_LASTY,x
    lda VS_P,y
    sta sprPtr,x
    lda VS_C,y
    sta sprCol,x
    lda bitTab,x
    ora sprEnable
    sta sprEnable
    lda VS_XH,y
    beq !+
    lda bitTab,x
    ora sprMsb
    sta sprMsb
!:  lda VS_M,y
    beq !+
    lda bitTab,x
    ora sprMC
    sta sprMC
!:  inx
    jmp !loop-

    // resten: schema för raster-avbrotten
!rest:
    cpx vsN
    bcs !done+
    txa
    and #7
    sta mxHw
    tay
    lda HW_LASTY,y
    cmp #212                // nästa skulle hamna under spelplanen
    bcs !skip+
    clc
    adc #24
    sta mxKeyY              // minsta y för nästa sprite i denna hårdvarusprite
    lda VS_SY,x
    cmp mxKeyY
    bcc !skip+              // för nära: visas inte denna bildruta
    ldy mpN
    cpy #8
    bcs !done+
    lda mxKeyY
    sec
    sbc #2                  // byt på linjen efter att förra spriten ritats klart
    cmp #TD_TOP_LINE+2
    bcs !+
    lda #TD_TOP_LINE+2
!:  sta MP_LINE,y
    lda mxHw
    sta MP_HW,y
    stx mxJ
    lda VS_ORD,x            // X = virtuell sprite
    tax
    lda VS_XL,x
    sta MP_X,y
    lda VS_XH,x
    sta MP_XH,y
    lda VS_Y,x
    sta MP_Y,y
    lda VS_P,x
    sta MP_P,y
    lda VS_C,x
    sta MP_C,y
    lda VS_M,x
    sta MP_M,y
    lda VS_Y,x
    ldx mxHw
    sta HW_LASTY,x
    ldx mxJ
    inc mpN
!skip:
    inx
    jmp !rest-
!done:
    rts

// -------------------------------------------------------------------
// I vblank (applyFrame): schemat blir aktivt
// -------------------------------------------------------------------
tdMuxActivate:
    ldx mpN
    stx maN
    lda #0
    sta maI
    dex
    bmi !done+
!loop:
    lda MP_LINE,x
    sta MA_LINE,x
    lda MP_HW,x
    sta MA_HW,x
    lda MP_X,x
    sta MA_X,x
    lda MP_XH,x
    sta MA_XH,x
    lda MP_Y,x
    sta MA_Y,x
    lda MP_P,x
    sta MA_P,x
    lda MP_C,x
    sta MA_C,x
    lda MP_M,x
    sta MA_M,x
    dex
    bpl !loop-
!done:
    rts

// -------------------------------------------------------------------
// Raster-avbrotten. muxStart anropas från irqTop (linje 63/64),
// muxIrq när irqStage = 2. Båda avslutar med att sätta nästa avbrott.
// -------------------------------------------------------------------
muxStart:
    lda maN
    beq !bottom+
    lda #2
    sta irqStage
    jmp muxNext

muxIrq:
    ldx maI
    lda MA_HW,x
    tay
    lda MA_P,x
    sta SCREEN_A+$3f8,y
    sta SCREEN_B+$3f8,y
    lda MA_C,x
    sta $d027,y
    lda MA_XH,x             // x-bit 8
    beq !+
    lda bitTab,y
    ora $d010
    bne !set+
!:  lda bitTab,y
    eor #$ff
    and $d010
!set:
    sta $d010
    lda MA_M,x              // multicolor
    beq !+
    lda bitTab,y
    ora $d01c
    bne !set+
!:  lda bitTab,y
    eor #$ff
    and $d01c
!set:
    sta $d01c
    tya
    asl
    tay
    lda MA_X,x
    sta $d000,y
    lda MA_Y,x
    sta $d001,y
    inc maI

muxNext:
    ldx maI
    cpx maN
    bcs !bottom+
    lda MA_LINE,x           // har linjen redan kommit? då direkt
    sec
    sbc #2
    cmp $d012
    bcc muxIrq
    beq muxIrq
    lda MA_LINE,x
    sta $d012
    rts
!bottom:
    lda #IRQ_LINE_BOTTOM
    sta $d012
    lda #0
    sta irqStage
    rts
