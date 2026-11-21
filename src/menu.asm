// ===================================================================
// Huvudmeny med topplistan, samt "GAME OVER"
// ===================================================================

.encoding "screencode_upper"

.const MENU_HS_ROW = 9
.const MENU_HS_COL = 12

menuText:
    // rad 1-3: logon "SOFTWARE OF SWEDEN" (logo.asm)
    .byte 5, 10, COL_YELLOW
    .text "F L I G H T Y   6 4"
    .byte 0
    .byte 7, 11, COL_WHITE
    .text "TOP 10 HIGH SCORES"
    .byte 0
    .byte 20, 10, COL_LIGHT_GREEN
    .text "PRESS FIRE TO START"
    .byte 0
    .byte 22, 3, COL_GREY
    .text "JOYSTICK PORT 2  UP=JUMP  FIRE=SHOOT"
    .byte 0
    .byte 24, 2, COL_LIGHT_BLUE
    .text "RUN, JUMP AND FLY THROUGH THE CAVES"
    .byte 0
    .byte $ff

gameOverText:
    .byte 11, 13, COL_WHITE
    .text "             "
    .byte 0
    .byte 12, 13, COL_YELLOW
    .text "  GAME OVER  "
    .byte 0
    .byte 13, 13, COL_WHITE
    .text "             "
    .byte 0
    .byte $ff

titleColors:
    .byte COL_YELLOW, COL_ORANGE, COL_LIGHT_RED, COL_RED, COL_PURPLE, COL_LIGHT_BLUE, COL_CYAN, COL_LIGHT_GREEN

showMenu:
    lda #ST_MENU
    sta gameState
    lda #0
    sta sprEnable
    sta $d015
    lda #D016_MENU
    sta hudD016
    sta nextD016
    lda #D018_A
    sta nextD018
    lda #COL_WHITE
    sta clearColor
    jsr clearScreens
    lda #<menuText
    ldx #>menuText
    jsr printList
    jsr printHighscores
    jmp logoStart

// Färgcykling på titeln och blinkande "PRESS FIRE"
menuAnimate:
    jsr logoUpdate
    inc menuTimer
    lda menuTimer
    and #3
    bne !done+
    lda menuTimer
    lsr
    lsr
    sta tmp0
    ldx #0
!loop:
    txa
    clc
    adc tmp0
    lsr
    and #7
    tay
    lda titleColors,y
    sta COLORRAM+5*40+10,x
    inx
    cpx #19
    bne !loop-
    lda menuTimer
    and #32
    beq !on+
    lda #COL_BLACK
    jmp !set+
!on:
    lda #COL_LIGHT_GREEN
!set:
    ldx #18
!loop:
    sta COLORRAM+20*40+10,x
    dex
    bpl !loop-
!done:
    rts

// -------------------------------------------------------------------
// Skriv ut topplistan: " 1. ABC   012345"
// -------------------------------------------------------------------
printHighscores:
    lda #0
    sta tmp4                // plats 0-9
!entry:
    lda tmp4
    clc
    adc #MENU_HS_ROW
    tax
    lda rowLo,x
    clc
    adc #MENU_HS_COL
    sta scrPtr
    sta colPtr2
    lda rowHi,x
    adc #0
    sta scrPtr+1
    clc
    adc #COLOR_OFS_HI
    sta colPtr2+1

    // färg: senaste inskrivna namnet i gult
    ldx #COL_WHITE
    lda tmp4
    cmp hsLast
    bne !+
    ldx #COL_YELLOW
!:  txa
    ldy #15
!loop:
    sta (colPtr2),y
    dey
    bpl !loop-

    // placering
    ldy #0
    lda tmp4
    cmp #9
    bne !single+
    lda #$31                // "10"
    sta (scrPtr),y
    iny
    lda #$30
    sta (scrPtr),y
    jmp !dot+
!single:
    lda #32
    sta (scrPtr),y
    iny
    lda tmp4
    clc
    adc #$31
    sta (scrPtr),y
!dot:
    iny
    lda #$2e                // "."
    sta (scrPtr),y

    // namn
    lda tmp4
    asl
    clc
    adc tmp4
    tax                     // X = plats*3
    stx tmp5
    ldy #4
    lda hsName,x
    sta (scrPtr),y
    iny
    lda hsName+1,x
    sta (scrPtr),y
    iny
    lda hsName+2,x
    sta (scrPtr),y

    // poäng (kolumn 10-15)
    ldy #10
!digit:
    lda hsScore,x
    lsr
    lsr
    lsr
    lsr
    ora #$30
    sta (scrPtr),y
    iny
    lda hsScore,x
    and #$0f
    ora #$30
    sta (scrPtr),y
    iny
    inx
    cpy #16
    bne !digit-

    inc tmp4
    lda tmp4
    cmp #10
    beq !done+
    jmp !entry-
!done:
    rts

// -------------------------------------------------------------------
// Game over: frys allt och visa text
// -------------------------------------------------------------------
startGameOver:
    lda #ST_GAMEOVER
    sta gameState
    lda #200
    sta goTimer
    lda #0
    sta sprEnable
    lda #<gameOverText
    ldx #>gameOverText
    jmp printList
