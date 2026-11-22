// ===================================================================
// Startskärmens logo: "SOFTWARE OF SWEDEN"
//
//  * Stora bokstäver (16x24 px) byggs vid start av C64:ans egna
//    ROM-tecken: varje pixel blir 2x3 pixlar. Tecknen är inverterade,
//    så bokstaven är ett "hål" där bakgrundsfärgen ($d021) syns.
//  * Hela logon svänger i sidled längs en sinuskurva (finscroll +
//    förskjutning i hela tecken).
//  * Genom hålen syns en svensk flagga som studsar:
//      - den vågräta gula balken = $d021 byts till gult på några
//        rasterlinjer. Den studsar i en halv sinus (|sin|): skarp
//        vändning i nederkant, mjuk i överkant.
//      - den lodräta gula balken = sprite 0 bakom förgrunden ($d01b),
//        så den syns bara genom bokstäverna. Den glider höger-vänster
//        med vanlig sinus (mjuka vändningar).
// ===================================================================

.encoding "screencode_upper"

.const LOGO_ROW    = 1            // teckenrad 1-3
.const LOGO_LINE0  = 59           // första rasterlinjen (51 + 8*1)
.const LOGO_H      = 24           // rasterlinjer
.const LOGO_CHAR0  = 128          // logotecknen: 128-187
.const LOGO_SOLID  = 188          // helt svart tecken runt texten
.const LOGO_LEN    = 18           // tecken i texten
.const NUM_LOGO_LETTERS = 10
.const FLAG_BAR_H  = 5            // vågräta balkens höjd i rader (lodräta: 6 px)

// Bokstäverna som behövs, i den ordning de byggs
logoLetters:
    .text "SOFTWAREDN"
// Texten som index i logoLetters ($ff = mellanslag, en kolumn brett)
//            S  O  F  T  W  A  R  E  _    O  F  _    S  W  E  D  E  N
logoText:
    .byte 0, 1, 2, 3, 4, 5, 6, 7, $ff, 1, 2, $ff, 0, 4, 7, 8, 7, 9

// ROM-rad för varje logorad (rad / 3)
div3:
    .byte 0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3
    .byte 4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7
// 4 bitar -> 8 bitar med varje bit dubblerad
dblTab:
    .byte %00000000, %00000011, %00001100, %00001111
    .byte %00110000, %00110011, %00111100, %00111111
    .byte %11000000, %11000011, %11001100, %11001111
    .byte %11110000, %11110011, %11111100, %11111111

// -------------------------------------------------------------------
// buildLogoChars: skapa logotecknen (körs en gång, efter copyCharRom)
// Bokstav k får tecknen 128+6k .. 128+6k+5 (2 brett, 3 högt):
//   +0 +1   rad 0-7
//   +2 +3   rad 8-15
//   +4 +5   rad 16-23
// -------------------------------------------------------------------
buildLogoChars:
    lda #0
    sta tmp4
    lda #<(CHARSET + LOGO_CHAR0*8)
    sta memDst
    lda #>(CHARSET + LOGO_CHAR0*8)
    sta memDst+1
!letter:
    ldx tmp4                // memSrc = CHARSET + skärmkod*8
    lda logoLetters,x
    sta memSrc
    lda #0
    sta memSrc+1
    asl memSrc
    rol memSrc+1
    asl memSrc
    rol memSrc+1
    asl memSrc
    rol memSrc+1
    lda memSrc
    clc
    adc #<CHARSET
    sta memSrc
    lda memSrc+1
    adc #>CHARSET
    sta memSrc+1
    lda #0
    sta tmp5                // logorad 0-23
!row:
    ldx tmp5
    ldy div3,x
    lda (memSrc),y
    sta tmp0
    lda tmp5                // målposition: (rad/8)*16 + rad%8
    and #$18
    asl
    sta tmp1
    lda tmp5
    and #7
    ora tmp1
    tay
    lda tmp0                // vänstra halvan
    lsr
    lsr
    lsr
    lsr
    tax
    lda dblTab,x
    eor #$ff
    sta (memDst),y
    tya                     // högra halvan (nästa tecken)
    clc
    adc #8
    tay
    lda tmp0
    and #$0f
    tax
    lda dblTab,x
    eor #$ff
    sta (memDst),y
    inc tmp5
    lda tmp5
    cmp #LOGO_H
    bne !row-
    lda memDst              // nästa bokstav: 6 tecken längre fram
    clc
    adc #48
    sta memDst
    bcc !+
    inc memDst+1
!:  inc tmp4
    lda tmp4
    cmp #NUM_LOGO_LETTERS
    bne !letter-

    ldx #7                  // helt svart tecken
    lda #$ff
!loop:
    sta CHARSET + LOGO_SOLID*8,x
    dex
    bpl !loop-
    rts

// -------------------------------------------------------------------
// logoStart: slå på logon (anropas av showMenu efter rensning)
// -------------------------------------------------------------------
logoStart:
    ldx #119                // logoraderna: svart färg
    lda #COL_BLACK
!loop:
    sta COLORRAM + LOGO_ROW*40,x
    dex
    bpl !loop-
    lda #$ff
    sta logoCoarse          // tvinga omritning
    lda #SPR_FLAGBAR
    sta SCREEN_A+$3f8
    lda #COL_YELLOW
    sta $d027
    lda #LOGO_LINE0-1       // spriten börjar på linjen efter sitt y-värde
    sta $d001
    lda #$01
    sta $d017               // höjdförstorad
    sta $d01b               // bakom förgrunden
    lda #$fe
    sta $d01c               // sprite 0 hires
    jsr logoUpdate
    lda #$01
    sta $d015
    lda #IRQ_LINE_LOGO
    sta irqTopLine
    lda #1
    sta logoOn
    rts

// logoStop: tillbaka till vanliga inställningar (spel, namninmatning)
logoStop:
    lda #0
    sta logoOn
    sta $d015
    sta $d017
    sta $d01b
    lda #$ff
    sta $d01c
    lda #IRQ_LINE_TOP
    sta irqTopLine
    rts

// -------------------------------------------------------------------
// drawLogo: rita logoraderna med förskjutningen logoCoarse
// -------------------------------------------------------------------
drawLogo:
    ldx #39
    lda #LOGO_SOLID
!loop:
    sta SCREEN_A + LOGO_ROW*40,x
    sta SCREEN_A + LOGO_ROW*40+40,x
    sta SCREEN_A + LOGO_ROW*40+80,x
    dex
    bpl !loop-
    lda logoCoarse
    clc
    adc #1
    sta tmp0                // kolumn
    ldx #0
!ch:
    lda logoText,x
    bmi !space+
    sta tmp1                // första tecknet = 128 + 6*index
    asl
    adc tmp1
    asl
    clc
    adc #LOGO_CHAR0
    ldy tmp0
    sta SCREEN_A + LOGO_ROW*40,y
    clc
    adc #1
    sta SCREEN_A + LOGO_ROW*40+1,y
    adc #1
    sta SCREEN_A + LOGO_ROW*40+40,y
    adc #1
    sta SCREEN_A + LOGO_ROW*40+41,y
    adc #1
    sta SCREEN_A + LOGO_ROW*40+80,y
    adc #1
    sta SCREEN_A + LOGO_ROW*40+81,y
    inc tmp0
!space:
    inc tmp0
    inx
    cpx #LOGO_LEN
    bne !ch-
    rts

// -------------------------------------------------------------------
// logoUpdate: en gång per bildruta i menyn (i vblank)
// -------------------------------------------------------------------
logoUpdate:
    inc swayPhase
    inc flagPhase
    inc flagPhase
    lda bouncePhase
    clc
    adc #3
    sta bouncePhase

    // svängning i sidled: finscroll + hela tecken
    ldx swayPhase
    lda swayTab,x
    sta logoOff
    and #7
    ora #D016_HUD           // 38 kolumner döljer kanten som avslöjas
    sta logoD016
    lda logoOff
    lsr
    lsr
    lsr
    cmp logoCoarse
    beq !+
    sta logoCoarse
    jsr drawLogo
!:
    // vågräta balken: vilka rasterlinjer som är gula
    ldx bouncePhase
    lda bounceTab,x
    sta tmp0                // balkens översta rad 0-19
    ldx #0
!loop:
    txa
    sec
    sbc tmp0
    cmp #FLAG_BAR_H         // 0 <= rad-topp < höjd -> gul
    lda #COL_BLUE
    bcs !+
    lda #COL_YELLOW
!:  sta LOGO_LINES,x
    inx
    cpx #LOGO_H
    bne !loop-
    lda #COL_BLACK          // efter logon
    sta LOGO_LINES,x

    // lodräta balken: sprite x = 24 + 8 + logoOff + 2*flagX
    ldx flagPhase
    lda flagXTab,x
    asl
    sta tmp1
    lda #0
    rol
    sta tmp2
    lda tmp1
    clc
    adc logoOff
    sta tmp1
    bcc !+
    inc tmp2
!:  lda tmp1
    clc
    adc #32
    sta $d000
    lda tmp2
    adc #0
    sta $d010
    rts

// -------------------------------------------------------------------
// logoRaster: körs i raster-avbrottet på linje 55. Sätter finscroll för
// logoraderna och byter $d021 i början av varje rasterlinje i logon
// (i vänsterkanten, innan bilden börjar ritas).
// -------------------------------------------------------------------
logoRaster:
    lda logoD016
    sta $d016
    ldy #LOGO_LINE0
    ldx #0
!loop:
    lda LOGO_LINES,x        // färgen hämtas innan vi väntar
!wait:
    cpy $d012
    bne !wait-
    sta $d021
    iny
    inx
    cpx #LOGO_H+1
    bne !loop-
    lda #D016_MENU          // resten av menyn: 40 kolumner, ingen scroll
    sta $d016

    // Rulltexten på rad 6: egen finscroll för just de 8 rasterlinjerna.
    // Skrivningarna görs i början av linjen (i vänsterkanten).
    ldy #SCROLL_LINE0
    lda scrollD016
!wait:
    cpy $d012
    bne !wait-
    sta $d016
    ldy #SCROLL_LINE0+8
    lda #D016_MENU
!wait:
    cpy $d012
    bne !wait-
    sta $d016
    rts
