// ===================================================================
//  FLIGHTY 64
//  Ett grottspel för Commodore 64 skrivet i KickAssembler.
//
//  Bygg:  ./build.sh   (eller: java -jar KickAss.jar src/main.asm)
//  Kör:   x64sc -autostart build/flighty64.prg
// ===================================================================

#import "gfx_const.asm"
#import "const.asm"

BasicUpstart2(start)

// -------------------------------------------------------------------
// Programstart
// -------------------------------------------------------------------
start:
    sei
    cld
    ldx #$ff
    txs
    lda #$35                // RAM överallt utom I/O
    sta $01

    lda #$7f                // stäng av CIA-avbrott
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d

    lda #<nmi               // RESTORE ska inte göra något
    sta $fffa
    lda #>nmi
    sta $fffb
    lda #<irq
    sta $fffe
    lda #>irq
    sta $ffff

    lda #$0b                // skärmen av under init
    sta $d011
    lda $dd00               // VIC-bank 1 ($4000-$7fff)
    and #$fc
    ora #$02
    sta $dd00

    jsr copyCharRom
    jsr buildLogoChars
    jsr copyGfx
    jsr initSid
    jsr initVic

    lda #$00                // båda joystickportarna som ingångar
    sta $dc02
    sta $dc03

    lda #$a5                // startvärde för slumptalen
    sta rngLo
    lda #$3c
    sta rngHi
    lda #$ff
    sta hsLast
    lda #0
    sta frameFlag
    sta joy
    sta irqStage
    sta logoOn
    lda #IRQ_LINE_TOP
    sta irqTopLine

    lda #D016_MENU
    sta hudD016
    sta nextD016
    lda #D018_A
    sta nextD018
    sta $d018

    lda #IRQ_LINE_BOTTOM    // raster-IRQ
    sta $d012
    lda #$1b                // skärm på, 25 rader, bit 8 av raster = 0
    sta $d011
    lda #$01
    sta $d01a
    lda #$ff
    sta $d019
    cli

// -------------------------------------------------------------------
// Huvudmeny
// -------------------------------------------------------------------
mainMenu:
    jsr showMenu
menuLoop:
    jsr waitFrame
    jsr soundUpdate
    jsr readJoy
    jsr rnd              // slumptalen beror på hur länge man väntar
    jsr menuAnimate
    lda joyNew
    and #JOY_FIRE
    beq menuLoop

    jsr startGame

// -------------------------------------------------------------------
// Spelets huvudloop - en varv per bildruta (50 Hz)
// -------------------------------------------------------------------
gameLoop:
    jsr waitFrame
    jsr applyFrame          // sprites + scrollregister (i vblank)
    jsr copyStep            // förbered den dolda skärmbufferten
    jsr soundUpdate
    jsr readJoy
    lda gameState
    cmp #ST_GAMEOVER
    beq gameOverTick

    jsr worldStep           // scrolla världen
    jsr playerUpdate
    jsr bulletsUpdate
    jsr monstersUpdate
    jsr spawnUpdate
    jsr collisions
    jsr buildSprites
    jsr hudUpdate
    jmp gameLoop

gameOverTick:
    lda goTimer
    cmp #120                // efter en stund kan man trycka fire
    bcs !wait+
    lda joyNew
    and #JOY_FIRE
    bne !done+
!wait:
    dec goTimer
    bne gameLoop
!done:
    jsr hsCheck
    lda hsPos
    bmi !menu+
    jsr enterName
!menu:
    jmp mainMenu

// -------------------------------------------------------------------
// Vänta på nästa bildruta (sätts av raster-IRQ längst ned)
// -------------------------------------------------------------------
waitFrame:
waitLoop:
    lda frameFlag
    beq waitLoop
    lda #0
    sta frameFlag
    inc frameCount
    rts

// -------------------------------------------------------------------
// Läs joystick i port 2. joy = nedtryckta, joyNew = nya denna frame
// -------------------------------------------------------------------
readJoy:
    lda joy
    sta joyPrev
    lda $dc00
    eor #$ff
    and #$1f
    sta joy
    eor joyPrev
    and joy
    sta joyNew
    rts

// -------------------------------------------------------------------
// 8-bitars slumptal från en 16-bitars Galois-LFSR. Bevarar X och Y.
// -------------------------------------------------------------------
rnd:
    lda #8
    sta rndCnt
    lda rngLo
!loop:
    asl
    rol rngHi
    bcc !+
    eor #$39
!:  dec rndCnt
    bne !loop-
    sta rngLo
    rts

// -------------------------------------------------------------------
// Kopiera tecken 0-63 (versaler, siffror, tecken) från tecken-ROM
// -------------------------------------------------------------------
copyCharRom:
    lda #$33                // tecken-ROM synligt på $d000
    sta $01
    ldx #0
!loop:
    lda $d000,x
    sta CHARSET,x
    lda $d100,x
    sta CHARSET+$100,x
    inx
    bne !loop-
    lda #$35
    sta $01
    rts

// -------------------------------------------------------------------
// Kopiera egna tecken och sprites till VIC-bank 1
// -------------------------------------------------------------------
copyGfx:
    lda #<gfxChars
    sta memSrc
    lda #>gfxChars
    sta memSrc+1
    lda #<(CHARSET + 64*8)
    sta memDst
    lda #>(CHARSET + 64*8)
    sta memDst+1
    lda #<GFX_CHARS_LEN
    sta memLen
    lda #>GFX_CHARS_LEN
    sta memLen+1
    jsr memCopy
    lda #<gfxSprites
    sta memSrc
    lda #>gfxSprites
    sta memSrc+1
    lda #<SPRITES
    sta memDst
    lda #>SPRITES
    sta memDst+1
    lda #<GFX_SPRITES_LEN
    sta memLen
    lda #>GFX_SPRITES_LEN
    sta memLen+1
    // fall igenom

// memCopy: kopiera memLen byte från (memSrc) till (memDst)
memCopy:
    ldy #0
!loop:
    lda memLen
    ora memLen+1
    beq !done+
    lda (memSrc),y
    sta (memDst),y
    inc memSrc
    bne !+
    inc memSrc+1
!:  inc memDst
    bne !+
    inc memDst+1
!:  lda memLen
    bne !+
    dec memLen+1
!:  dec memLen
    jmp !loop-
!done:
    rts

// -------------------------------------------------------------------
// Grundinställningar för VIC
// -------------------------------------------------------------------
initVic:
    lda #COL_BLACK
    sta $d020
    sta $d021
    jsr setRunColors
    lda #$ff                // alla sprites multicolor
    sta $d01c
    lda #0
    sta $d015
    sta $d017
    sta $d01d
    sta $d01b               // sprites framför grafiken
    lda #COL_WHITE
    sta $d025
    lda #COL_LIGHT_RED
    sta $d026
    rts

setRunColors:
    lda #COL_BROWN
    sta $d022
    lda #COL_DARK_GREY
    sta $d023
    rts

setFlyColors:
    lda #COL_BLUE
    sta $d022
    lda #COL_DARK_GREY
    sta $d023
    rts

// -------------------------------------------------------------------
// Starta en ny omgång
// -------------------------------------------------------------------
startGame:
    jsr logoStop
    lda #0
    sta $d015
    sta sprEnable
    sta score
    sta score+1
    sta score+2
    sta wave
    sta waveCol
    sta facing
    sta ringBase
    sta dispBuf
    sta needCopy
    sta pendingSwap
    sta genPtr
    sta pState
    sta vyLo
    sta vyHi
    sta pyLo
    sta landDelay
    sta shipExists
    sta fireCool
    sta B_ON
    sta B_ON+1
    ldx #NUM_MON-1
!loop:
    sta M_TYPE,x
    dex
    bpl !loop-

    lda #ST_PLAY
    sta gameState
    lda #PH_RUN
    sta phase
    lda #3
    sta lives
    lda #1
    sta level
    lda #2
    sta scrollSpeed
    lda #7
    sta fine
    lda #120
    sta spawnTimer
    lda #90
    sta invuln

    jsr setRunColors
    lda #CAVE_CR_RUN
    jsr clearGameScreens
    jsr initGenerator

    // generera 41 kolumner och rita de 40 första på skärm A
    ldx #41
!gen:
    jsr genColumn
    dex
    bne !gen-
    ldx #0
!draw:
    txa
    clc
    adc #<(SCREEN_A + PLAY_TOP*40)
    sta colPtr
    lda #>(SCREEN_A + PLAY_TOP*40)
    adc #0
    sta colPtr+1
    txa
    tay
    stx tmp3
    jsr drawRingColumn
    ldx tmp3
    inx
    cpx #40
    bne !draw-

    // skärm B = skärm A förskjuten ett tecken + kolumn 40
    lda #40
    sta newColIdx
    lda #2
    sta needCopy
    jsr copyFinish

    jsr setMaxMon
    jsr showWaveMsg

    lda #60
    sta px
    jsr probeColumns
    lda floorTop
    sec
    sbc #P_H
    sta py
    lda #1
    sta onGround

    lda #D016_HUD
    sta hudD016
    lda fine
    ora #D016_GAME
    sta pendingD016
    lda #D018_A
    sta pendingD018
    jsr buildSprites
    rts

#import "irq.asm"
#import "screen.asm"
#import "cave.asm"
#import "player.asm"
#import "enemies.asm"
#import "sound.asm"
#import "menu.asm"
#import "logo.asm"
#import "highscore.asm"

// Grafikdata (genererad av tools/make_gfx.py)
#import "gfx_data.asm"
