// ===================================================================
// Ljudeffekter (SID). Varje effekt: en röst, en vågform och ett
// frekvenssvep under ett antal bildrutor.
// ===================================================================

.const SID = $d400

initSid:
    ldx #$18
    lda #0
!loop:
    sta SID,x
    dex
    bpl !loop-
    lda #$08                // pulsbredd 50% på alla röster
    sta SID+$03
    sta SID+$0a
    sta SID+$11
    lda #$0f                // full volym
    sta SID+$18
    lda #0
    sta SFX_TIMER
    sta SFX_TIMER+1
    sta SFX_TIMER+2
    rts

// Effekttabell, 8 byte per effekt:
// röstoffset, röst, vågform, AD, SR, startfrekvens (hi), delta, längd
sfxTab:
    .byte 0,  0, $21, $08, $00, $30, $fc, 8      // SFX_SHOOT
    .byte 7,  1, $11, $06, $00, $0a, $02, 10     // SFX_JUMP
    .byte 14, 2, $81, $08, $00, $28, $fe, 10     // SFX_KILL
    .byte 14, 2, $81, $0b, $00, $10, $ff, 40     // SFX_DEATH
    .byte 7,  1, $11, $09, $00, $10, $03, 30     // SFX_PICKUP
    .byte 0,  0, $41, $04, $00, $20, $00, 3      // SFX_BLIP

voiceOfs: .byte 0, 7, 14

// playSfx: A = effektnummer. Bevarar X.
playSfx:
    stx tmp3
    asl
    asl
    asl
    tax
    ldy sfxTab+1,x
    lda sfxTab+5,x
    sta SFX_FREQ,y
    lda sfxTab+6,x
    sta SFX_DELTA,y
    lda sfxTab+7,x
    sta SFX_TIMER,y
    lda sfxTab+2,x
    sta SFX_WAVE,y
    ldy sfxTab,x
    lda #0
    sta SID+4,y             // gate av (starta om envelope)
    sta SID+0,y
    lda sfxTab+3,x
    sta SID+5,y
    lda sfxTab+4,x
    sta SID+6,y
    lda sfxTab+5,x
    sta SID+1,y
    lda sfxTab+2,x
    ora #1                  // gate på
    sta SID+4,y
    ldx tmp3
    rts

// Körs en gång per bildruta
soundUpdate:
    ldx #2
!loop:
    lda SFX_TIMER,x
    beq !next+
    dec SFX_TIMER,x
    ldy voiceOfs,x
    lda SFX_FREQ,x
    clc
    adc SFX_DELTA,x
    sta SFX_FREQ,x
    sta SID+1,y
    lda SFX_TIMER,x
    bne !next+
    lda SFX_WAVE,x          // gate av
    sta SID+4,y
!next:
    dex
    bpl !loop-
    rts
