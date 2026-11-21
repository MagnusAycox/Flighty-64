// ===================================================================
// Topplistan (10 platser) och inmatning av namn
// ===================================================================

.encoding "screencode_upper"

// Poäng: 3 byte BCD per plats, mest signifikant först
hsScore:
    .byte $00, $50, $00
    .byte $00, $45, $00
    .byte $00, $40, $00
    .byte $00, $35, $00
    .byte $00, $30, $00
    .byte $00, $25, $00
    .byte $00, $20, $00
    .byte $00, $15, $00
    .byte $00, $10, $00
    .byte $00, $05, $00
// Namn: 3 tecken (skärmkoder) per plats
hsName:
    .text "ACE"
    .text "BOB"
    .text "C64"
    .text "SID"
    .text "VIC"
    .text "JOY"
    .text "ZAP"
    .text "MAX"
    .text "KAT"
    .text "ROM"

// Tecken man kan välja i namnet
letters:
    .text "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-! "
.const NUM_LETTERS = 40

nameText:
    .byte 5, 12, COL_YELLOW
    .text "CONGRATULATIONS!"
    .byte 0
    .byte 8, 10, COL_WHITE
    .text "YOU MADE THE TOP 10"
    .byte 0
    .byte 11, 12, COL_LIGHT_BLUE
    .text "ENTER YOUR NAME"
    .byte 0
    .byte 18, 6, COL_GREY
    .text "UP/DOWN = LETTER   FIRE = NEXT"
    .byte 0
    .byte $ff

// -------------------------------------------------------------------
// hsCheck: hsPos = platsen poängen hamnar på (0-9), $ff = ingen plats
// -------------------------------------------------------------------
hsCheck:
    ldx #0
    ldy #0
!loop:
    lda score
    cmp hsScore,y
    bcc !next+
    bne !found+
    lda score+1
    cmp hsScore+1,y
    bcc !next+
    bne !found+
    lda score+2
    cmp hsScore+2,y
    bcc !next+
    bne !found+
!next:
    iny
    iny
    iny
    inx
    cpx #10
    bne !loop-
    ldx #$ff
!found:
    stx hsPos
    rts

// -------------------------------------------------------------------
// hsInsert: flytta ned sämre resultat och lägg in poängen på hsPos
// -------------------------------------------------------------------
hsInsert:
    lda hsPos
    asl
    clc
    adc hsPos
    sta tmp0                // plats*3
    ldx #26
!loop:
    cpx tmp0
    bcc !done+
    lda hsScore,x
    sta hsScore+3,x
    lda hsName,x
    sta hsName+3,x
    dex
    bpl !loop-
!done:
    ldx tmp0
    lda score
    sta hsScore,x
    lda score+1
    sta hsScore+1,x
    lda score+2
    sta hsScore+2,x
    rts

// -------------------------------------------------------------------
// enterName: låt spelaren skriva in tre tecken med joysticken
// -------------------------------------------------------------------
.const NAME_ROW = 14
.const NAME_COL = 17

enterName:
    jsr hsInsert
    lda #0
    sta $d015
    sta sprEnable
    sta nameCursor
    sta nameBuf
    sta nameBuf+1
    sta nameBuf+2
    sta repeatTimer
    lda #D016_MENU
    sta hudD016
    sta nextD016
    lda #D018_A
    sta nextD018
    lda #COL_WHITE
    sta clearColor
    jsr clearScreens
    lda #<nameText
    ldx #>nameText
    jsr printList

!frame:
    jsr waitFrame
    jsr soundUpdate
    jsr readJoy

    // upp/ned med autorepetition
    lda joy
    and #JOY_UP+JOY_DOWN
    bne !held+
    lda #0
    sta repeatTimer
    jmp !fire+
!held:
    lda repeatTimer
    beq !step+
    dec repeatTimer
    jmp !fire+
!step:
    lda joyNew
    and #JOY_UP+JOY_DOWN
    beq !rep+
    lda #14                 // första fördröjningen
    bne !setrep+
!rep:
    lda #5
!setrep:
    sta repeatTimer
    ldx nameCursor
    lda joy
    and #JOY_UP
    beq !down+
    inc nameBuf,x
    lda nameBuf,x
    cmp #NUM_LETTERS
    bcc !snd+
    lda #0
    sta nameBuf,x
    jmp !snd+
!down:
    dec nameBuf,x
    bpl !snd+
    lda #NUM_LETTERS-1
    sta nameBuf,x
!snd:
    lda #SFX_BLIP
    jsr playSfx

!fire:
    lda joyNew
    and #JOY_FIRE
    beq !draw+
    lda #SFX_SHOOT
    jsr playSfx
    inc nameCursor
    lda nameCursor
    cmp #3
    beq !finish+

!draw:
    ldx #0
!loop:
    ldy nameBuf,x
    lda letters,y
    pha
    txa
    asl
    tay
    pla
    sta SCREEN_A + NAME_ROW*40 + NAME_COL,y
    lda #COL_WHITE
    cpx nameCursor
    bne !+
    lda frameCount          // markören blinkar
    and #8
    beq !+
    lda #COL_YELLOW
!:  sta COLORRAM + NAME_ROW*40 + NAME_COL,y
    inx
    cpx #3
    bne !loop-
    jmp !frame-

!finish:
    lda hsPos
    asl
    clc
    adc hsPos
    tax
    ldy nameBuf
    lda letters,y
    sta hsName,x
    ldy nameBuf+1
    lda letters,y
    sta hsName+1,x
    ldy nameBuf+2
    lda letters,y
    sta hsName+2,x
    lda hsPos
    sta hsLast
    rts
