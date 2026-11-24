// ===================================================================
// Startskärmens logo: "SOFTWARE OF SWEDEN"
//
//  * Stora bokstäver (16x24 px) byggs vid start av C64:ans egna
//    ROM-tecken: varje pixel blir 2x3 pixlar. Tecknen är inverterade,
//    så bokstaven är ett "hål" där bakgrundsfärgen ($d021) syns.
//  * Bokstäverna böljar i sidled: varje rasterlinje får en egen finscroll
//    ($d016), så vänsterkanten följer en sinuskurva som vandrar uppåt.
//  * Genom hålen syns en svensk flagga. Korset rör sig som en boll sedd
//    från sidan, som studsar mot golvet och mot väggarna:
//      - den vågräta gula balken = $d021 byts till gult på några
//        rasterlinjer. Den följer parabler (konstant tyngdkraft) i en
//        serie studsar som blir lägre och sedan får en ny knuff, som en
//        dribblad basketboll (bounceTop/bounceH). I golvkontakten trycks
//        balken ihop, nära golvet sträcks den ut.
//      - den lodräta gula balken = sprite 0 bakom förgrunden ($d01b),
//        så den syns bara genom bokstäverna. Den går med jämn fart i
//        sidled och vänder tvärt vid textens kanter, som mot en vägg.
//        Vid väggen trycks den ihop (smalare sprite) några bildrutor.
// ===================================================================

.encoding "screencode_upper"

.const LOGO_ROW    = 1            // teckenrad 1-3
.const LOGO_LINE0  = 59           // första rasterlinjen (51 + 8*1)
.const LOGO_H      = 24           // rasterlinjer
.const LOGO_CHAR0  = 128          // logotecknen: 128-187
.const LOGO_SOLID  = 188          // helt svart tecken runt texten
.const LOGO_LEN    = 18           // tecken i texten
.const NUM_LOGO_LETTERS = 10
.const LOGO_COL    = 2            // textens första kolumn
.const WAVE_STEP   = 3            // vågens fas per rasterlinje (64 = en period)
// Lodräta balkens väggar (sprite-x för balkens vänsterkant): textens
// vänsterkant (kolumn + halva vågen) och 272-6 pixlar längre åt höger
.const FLAG_XMIN   = 24 + 8*LOGO_COL + 4
.const FLAG_XMAX   = FLAG_XMIN + 266
.const FLAG_SQUASH = 3            // bildrutor ihoptryckt mot väggen
// Rasterloopen börjar på linjen före logon. Tabellerna LOGO_LINES och
// LOGO_D016 indexeras med rasterlinjen: post 0 = linje 58, 1-24 = logon,
// 25-26 = linje 83-84 (under logon).
.const LOGO_RL0    = LOGO_LINE0-1
.const LOGO_RLEND  = LOGO_LINE0+LOGO_H+2   // loopen slutar efter linje 84

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
    lda #0                  // nivå 3:s raster ska inte köras i menyn
    sta tdOn
    jsr setSprShared
    ldx #119                // logoraderna: svart färg
    lda #COL_BLACK
!loop:
    sta COLORRAM + LOGO_ROW*40,x
    dex
    bpl !loop-
    jsr drawLogo
    lda #COL_BLACK          // linjen före och linjerna efter logon
    sta LOGO_LINES
    sta LOGO_LINES+LOGO_H+1
    sta LOGO_LINES+LOGO_H+2
    lda #D016_HUD           // 38 kolumner döljer kanten som avslöjas
    sta LOGO_D016
    lda #D016_MENU          // resten av menyn: 40 kolumner, ingen scroll
    sta LOGO_D016+LOGO_H+1
    sta LOGO_D016+LOGO_H+2
    lda #<FLAG_XMIN         // korset börjar vid vänster vägg, på golvet
    sta flagXLo
    lda #>FLAG_XMIN
    sta flagXHi
    lda #0
    sta flagDir
    sta flagSquash
    sta bouncePhase
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
    sta tdOn
    sta $d015
    sta $d017
    sta $d01b
    lda #$ff
    sta $d01c
    lda #IRQ_LINE_TOP
    sta irqTopLine
    rts

// -------------------------------------------------------------------
// drawLogo: rita logoraderna (texten börjar i kolumn LOGO_COL)
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
    lda #LOGO_COL
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
    inc wavePhase
    // bokstävernas våg: egen finscroll för varje rasterlinje
    lda wavePhase
    sta tmp0
    ldx #0
!loop:
    lda tmp0
    and #63
    tay
    lda waveTab,y
    ora #D016_HUD
    sta LOGO_D016+1,x
    lda tmp0
    clc
    adc #WAVE_STEP
    sta tmp0
    inx
    cpx #LOGO_H
    bne !loop-

    // vågräta balken: nästa bildruta i studsserien
    ldx bouncePhase
    lda bounceTop,x
    sta tmp0                // översta raden 0-23
    lda bounceH,x
    sta tmp2                // tjocklek i rader
    inx
    cpx #BOUNCE_LEN
    bne !+
    ldx #0
!:  stx bouncePhase
    ldx #0                  // vilka rasterlinjer som är gula
!loop:
    txa
    sec
    sbc tmp0
    cmp tmp2                // 0 <= rad-topp < tjocklek -> gul
    lda #COL_BLUE
    bcs !+
    lda #COL_YELLOW
!:  sta LOGO_LINES+1,x
    inx
    cpx #LOGO_H
    bne !loop-

    // lodräta balken: jämn fart, vänder vid väggarna
    lda flagSquash
    beq !move+
    dec flagSquash          // står still mot väggen
    jmp !show+
!move:
    lda flagDir
    bne !left+
    inc flagXLo             // åt höger
    bne !+
    inc flagXHi
!:  lda flagXLo
    cmp #<FLAG_XMAX
    bne !show+
    lda flagXHi
    cmp #>FLAG_XMAX
    bne !show+
    lda #1                  // högra väggen
    bne !hit+
!left:
    lda flagXLo             // åt vänster
    bne !+
    dec flagXHi
!:  dec flagXLo
    lda flagXLo
    cmp #<FLAG_XMIN
    bne !show+
    lda flagXHi
    cmp #>FLAG_XMIN
    bne !show+
    lda #0                  // vänstra väggen
!hit:
    sta flagDir             // vänd
    lda #FLAG_SQUASH
    sta flagSquash
!show:
    // ihoptryckt: 4 pixlar bred, mot den vägg den just träffat
    // (högra väggen: flyttad 2 pixlar så att högerkanten ligger kvar)
    lda #SPR_FLAGBAR
    ldx #0
    ldy flagSquash
    beq !put+
    lda #SPR_FLAGBAR4
    ldy flagDir
    beq !put+
    ldx #2
!put:
    sta SCREEN_A+$3f8
    stx tmp1
    lda flagXLo
    clc
    adc tmp1
    sta $d000
    lda flagXHi
    adc #0
    sta $d010
    rts

// -------------------------------------------------------------------
// logoRaster: körs i raster-avbrottet på linje 55. Skriver $d016
// (bokstävernas våg) och $d021 (flaggans vågräta balk) för varje
// rasterlinje i logon, linje 58-84. (Uppmätt i VICE x64sc.)
//
// Vanliga linjer: värdena skrivs direkt när linjen börjar. $d016 först
// (cykel ca 6-12): en ändring av finscrollen medan bilden ritas ger
// lösa pixlar i bakgrundsfärgen, så den måste ske innan bildfönstret
// börjar (cykel ca 16). $d021 hinner sedan till cykel ca 16; bakgrunden
// syns inte förrän i bokstäverna, som börjar i kolumn 2.
//
// Badlines (första linjen i varje teckenrad: 59, 67, 75, 83): där står
// CPU:n still från cykel ca 15 till 55, och loopen hinner inte ikapp
// till linjen efter. Därför, på linjen före en badline:
//   1. skriv linjens egna värden som vanligt,
//   2. vänta till högerkanten och skriv badlinens värden. Fönstret är
//      smalt: efter bildfönstret (cykel ca 54) men före badlinens stopp
//      (CPU:n stannar vid första läsning från cykel 12). Skrivs $d021 för
//      sent stannar den till cykel 55, och hela badlinen får förra
//      linjens färg,
//   3. lägg fram värdena för linjen efter badlinen. Skrivningen ska ske
//      efter stoppet, i badlinens högerkant; skulle sty hinna läsa klart
//      före cykel 12 får badlinen i stället nästa linjes värden.
//      Uppmätt i VICE (sprite 0:s DMA i slutet av varje linje medräknad):
//      badlinens $d021 skrivs i badlinens cykel 2-8, och sty för linjen
//      efter läser tidigast i cykel 12+3. Marginal ca 3 cykler åt båda
//      hållen; mer går inte med rasterjittret på 7 cykler,
//   4. hoppa över båda linjerna.
//
// X = rasterlinjen, A/Y = färg/$d016 för den linje som väntas på.
// -------------------------------------------------------------------
.const LL = LOGO_LINES - LOGO_RL0   // tabellerna indexerade med rasterlinje
.const LD = LOGO_D016 - LOGO_RL0

logoRaster:
    lda #D016_HUD
    sta $d016
    ldx #LOGO_RL0
    lda LL,x
    ldy LD,x
!line:
!wait:
    cpx $d012
    bne !wait-
    sty $d016               // början av linjen, före bildfönstret
    sta $d021
    txa
    and #7
    cmp #2                  // linjen före en badline (yscroll = 3)?
    bne !next+
    ldy #5                  // vänta till högerkanten
!delay:
    dey
    bne !delay-
    lda LL+1,x              // badlinens värden
    ldy LD+1,x
    sty $d016
    sta $d021
    inx                     // X = badlinen
    lda LL+1,x              // linjen efter badlinen: CPU:n stoppas under
    ldy LD+1,x              // de här instruktionerna, så skrivningen
    sty $d016               // sker först i badlinens högerkant
    sta $d021
    inx
!next:
    inx
    lda LL,x
    ldy LD,x
    cpx #LOGO_RLEND
    bne !line-

    // Rulltexten på rad 6: egen finscroll för just de 8 rasterlinjerna.
    // Radens första linje (99) och linjen efter (107) är badlines, så
    // värdena skrivs i högerkanten på linjen före, som för logon.
    ldx #SCROLL_LINE0-1
    lda scrollD016
    jsr d016AtLineEnd
    ldx #SCROLL_LINE0+8-1
    lda #D016_MENU
    // (fortsätter i d016AtLineEnd)

// -------------------------------------------------------------------
// d016AtLineEnd: vänta på rasterlinje X och skriv A till $d016 i
// högerkanten, efter bildfönstret men före nästa linjes badline-stopp
// (CPU:n stannar vid första läsning från cykel 12). Uppmätt i VICE:
// skrivningen sker i cykel ca 59-66 (sprite 0:s DMA i slutet av
// linjen kan skjuta den några cykler). Marginal ca 5 cykler åt båda
// hållen.
// -------------------------------------------------------------------
d016AtLineEnd:
!wait:
    cpx $d012
    bne !wait-
    ldy #10
!delay:
    dey
    bne !delay-
    nop
    sta $d016
    rts
