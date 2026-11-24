// ===================================================================
// Nivå 3: fiender, skott, granater, lådor och porten
//
//  Våg 1: soldaterna skjuter rakt nedåt
//  Våg 2: också snett nedåt (mot spelaren); lådor med 4 granater
//  Våg 3: soldaterna kastar också granater mot spelaren
//  Våg 4: taggtråd som inte får röras
//  Sist:  muren med porten - tre granatträffar spränger den
//
//  Allt som ligger på marken (fiender, skott, granater, explosioner)
//  har skärmkoordinater och flyttas en pixel nedåt när banan scrollar.
// ===================================================================

.const NUM_E      = 5
.const NUM_EB     = 4
.const NUM_FX     = 2
.const E_TYPE     = $cd00
.const E_XL       = $cd08
.const E_XH       = $cd10
.const E_Y        = $cd18
.const E_ST       = $cd20
.const E_TM       = $cd28
.const E_DIR      = $cd30         // -1, 0, 1
.const E_TY       = $cd38         // y där soldaten stannar och skjuter
.const E_SHOTS    = $cd40
.const E_POSE     = $cd48         // > 0: visar "kastar"-bilden
.const EB_ON      = $cd50
.const EB_XL      = $cd54
.const EB_XH      = $cd58
.const EB_Y       = $cd5c
.const EB_DX      = $cd60
.const EB_DY      = $cd64
.const FX_T       = $cd70
.const FX_XL      = $cd72
.const FX_XH      = $cd74
.const FX_Y       = $cd76

.const ET_SOLDIER = 1
.const ET_BOOM    = 2
.const ES_WALK    = 0
.const ES_AIM     = 1
.const ES_LEAVE   = 2

.const GRENADE_T  = 36            // spelarens granat: bildrutor i luften
.const GATE_CX    = 184           // portens mitt i sprite-x
.const GATE_HITS  = 3

// Granatens höjd över marken under flygningen (parabel, 0-20 pixlar)
grenadeH:
    .byte 0, 2, 4, 6, 8, 10, 11, 13, 14, 15, 16, 17, 18, 19, 19, 20, 20, 20, 20
    .byte 20, 20, 20, 19, 19, 18, 17, 16, 15, 14, 13, 11, 10, 8, 6, 4, 2, 0

msgGate:
    .byte 0, 11, COL_YELLOW
    .text "BLOW UP THE GATE!"
    .byte 0
    .byte $ff

// -------------------------------------------------------------------
// Nollställ allt (tdStart)
// -------------------------------------------------------------------
tdObjectsInit:
    lda #0
    ldx #NUM_E-1
!loop:
    sta E_TYPE,x
    dex
    bpl !loop-
    ldx #NUM_EB-1
!loop:
    sta EB_ON,x
    dex
    bpl !loop-
    sta FX_T
    sta FX_T+1
    sta pgOn
    sta egOn
    sta tdGateGen
    sta tdGateHP
    sta tdCrateCool
    sta tdWireCool
    sta throwCool
    sta vsN
    sta mpN
    sta maN
    lda #120
    sta tdSpawnT
    rts

// -------------------------------------------------------------------
// En bildruta: allt utom spelaren själv
// -------------------------------------------------------------------
tdObjectsUpdate:
    jsr tdSpawn
    jsr tdEnemies
    jsr tdEnemyBullets
    jsr tdPlayerGrenade
    jsr tdEnemyGrenade
    jsr tdFx
    jsr tdGateCrate
    jmp tdCollide

// Banan scrollade en pixel: allt på marken följer med
tdShiftObjects:
    ldx #NUM_E-1
!loop:
    lda E_TYPE,x
    beq !+
    inc E_Y,x
    lda E_Y,x
    cmp #240                // ut nedtill
    bcc !+
    lda #0
    sta E_TYPE,x
!:  dex
    bpl !loop-
    ldx #NUM_EB-1
!loop:
    lda EB_ON,x
    beq !+
    inc EB_Y,x
    lda EB_Y,x
    cmp #244
    bcc !+
    lda #0
    sta EB_ON,x
!:  dex
    bpl !loop-
    ldx #NUM_FX-1
!loop:
    inc FX_Y,x
    lda FX_Y,x
    cmp #244
    bcc !+
    lda #0
    sta FX_T,x
!:  dex
    bpl !loop-
    inc pgY
    inc egY
    inc egTY
    lda egTY                // målet för fiendens granat får inte slå runt
    cmp #250
    bcc !+
    dec egTY
!:  rts

// -------------------------------------------------------------------
// Nya soldater uppifrån (vid porten: ut genom porten)
// -------------------------------------------------------------------
tdSpawn:
    lda tdState
    cmp #TDS_PLAY
    beq !ok+
    cmp #TDS_GATE
    beq !ok+
    rts
!ok:
    dec tdSpawnT
    beq !+
    rts
!:  lda wave                // tid till nästa: 70 - 10*våg + slump(0-31)
    asl
    sta tmp6
    asl
    asl
    clc
    adc tmp6
    sta tmp6
    lda #70
    sec
    sbc tmp6
    sta tmp6
    jsr rnd
    and #31
    clc
    adc tmp6
    sta tdSpawnT

    lda wave                // max antal: 2 + våg (+1 vid porten, +1 från nivå 6)
    clc
    adc #2
    ldx tdState
    cpx #TDS_GATE
    bne !+
    clc
    adc #1
!:  ldx level
    cpx #6
    bcc !+
    clc
    adc #1
!:  cmp #NUM_E+1
    bcc !+
    lda #NUM_E
!:  sta maxE
    lda #0                  // räkna soldater
    sta tmp6
    ldx #NUM_E-1
!loop:
    lda E_TYPE,x
    cmp #ET_SOLDIER
    bne !+
    inc tmp6
!:  dex
    bpl !loop-
    lda tmp6
    cmp maxE
    bcc !+
    rts
!:  ldx #NUM_E-1            // ledig plats
!loop:
    lda E_TYPE,x
    beq !found+
    dex
    bpl !loop-
    rts
!found:
    lda tdState
    cmp #TDS_GATE
    bne !top+
    jsr rnd                 // ut genom porten
    and #15
    clc
    adc #GATE_CX-20
    sta E_XL,x
    lda #0
    sta E_XH,x
    lda tdGateY
    clc
    adc #4
    sta E_Y,x
    jsr rnd
    and #31
    clc
    adc #30
    adc tdGateY
    sta E_TY,x
    jmp !init+
!top:
    jsr rnd                 // uppifrån, någonstans på bredden
    clc
    adc #40
    sta E_XL,x
    lda #0
    adc #0
    sta E_XH,x
    lda #58
    sta E_Y,x
    jsr rnd
    and #63
    clc
    adc #90
    sta E_TY,x
!init:
    lda #0
    sta tmp6                // står den på ett hinder? då ingen soldat nu
    sta tmp7
    jsr tdEnemyTry
    bcc !+
    rts
!:  lda #ET_SOLDIER
    sta E_TYPE,x
    lda #ES_WALK
    sta E_ST,x
    lda #0
    sta E_TM,x
    sta E_POSE,x
    jsr tdRandomDir
    jsr rnd
    and #1
    clc
    adc #2
    sta E_SHOTS,x
    rts

tdRandomDir:
    jsr rnd
    and #3
    cmp #3
    bne !+
    lda #1
!:  sec
    sbc #1                  // -1, 0, 1
    sta E_DIR,x
    rts

// -------------------------------------------------------------------
// Soldaterna
// -------------------------------------------------------------------
tdEnemies:
    ldx #NUM_E-1
!loop:
    lda E_TYPE,x
    beq !next+
    cmp #ET_BOOM
    bne !soldier+
    dec E_TM,x
    bne !next+
    lda #0
    sta E_TYPE,x
    beq !next+
!soldier:
    jsr tdEnemyAI
!next:
    dex
    bpl !loop-
    rts

tdEnemyAI:
    lda E_POSE,x
    beq !+
    dec E_POSE,x
!:  lda E_ST,x
    cmp #ES_AIM
    bne !walk+
    dec E_TM,x              // står still och skjuter
    bne !rts+
    lda E_SHOTS,x
    beq !leave+
    dec E_SHOTS,x
    jsr tdEnemyShoot
    lda wave
    asl
    asl
    asl
    sta tmp6
    lda #56
    sec
    sbc tmp6
    sta tmp6
    jsr rnd
    and #15
    clc
    adc tmp6
    sta E_TM,x
!rts:
    rts
!leave:
    lda #ES_LEAVE
    sta E_ST,x
    jmp tdRandomDir

!walk:
    txa                     // går en pixel varannan bildruta (hälften av
    eor frameCount          // soldaterna i taget, så att CPU-tiden sprids)
    and #1
    bne !rts-
    jsr rnd                 // byter riktning ibland
    cmp #6
    bcs !+
    jsr tdRandomDir
!:  lda E_DIR,x             // snett/rakt nedåt
    sta tmp6
    lda #1
    sta tmp7
    jsr tdEnemyTry
    bcc !moved+
    lda #0                  // rakt nedåt
    sta tmp6
    jsr tdEnemyTry
    bcc !moved+
    lda #0                  // åt sidan
    sta tmp7
    lda #1
    sta tmp6
    jsr tdEnemyTry
    bcc !moved+
    lda #$ff
    sta tmp6
    jsr tdEnemyTry
    bcc !moved+
    jmp tdRandomDir         // fast: prova en ny riktning nästa gång
!moved:
    lda E_ST,x
    cmp #ES_WALK
    bne !exit+
    lda E_Y,x
    cmp E_TY,x
    bcc !exit+
    lda #ES_AIM             // framme: stanna och skjut
    sta E_ST,x
    lda #20
    sta E_TM,x
!exit:
    lda E_Y,x               // ut nedtill
    cmp #236
    bcc !rts+
    lda #0
    sta E_TYPE,x
!rts:
    rts

// tdEnemyTry: flytta soldat X med (tmp6, tmp7) = (dx -1..1, dy 0..1)
// om platsen är fri från hinder och taggtråd. C=1 om det inte gick.
tdEnemyTry:
    lda E_XL,x
    clc
    adc tmp6
    sta tdTX
    lda tmp6                // teckenutvidga dx
    bpl !+
    lda #$ff
    bne !hi+
!:  lda #0
!hi:
    adc E_XH,x
    sta tdTXH
    bmi !no+                // utanför skärmen
    bne !+
    lda tdTX
    cmp #24
    bcc !no+
    bcs !y+
!:  lda tdTX
    cmp #<TD_MAX_X
    bcs !no+
!y: lda E_Y,x
    clc
    adc tmp7
    sta tdTY
    // Platsen innan var fri, så bara hörnen som flyttas in i nya tecken
    // behöver kollas (hindren är 16 pixlar breda). Står den still (vid
    // start) kollas alla fyra.
    lda tmp6
    ora tmp7
    bne !+
    lda #6
    ldy #12
    jsr tdBadAt
    bcs !no+
    lda #17
    ldy #12
    jsr tdBadAt
    bcs !no+
    lda #0
    sta tmp7
    beq !bottom+
!:  lda tmp7
    beq !side+
!bottom:
    lda #6                  // nedåt: nederkanten
    ldy #16
    jsr tdBadAt
    bcs !no+
    lda #17
    ldy #16
    jsr tdBadAt
    bcs !no+
!side:
    lda tmp6
    beq !ok+
    bmi !l+
    lda #17                 // åt höger: högerkanten
    bne !+
!l: lda #6                  // åt vänster: vänsterkanten
!:  pha
    ldy #12
    jsr tdBadAt
    pla
    bcs !no+
    ldy tmp7                // nederkanten är redan kollad om den gick nedåt
    bne !ok+
    ldy #16
    jsr tdBadAt
    bcs !no+
!ok:
    lda tdTX
    sta E_XL,x
    lda tdTXH
    sta E_XH,x
    lda tdTY
    sta E_Y,x
    clc
    rts
!no:
    sec
    rts

// tdBadAt: C=1 om tecknet vid (tdTX/tdTXH + A, tdTY + Y) är hinder eller taggtråd
tdBadAt:
    clc
    adc tdTX
    sta cxLo
    lda tdTXH
    adc #0
    sta cxHi
    tya
    clc
    adc tdTY
    jsr tdCharAt
    cmp #TD_SOLID_FIRST
    bcs !yes+
    cmp #TD_WIRE_FIRST
    bcc !no+
    cmp #TD_WIRE_FIRST+8
    bcs !no+
!yes:
    sec
    rts
!no:
    clc
    rts

// -------------------------------------------------------------------
// Soldaten skjuter (eller kastar granat från våg 3)
// -------------------------------------------------------------------
tdEnemyShoot:
    lda wave
    cmp #2
    bcc !bullet+
    lda egOn
    bne !bullet+
    jsr rnd
    cmp #90
    bcs !bullet+
    lda #1                  // granat mot spelarens position
    sta egOn
    lda #0
    sta egT
    lda E_XL,x
    clc
    adc #6
    sta egXL
    lda E_XH,x
    adc #0
    sta egXH
    lda E_Y,x
    clc
    adc #8
    sta egY
    lda px
    clc
    adc #6
    sta egTXL
    lda pxHi
    adc #0
    sta egTXH
    lda py
    clc
    adc #8
    sta egTY
    lda #16
    sta E_POSE,x
    lda #SFX_JUMP
    jmp playSfx

!bullet:
    ldy #NUM_EB-1
!loop:
    lda EB_ON,y
    beq !free+
    dey
    bpl !loop-
    rts
!free:
    lda #1
    sta EB_ON,y
    lda E_XL,x
    clc
    adc #8
    sta EB_XL,y
    lda E_XH,x
    adc #0
    sta EB_XH,y
    lda E_Y,x
    clc
    adc #16
    sta EB_Y,y
    lda #2
    sta EB_DY,y
    lda #0
    sta EB_DX,y
    lda wave                // våg 1: bara rakt nedåt
    beq !snd+
    lda px                  // annars snett mot spelaren om han står vid sidan
    sec
    sbc E_XL,x
    sta tmp6
    lda pxHi
    sbc E_XH,x
    bmi !left+
    bne !right+
    lda tmp6
    cmp #24
    bcc !snd+
!right:
    lda #2
    sta EB_DX,y
    bne !snd+
!left:
    lda tmp6
    cmp #256-24
    bcs !snd+
    lda #256-2
    sta EB_DX,y
!snd:
    lda #SFX_BLIP
    jmp playSfx

// Fiendeskotten
tdEnemyBullets:
    ldx #NUM_EB-1
!loop:
    lda EB_ON,x
    beq !next+
    ldy #0
    lda EB_DX,x
    bpl !+
    dey
!:  clc
    adc EB_XL,x
    sta EB_XL,x
    tya
    adc EB_XH,x
    sta EB_XH,x
    bmi !off+
    bne !hi+
    lda EB_XL,x
    cmp #8
    bcc !off+
    bcs !y+
!hi:
    lda EB_XL,x
    cmp #<336
    bcs !off+
!y: lda EB_Y,x
    clc
    adc EB_DY,x
    sta EB_Y,x
    cmp #244
    bcc !next+
!off:
    lda #0
    sta EB_ON,x
!next:
    dex
    bpl !loop-
    rts

// -------------------------------------------------------------------
// Spelarens granat: kastas rakt uppåt (fire + joystick ned)
// -------------------------------------------------------------------
tdThrowCheck:
    lda throwCool
    beq !+
    dec throwCool
    rts
!:  lda joy
    and #JOY_FIRE+JOY_DOWN
    cmp #JOY_FIRE+JOY_DOWN
    bne !rts+
    lda tdGren
    beq !rts+
    lda pgOn
    bne !rts+
    dec tdGren
    lda #1
    sta pgOn
    lda #0
    sta pgT
    lda px
    clc
    adc #4
    sta pgXL
    lda pxHi
    adc #0
    sta pgXH
    lda py
    sta pgY
    lda #30
    sta throwCool
    lda #SFX_JUMP
    jmp playSfx
!rts:
    rts

tdPlayerGrenade:
    lda pgOn
    beq !rts+
    dec pgY
    dec pgY
    inc pgT
    lda pgT
    cmp #GRENADE_T
    bcc !rts+
    lda #0
    sta pgOn
    // smäll: mitt i granaten
    lda pgXL
    clc
    adc #9
    sta tbAX
    lda pgXH
    adc #0
    sta tbAX+1
    lda pgY
    clc
    adc #2
    sta tbAY
    jsr tdFxAt
    jsr tdBlastEnemies
    lda tdState
    cmp #TDS_GATE
    bne !rts+
    jmp tdGateBlast
!rts:
    rts

// Alla soldater nära smällen (tbAX/tbAY) dör
tdBlastEnemies:
    ldx #NUM_E-1
!loop:
    lda E_TYPE,x
    cmp #ET_SOLDIER
    bne !next+
    lda E_XL,x              // soldatens mitt
    clc
    adc #12
    sta tbBX
    lda E_XH,x
    adc #0
    sta tbBX+1
    jsr tdAbsDX
    cmp #26
    bcs !next+
    lda E_Y,x
    clc
    adc #8
    sec
    sbc tbAY
    bcs !+
    eor #$ff
    adc #1
!:  cmp #22
    bcs !next+
    jsr tdKillEnemy
!next:
    dex
    bpl !loop-
    rts

// A = |tbAX - tbBX| (högst 255)
tdAbsDX:
    lda tbAX
    sec
    sbc tbBX
    sta tmp6
    lda tbAX+1
    sbc tbBX+1
    bmi !neg+
    bne !big+
    lda tmp6
    rts
!neg:
    cmp #$ff
    bne !big+
    lda tmp6
    eor #$ff
    clc
    adc #1
    rts
!big:
    lda #255
    rts

// -------------------------------------------------------------------
// Fiendens granat: flyger mot målet och exploderar
// -------------------------------------------------------------------
tdEnemyGrenade:
    lda egOn
    bne !+
    rts
!:  inc egT
    ldy #0                  // x mot målet, högst 2 pixlar per bildruta
!step:
    lda egXL
    cmp egTXL
    lda egXH
    sbc egTXH
    bcc !right+             // egX < mål
    lda egXL
    cmp egTXL
    bne !left+
    lda egXH
    cmp egTXH
    beq !ydir+
!left:
    lda egXL
    bne !+
    dec egXH
!:  dec egXL
    jmp !ydir+
!right:
    inc egXL
    bne !ydir+
    inc egXH
!ydir:
    lda egY
    cmp egTY
    beq !nexty+
    bcc !down+
    dec egY
    jmp !nexty+
!down:
    inc egY
!nexty:
    iny
    cpy #2
    bne !step-
    lda egXL                // framme (eller för länge i luften)?
    cmp egTXL
    bne !notyet+
    lda egY
    cmp egTY
    beq !boom+
!notyet:
    lda egT
    cmp #72
    bcc !rts+
!boom:
    lda #0
    sta egOn
    lda egXL
    clc
    adc #9
    sta tbAX
    lda egXH
    adc #0
    sta tbAX+1
    lda egY
    clc
    adc #2
    sta tbAY
    jsr tdFxAt
    lda pState              // spelaren nära smällen?
    bne !rts+
    lda invuln
    bne !rts+
    lda px
    clc
    adc #12
    sta tbBX
    lda pxHi
    adc #0
    sta tbBX+1
    jsr tdAbsDX
    cmp #20
    bcs !rts+
    lda py
    clc
    adc #9
    sec
    sbc tbAY
    bcs !+
    eor #$ff
    adc #1
!:  cmp #18
    bcs !rts+
    jmp tdKillPlayer
!rts:
    rts

// -------------------------------------------------------------------
// Explosioner (bara grafik). tdFxAt: smäll med mitten i tbAX/tbAY
// -------------------------------------------------------------------
tdFxAt:
    ldx #0
    lda FX_T
    beq !+
    inx
!:  lda #24
    sta FX_T,x
    lda tbAX
    sec
    sbc #11
    sta FX_XL,x
    lda tbAX+1
    sbc #0
    sta FX_XH,x
    lda tbAY
    sec
    sbc #10
    sta FX_Y,x
    lda #SFX_DEATH
    jmp playSfx

tdFx:
    ldx #NUM_FX-1
!loop:
    lda FX_T,x
    beq !+
    dec FX_T,x
!:  dex
    bpl !loop-
    rts

// -------------------------------------------------------------------
// Krockar: skott mot soldater, soldater/skott mot spelaren
// -------------------------------------------------------------------
tdCollide:
    ldy #NUM_BUL-1
!bul:
    lda B_ON,y
    beq !nextb+
    ldx #NUM_E-1
!en:
    lda E_TYPE,x
    cmp #ET_SOLDIER
    bne !nexte+
    lda B_Y,y               // snabbt först: är y ens i närheten?
    clc
    adc #4
    sec
    sbc E_Y,x
    cmp #24
    bcs !nexte+
    jsr tdEnemyBox
    lda B_XLO,y             // skottet: 8x4
    sta tbBX
    lda B_XHI,y
    sta tbBX+1
    lda B_Y,y
    sta tbBY
    lda #8
    sta tbBW
    lda #4
    sta tbBH
    sty tmp7
    jsr tdBoxHit
    ldy tmp7
    bcc !nexte+
    lda #0
    sta B_ON,y
    jsr tdKillEnemy
    jmp !nextb+
!nexte:
    dex
    bpl !en-
!nextb:
    dey
    bpl !bul-

    lda pState
    bne !done+
    lda invuln
    bne !done+
    ldx #NUM_E-1            // soldat mot spelaren
!en:
    lda E_TYPE,x
    cmp #ET_SOLDIER
    bne !nexte+
    jsr tdEnemyBox
    jsr tdPlayerBoxB
    jsr tdBoxHit
    bcc !nexte+
    jsr tdKillEnemy
    jmp tdKillPlayer
!nexte:
    dex
    bpl !en-
    ldx #NUM_EB-1           // fiendeskott mot spelaren
!eb:
    lda EB_ON,x
    beq !nexteb+
    jsr tdPlayerBoxA
    lda EB_XL,x
    sta tbBX
    lda EB_XH,x
    sta tbBX+1
    lda EB_Y,x
    sta tbBY
    lda #8
    sta tbBW
    lda #3
    sta tbBH
    jsr tdBoxHit
    bcc !nexteb+
    lda #0
    sta EB_ON,x
    jmp tdKillPlayer
!nexteb:
    dex
    bpl !eb-
!done:
    rts

// Box A = soldat X (14x14)
tdEnemyBox:
    lda E_XL,x
    clc
    adc #5
    sta tbAX
    lda E_XH,x
    adc #0
    sta tbAX+1
    lda E_Y,x
    clc
    adc #2
    sta tbAY
    lda #14
    sta tbAW
    sta tbAH
    rts

// Spelarens kropp (12x14) som box A eller B
tdPlayerBoxA:
    lda px
    clc
    adc #6
    sta tbAX
    lda pxHi
    adc #0
    sta tbAX+1
    lda py
    clc
    adc #2
    sta tbAY
    lda #12
    sta tbAW
    lda #14
    sta tbAH
    rts
tdPlayerBoxB:
    lda px
    clc
    adc #6
    sta tbBX
    lda pxHi
    adc #0
    sta tbBX+1
    lda py
    clc
    adc #2
    sta tbBY
    lda #12
    sta tbBW
    lda #14
    sta tbBH
    rts

// tdBoxHit: C=1 om box A och box B överlappar (använder overlap)
tdBoxHit:
    lda tbAX
    sta ovL
    lda tbAX+1
    sta ovL+1
    lda tbBW
    sec
    sbc #1
    sta tmp6
    clc
    adc tbBX
    sta ovR
    lda tbBX+1
    adc #0
    sta ovR+1
    lda tbAW
    clc
    adc tmp6
    sec
    sbc #1
    sta ovW
    lda tbAY
    sta ovLY
    lda tbBH
    sec
    sbc #1
    sta tmp6
    clc
    adc tbBY
    sta ovRY
    lda tbAH
    clc
    adc tmp6
    sec
    sbc #1
    sta ovWY
    jmp overlap

tdKillEnemy:
    lda #ET_BOOM
    sta E_TYPE,x
    lda #20
    sta E_TM,x
    lda #$01                // 100 poäng
    jsr addScoreHi
    lda #SFX_KILL
    jmp playSfx

// addScoreHi: lägg till BCD-värdet i A som hundratal
addScoreHi:
    sed
    clc
    adc score+1
    sta score+1
    lda score
    adc #0
    sta score
    cld
    rts

tdKillPlayer:
    lda pState
    bne !rts+
    lda invuln
    bne !rts+
    lda #1
    sta pState
    lda #60
    sta deathTimer
    lda #SFX_DEATH
    jmp playSfx
!rts:
    rts

// Spelaren död: räkna ned, sedan nytt liv eller game over
tdDying:
    dec deathTimer
    bne !rts+
    dec lives
    bne !+
    jmp startGameOver
!:  lda #0
    sta pState
    lda #150
    sta invuln
    ldx #0                  // flytta åt sidan om han står i taggtråd/hinder
!try:
    jsr tdBlocked
    bcs !move+
    jsr tdOnWire
    bcc !rts+
!move:
    jsr tdIncX
    jsr tdIncX
    jsr tdIncX
    jsr tdIncX
    lda pxHi
    beq !+
    lda px
    cmp #<TD_MAX_X
    bcc !+
    lda #TD_MIN_X+8
    sta px
    lda #0
    sta pxHi
!:  inx
    cpx #80
    bne !try-
!rts:
    rts

// tdOnWire: C=1 om spelaren rör taggtråd
tdOnWire:
    lda #TD_FOOT_L
    ldy #TD_FOOT_T
    jsr tdWireAt
    bcs !yes+
    lda #TD_FOOT_R
    ldy #TD_FOOT_T
    jsr tdWireAt
    bcs !yes+
    lda #TD_FOOT_L
    ldy #TD_FOOT_B
    jsr tdWireAt
    bcs !yes+
    lda #TD_FOOT_R
    ldy #TD_FOOT_B
    jsr tdWireAt
!yes:
    rts

tdWireAt:
    clc
    adc px
    sta cxLo
    lda pxHi
    adc #0
    sta cxHi
    tya
    clc
    adc py
    jsr tdCharAt
    cmp #TD_WIRE_FIRST
    bcc !no+
    cmp #TD_WIRE_FIRST+8
    bcs !no+
    sec
    rts
!no:
    clc
    rts

// -------------------------------------------------------------------
// Lådor: gå på lådan = 4 granater (högst 9)
// -------------------------------------------------------------------
tdCrateCheck:
    lda px
    clc
    adc #11
    sta cxLo
    lda pxHi
    adc #0
    sta cxHi
    lda py
    clc
    adc #10
    jsr tdCharAt
    cmp #TD_CRATE_FIRST
    bcc !rts+
    cmp #TD_CRATE_FIRST+4
    bcs !rts+
    sec                     // vilken fjärdedel av lådan?
    sbc #TD_CRATE_FIRST
    sta tmp6
    lda tdLastRow           // nedre teckenraden (lägre världsrad)
    ldx tmp6
    cpx #2
    bcs !+
    sec
    sbc #1
!:  sta tsRow
    lda tdLastCol
    sta tsCol
    lda tmp6
    and #1
    beq !+
    dec tsCol
!:  lda #MT_GRASS0
    jsr tdSetTile
    lda tdGren
    clc
    adc #4
    cmp #10
    bcc !+
    lda #9
!:  sta tdGren
    lda #SFX_PICKUP
    jmp playSfx
!rts:
    rts

// tdSetTile: A = block, tsRow = världsrad för blockets nedre halva,
// tsCol = vänstra teckenkolumnen. Skriver ringbuffert + båda skärmarna.
tdSetTile:
    tax
    lda mtBL,x
    jsr tdSetChar
    inc tsCol
    lda mtBR,x
    jsr tdSetChar
    inc tsRow
    lda mtTR,x
    jsr tdSetChar
    dec tsCol
    lda mtTL,x
    jsr tdSetChar
    dec tsRow
    rts

// tdSetChar: A = tecken vid världsrad tsRow, kolumn tsCol. Bevarar X.
tdSetChar:
    sta tmp7
    stx mxSaveX
    lda tsRow
    and #63
    tay
    lda ringLo,y
    sta tdPtr
    lda ringHi,y
    sta tdPtr+1
    ldy tsCol
    lda tmp7
    sta (tdPtr),y
    ldx #1                  // båda skärmbuffertarna
!buf:
    lda bufTop,x
    sec
    sbc tsRow
    cmp #23
    bcs !next+
    clc
    adc #2
    tay
    lda rowLo,y
    clc
    adc tsCol
    sta tdPtr
    lda rowHi,y
    adc #0
    cpx #1
    bne !+
    clc
    adc #SCREEN_B_OFS_HI
!:  sta tdPtr+1
    ldy #0
    lda tmp7
    sta (tdPtr),y
!next:
    dex
    bpl !buf-
    ldx mxSaveX
    rts

// -------------------------------------------------------------------
// Porten
// -------------------------------------------------------------------
// tdCanScroll: C=1 om banan inte får scrolla mer (muren är framme)
tdCanScroll:
    lda tdGateGen
    cmp #6
    bcc !yes+
    lda tdWrow
    sec
    sbc tdGateRow
    cmp #4
    bcc !yes+
    lda tdState             // första gången: porten ska sprängas
    cmp #TDS_PLAY
    bne !stop+
    lda #TDS_GATE
    sta tdState
    lda #GATE_HITS
    sta tdGateHP
    lda #1
    sta tdCrateT
    lda #40
    sta tdSpawnT
    lda tdFine              // portens nederkant i sprite-y
    clc
    adc #TD_TOP_LINE+32+6
    sta tdGateY
    lda #<msgGate
    ldx #>msgGate
    jsr showMsg
!stop:
    sec
    rts
!yes:
    clc
    rts

// En granat smällde vid tbAX/tbAY: träffade den porten?
tdGateBlast:
    lda #<GATE_CX
    sta tbBX
    lda #>GATE_CX
    sta tbBX+1
    jsr tdAbsDX
    cmp #22
    bcs !miss+
    lda tdGateY
    clc
    adc #10
    cmp tbAY
    bcs !hit+
!miss:
    rts
!hit:
    dec tdGateHP
    beq !broken+
    lda #SFX_KILL
    jsr playSfx
    lda #MT_GATED_BL        // skadad port
    sta tmp4
    lda #MT_GATED_BR
    sta tmp5
    lda #MT_GATED_TL
    sta tdTX
    lda #MT_GATED_TR
    sta tdTXH
    jmp tdGateTiles
!broken:
    lda #MT_RUBBLE_B        // sprängd: grus
    sta tmp4
    sta tmp5
    lda #MT_RUBBLE_T
    sta tdTX
    sta tdTXH
    jsr tdGateTiles
    lda tbAY                // en smäll till
    sec
    sbc #12
    sta tbAY
    jsr tdFxAt
    lda #$05                // 500 poäng + 100 per granat kvar
    jsr addScoreHi
!bonus:
    lda tdGren
    beq !+
    dec tdGren
    lda #$01
    jsr addScoreHi
    jmp !bonus-
!:  ldx #NUM_E-1            // alla soldater kvar sprängs också
!loop:
    lda E_TYPE,x
    cmp #ET_SOLDIER
    bne !next+
    lda #ET_BOOM
    sta E_TYPE,x
    lda #20
    sta E_TM,x
!next:
    dex
    bpl !loop-
    lda #0
    sta egOn
    ldx #NUM_EB-1
!loop:
    sta EB_ON,x
    dex
    bpl !loop-
    lda #TDS_CLEAR
    sta tdState
    lda #200
    sta tdTimer
    lda #SFX_PICKUP
    jsr playSfx
    lda #<msgClear
    ldx #>msgClear
    jmp showMsg
!rts:
    rts

// Byt portens fyra block: tmp4/tmp5 = nedre vänster/höger, tdTX/tdTXH = övre
tdGateTiles:
    lda tdGateRow
    sta tsRow
    lda #18
    sta tsCol
    lda tmp4
    jsr tdSetTile
    lda #20
    sta tsCol
    lda tmp5
    jsr tdSetTile
    inc tsRow
    inc tsRow
    lda #18
    sta tsCol
    lda tdTX
    jsr tdSetTile
    lda #20
    sta tsCol
    lda tdTXH
    jmp tdSetTile

// Vid porten utan granater: en ny låda dyker upp efter en stund
tdGateCrate:
    lda tdState
    cmp #TDS_GATE
    bne !rts+
    lda tdGren
    ora pgOn
    bne !rts+
    dec tdCrateT
    bne !rts+
    lda #250
    sta tdCrateT
    lda tdWrow              // skärmrad 16-17
    sec
    sbc #15
    sta tsRow
    lda frameCount          // vänster eller höger sida
    and #1
    tax
    lda crateCols,x
    sta tsCol
    lda #MT_CRATE
    jmp tdSetTile
!rts:
    rts
crateCols: .byte 8, 30

// -------------------------------------------------------------------
// Sprites för allt på marken (anropas från tdBuildSprites)
// -------------------------------------------------------------------
tdPushObjects:
    ldx #NUM_EB-1           // fiendeskott
!loop:
    lda EB_ON,x
    beq !next+
    lda EB_XL,x
    sta vsTX
    lda EB_XH,x
    sta vsTXH
    lda EB_Y,x
    sta vsTY
    lda #SPR_TD_EBULLET
    sta vsTP
    lda #COL_WHITE
    sta vsTC
    lda #1
    sta vsTM
    jsr vsPush
!next:
    dex
    bpl !loop-

    ldx #NUM_E-1            // soldater och explosioner
!loop:
    lda E_TYPE,x
    beq !next+
    lda E_XL,x
    sta vsTX
    lda E_XH,x
    sta vsTXH
    lda E_Y,x
    sta vsTY
    lda #1
    sta vsTM
    lda E_TYPE,x
    cmp #ET_BOOM
    bne !sol+
    lda #COL_YELLOW
    sta vsTC
    lda E_TM,x
    lsr
    lsr
    and #1
    clc
    adc #SPR_BOOM0
    bne !push+
!sol:
    lda #COL_GREY
    sta vsTC
    lda E_POSE,x
    beq !+
    lda #SPR_TD_ENEMYT
    bne !push+
!:  lda E_ST,x
    cmp #ES_AIM
    beq !+
    lda frameCount
    lsr
    lsr
    lsr
    and #1
!:  and #1
    clc
    adc #SPR_TD_ENEMY0
!push:
    sta vsTP
    jsr vsPush
!next:
    dex
    bpl !loop-

    ldx #NUM_BUL-1          // spelarens skott
!loop:
    lda B_ON,x
    beq !next+
    lda B_XLO,x
    sta vsTX
    lda B_XHI,x
    sta vsTXH
    lda B_Y,x
    sta vsTY
    lda #SPR_BULLET
    sta vsTP
    lda #COL_YELLOW
    sta vsTC
    lda #1
    sta vsTM
    jsr vsPush
!next:
    dex
    bpl !loop-

    lda pgOn                // spelarens granat + skugga
    beq !+
    lda pgXL
    sta vsTX
    lda pgXH
    sta vsTXH
    lda pgY
    sta vsTY
    jsr tdPushGrenade
    ldx pgT
    lda pgY
    sec
    sbc grenadeH,x
    sta vsTY
    jsr tdPushGrenadeTop
!:  lda egOn                // fiendens granat + skugga
    beq !+
    lda egXL
    sta vsTX
    lda egXH
    sta vsTXH
    lda egY
    sta vsTY
    jsr tdPushGrenade
    lda egT
    cmp #GRENADE_T
    bcc !small+
    lda #GRENADE_T-1
!small:
    tax
    lda egY
    sec
    sbc grenadeH,x
    sta vsTY
    jsr tdPushGrenadeTop
!:  ldx #NUM_FX-1           // explosioner
!loop:
    lda FX_T,x
    beq !next+
    lda FX_XL,x
    sta vsTX
    lda FX_XH,x
    sta vsTXH
    lda FX_Y,x
    sta vsTY
    lda FX_T,x
    lsr
    lsr
    and #1
    clc
    adc #SPR_BOOM0
    sta vsTP
    lda #COL_YELLOW
    sta vsTC
    lda #1
    sta vsTM
    jsr vsPush
!next:
    dex
    bpl !loop-
    rts

tdPushGrenade:              // skuggan på marken
    lda vsTY
    clc
    adc #2
    sta vsTY
    lda #SPR_TD_GSHADOW
    sta vsTP
    lda #COL_BLACK
    sta vsTC
    lda #1
    sta vsTM
    jmp vsPush
tdPushGrenadeTop:           // själva granaten (en bit upp i luften)
    lda #SPR_TD_GRENADE
    sta vsTP
    lda #COL_DARK_GREY
    sta vsTC
    lda #1
    sta vsTM
    jmp vsPush
