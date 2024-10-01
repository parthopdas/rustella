;===============================================================================
; Program Information
;===============================================================================

    ; Program:      Collect
    ; Program by:   Darrell Spice, Jr
    ; Last Update:  July 7, 2014
    ;
    ; Super simple game of "collect the boxes" used for presentation on
    ; developing Atari 2600 homebrew games.
    ;
    ; See readme.txt for compile instructions
    
    
;===============================================================================
; Change Log
;===============================================================================
 
    ; 2014.06.24 - generate a stable display
    ; 2014.06.25 - add Score+1s 
    ; 2014.06.28 - add score display and check for TV Type
    ; 2014.07.03 - add 2LK (2 line kernel)
    ; 2014.07.04 - 2LK update, set VDELP0 and VDELP1 based on Y positions
    ; 2014.07.04a- swapped GRP0 and GRP1 lines in the 2LK.  That gives us a
    ;              possiblity of adding the BALL object
    ;            - changed Score+1 to be a bar across the screen so we can have
    ;              a 2 player option
    ; 2014.07.06 - Draw the Arena, playfield collision logic
    ; 2014.07.07 - Select/Reset Switches, game active/inactive logic

;===============================================================================
; Initialize dasm
;===============================================================================

    ; Dasm supports a number of processors, this line tells dasm the code
    ; is for the 6502 CPU.  The Atari has a 6507, which is 6502 that's been
    ; put into a "reduced package".  This package limits the 6507 to an 8K
    ; address space and also removes support for external interrupts.
        PROCESSOR 6502
    
    ; vcs.h contains the standard definitions for TIA and RIOT registers 
        include vcs.h       
    
    ; macro.h contains commonly used routines which aid in coding
        include macro.h

;===============================================================================
; Define Constants
;===============================================================================
    ; height of the arena (gameplay area).  Since we're using a 2 line kernel,
    ; actual height will be twice this.  Also, we're using 0-89 for the 
    ; scanlines so actual height is 176 = 88*2
ARENA_HEIGHT   = 87    

;===============================================================================
; Define RAM Usage
;===============================================================================

    ; define a segment for variables
    ; .U means uninitialized, does not end up in ROM
        SEG.U VARS
    
    ; RAM starts at $80
        ORG $80             

    ; Holds 2 digit score for each player, stored as BCD (Binary Coded Decimal)
Score:          ds 2    ; stored in $80-81
    ; CODING TIP - The : is optional. However, if you remember to include the :
    ;              in all of your labels you can then easily find where
    ;              something is defined by including : in the search.
    ;              Find "Score:" will bring you here, find "Score" will locate
    ;              all places that the variable Score is used.

    ; Offsets into digit graphic data
DigitOnes:      ds 2    ; stored in $82-83, DigitOnes = Score, DigitOnes+1 = Score+1
DigitTens:      ds 2    ; stored in $84-85, DigitTens = Score, DigitTens+1 = Score+1

    ; graphic data ready to put into PF1 during display score routine
ScoreGfx:       ds 2    ; stored in $86-87

    ; scratch variable
Temp:           ds 1    ; stored in $88

    ; object X positions in $89-8D
ObjectX:        ds 5    ; player0, player1, missile0, missile1, ball

    ; object Y positions in $8E-92
ObjectY:        ds 5    ; player0, player1, missile0, missile1, ball

    ; DoDraw storage in $93-94
Player0Draw:    ds 1    ; used for drawing player0
Player1Draw:    ds 1    ; used for drawing player1

    ; DoDraw Graphic Pointers in $95-98
Player0Ptr:     ds 2    ; used for drawing player0
Player1Ptr:     ds 2    ; used for drawing player1

    ; frame counter
Frame:          ds 1    ; stored in $99

TimerPF:        ds 6    ; stored in $9A-9F
ArenaColor:     ds 1    ; stored in $A0

    ;save player locations for playfield collision logic
SavedX:         ds 2    ; stored in $A1-A2
SavedY:         ds 2    ; stored in $A3-A4

ArenaOffset:    ds 1    ; stored in $A5

Temp2:          ds 1    ; stored in $A6

    ; D7, 1=Game Active, 0=Game Over
GameState:      ds 1    ; stored in $A7
    ; CODING TIP - There are 8 bits within a byte.  Dx notation is used to
    ;              specify a specific bit where x is 0-7.
    ;              D7 is the high bit, D0 is the low bit.
    ;              D7 and D6 can be quickly tested without trashing any CPU
    ;              registers by using the BIT command.  You can see this in
    ;              action in OverScan where TIA's collision detection registers
    ;              are tested using the BIT command.

ColorCycle:        ds 1    ; stored in $A8    
;===============================================================================
; Define Start of Cartridge
;===============================================================================

    ; define a segment for code
    SEG CODE    
    
    ; 2K ROM starts at $F800, 4K ROM starts at $F000
    ORG $F800

;===============================================================================
; PosObject
;----------
; subroutine for setting the X position of any TIA object
; when called, set the following registers:
;   A - holds the X position of the object
;   X - holds which object to position
;       0 = player0
;       1 = player1
;       2 = missile0
;       3 = missile1
;       4 = ball
; the routine will set the coarse X position of the object, as well as the
; fine-tune register that will be used when HMOVE is used.
;===============================================================================
PosObject:
        sec
        sta WSYNC
DivideLoop
        sbc #15        ; 2  2 - each time thru this loop takes 5 cycles, which is 
        bcs DivideLoop ; 2  4 - the same amount of time it takes to draw 15 pixels
        eor #7         ; 2  6 - The EOR & ASL statements convert the remainder
        asl            ; 2  8 - of position/15 to the value needed to fine tune
        asl            ; 2 10 - the X position
        asl            ; 2 12
        asl            ; 2 14
        sta.wx HMP0,X  ; 5 19 - store fine tuning of X
        sta RESP0,X    ; 4 23 - set coarse X position of object
        rts            ; 6 29

        
;===============================================================================
; Initialize Atari
;===============================================================================
    
InitSystem:
    ; CLEAN_START is a macro found in macro.h
    ; it sets all RAM, TIA registers and CPU registers to 0
        CLEAN_START   
        
        jsr InitPos    ; put objects in default position
    ; from here we "fall into" the main loop    

;===============================================================================
; Main Program Loop
;===============================================================================

Main:
        jsr VerticalSync    ; Jump to SubRoutine VerticalSync
        jsr VerticalBlank   ; Jump to SubRoutine VerticalBlank
        jsr Kernel          ; Jump to SubRoutine Kernel
        jsr OverScan        ; Jump to SubRoutine OverScan
        jmp Main            ; JuMP to Main
    

;===============================================================================
; Vertical Sync
; -------------
; here we generate the signal that tells the TV to move the beam to the top of
; the screen so we can start the next frame of video.
; The Sync Signal must be on for 3 scanlines.
;===============================================================================

VerticalSync:
        lda #2          ; LoaD Accumulator with 2 so D1=1
        ldx #49         ; LoaD X with 49
        sta WSYNC       ; Wait for SYNC (halts CPU until end of scanline)
        sta VSYNC       ; Accumulator D1=1, turns on Vertical Sync signal
        stx TIM64T      ; set Score+1 to go off in 41 scanlines (49 * 64) / 76
        sta CTRLPF      ; D1=1, playfield now in SCORE mode
        lda Frame
        and #$3f
        bne VSskip
        dec ColorCycle
VSskip: inc Frame       ; increment Frame count

        sta WSYNC   ; Wait for Sync - halts CPU until end of 1st scanline of VSYNC
        sta WSYNC   ; wait until end of 2nd scanline of VSYNC
        lda #0      ; LoaD Accumulator with 0 so D1=0
        sta PF0     ; blank the playfield
        sta PF1     ; blank the playfield
        sta PF2     ; blank the playfield
        sta GRP0    ; blanks player0 if VDELP0 was off
        sta GRP1    ; blanks player0 if VDELP0 was on, player1 if VDELP1 was off 
        sta GRP0    ; blanks                           player1 if VDELP1 was on
        sta VDELP0  ; turn off Vertical Delay
        sta VDELP1  ; turn off Vertical Delay
        sta CXCLR   ; clear collision detection latches
        sta WSYNC   ; wait until end of 3rd scanline of VSYNC
        sta VSYNC   ; Accumulator D1=0, turns off Vertical Sync signal
Sleep12:            ;       jsr here to sleep for 12 cycles        
        rts         ; ReTurn from Subroutine
    
    
;===============================================================================
; Vertical Blank
; --------------
; game logic runs here.
;===============================================================================

VerticalBlank:
        jsr ProcessSwitches
        bit GameState
        bpl NotActive
        jsr UpdateTimer
        jsr ProcessJoystick
NotActive:        
        jsr PositionObjects
        jsr SetObjectColors
        jsr PrepScoreForDisplay
        rts             ; ReTurn from Subroutine

    
;===============================================================================
; Kernel
; ------
; here we update the registers in TIA, the video chip, scanline by scanline
; in order to generate what the player sees.
;
; Timing is crucial in the kernel, so we need to count the cycles.  You may
; use your own method of counting cycles, this is how I do it:
;       instruction     ;xx yy - comment
;   xx = cycles instruction will take
;   yy = cumulative cycle count after instruction runs
;   comment = what's going on.  Some instructions have special notation:
;       @aa-bb where aa and bb are numbers.  These are used to denote that the
;           instruction MUST be done within a range of cycles.  This is especially
;           true of updating the playfield where you need to update the register
;           twice on a scanline if you want the left and right side of the screen
;           to show different images.  If aa > bb that means the instruction can
;           be executed on the prior scanline on or after cycle aa.
;       (a b) where a and b are numbers.  These are used for branches to show
;           the cycles and cycle count if the branch is taken.
;
; The following is used to denote when a new scanline starts:
;---------------------------------------
;
;===============================================================================

Kernel:            
        sta WSYNC       ; Wait for SYNC (halts CPU until end of scanline)
;---------------------------------------                
        lda INTIM       ; 4  4 - check the Score+1
        bne Kernel      ; 2  6 - (3 7) Branch if its Not Equal to 0
    ; turn on the display
        sta VBLANK      ; 3  9 - Accumulator D1=0, turns off Vertical Blank signal (image output on)
        ldx #5          ; 2 11 - use X as the loop counter for ScoreLoop
        
    ; first thing we draw is the score.  Score is drawn using only PF1 of the
    ; playfield.  The playfield is set for in repeat mode, and SCORE is turned
    ; on so the left and right sides take on the colors of player0 and player1.
    ; To get here we can fall thru from above (cycle 11) OR loop back from below
    ; (cycle 43). We'll cycle count from the worst case scenario
ScoreLoop:              ;   43 - cycle after bpl ScoreLoop
        ldy DigitTens   ; 3 46 - get the tens digit offset for the Score
        lda DigitGfx,y  ; 5 51 -   use it to load the digit graphics
        and #$F0        ; 2 53 -   remove the graphics for the ones digit
        sta ScoreGfx    ; 3 56 -   and save it
        ldy DigitOnes   ; 3 59 - get the ones digit offset for the Score
        lda DigitGfx,y  ; 5 64 -   use it to load the digit graphics
        and #$0F        ; 2 66 -   remove the graphics for the tens digit
        ora ScoreGfx    ; 3 69 -   merge with the tens digit graphics
        sta ScoreGfx    ; 3 72 -   and save it
        sta WSYNC       ; 3 75 - wait for end of scanline
;---------------------------------------        
        sta PF1         ; 3  3 - @66-28, update playfield for Score dislay
        ldy DigitTens+1 ; 3  6 - get the left digit offset for the Score+1
        lda DigitGfx,y  ; 5 11 -   use it to load the digit graphics
        and #$F0        ; 2 13 -   remove the graphics for the ones digit
        sta ScoreGfx+1  ; 3 16 -   and save it
        ldy DigitOnes+1 ; 3 19 - get the ones digit offset for the Score+1
        lda DigitGfx,y  ; 5 24 -   use it to load the digit graphics
        and #$0F        ; 2 26 -   remove the graphics for the tens digit
        ora ScoreGfx+1  ; 3 29 -   merge with the tens digit graphics
        sta ScoreGfx+1  ; 3 32 -   and save it
        jsr Sleep12     ;12 44 - waste some cycles
        sta PF1         ; 3 47 - @39-54, update playfield for Score+1 display
        ldy ScoreGfx    ; 3 50 - preload for next scanline 
        sta WSYNC       ; 3 53 - wait for end of scanline
;---------------------------------------
        sty PF1         ; 3  3 - update playfield for the Score display
        inc DigitTens   ; 5  8 - advance for the next line of graphic data
        inc DigitTens+1 ; 5 13 - advance for the next line of graphic data
        inc DigitOnes   ; 5 18 - advance for the next line of graphic data
        inc DigitOnes+1 ; 5 23 - advance for the next line of graphic data
        jsr Sleep12     ;12 35 - waste some cycles
        dex             ; 2 37 - decrease the loop counter
        sta PF1         ; 3 40 - @39-54, update playfield for the Score+1 display
        bne ScoreLoop   ; 2 42 - (3 43) if dex != 0 then branch to ScoreLoop
        sta WSYNC       ; 3 45 - wait for end of scanline
;---------------------------------------
        stx PF1         ; 3  3 - x = 0, so this blanks out playfield        
        sta WSYNC       ; 3  6 - wait for end of scanline
;---------------------------------------  
        lda #0          ; 2  2
        sta CTRLPF      ; 3  5 - turn off SCORE mode
        ldx #1          ; 2  7
    ; draw timer bar
TimerBar:    
        sta WSYNC       ; 3  
;---------------------------------------
        lda TimerPF     ; 3  3
        sta PF0         ; 3  6
        lda TimerPF+1   ; 3  9
        sta PF1         ; 3 12
        lda TimerPF+2   ; 3 15
        sta PF2         ; 3 18
        SLEEP 20        ;20 38
        lda TimerPF+3   ; 3 41
        sta PF0         ; 3 44
        lda TimerPF+4   ; 3 47
        sta PF1         ; 3 50
        lda TimerPF+5   ; 3 53
        sta PF2         ; 3 56
        dex             ; 2 58
        bpl TimerBar    ; 2 60 (3 61)
        sta WSYNC       ; 3 63
;---------------------------------------
        lda #0          ; 2  2
        sta PF0         ; 3  5
        sta PF1         ; 3  8
        sta PF2         ; 3 11
        lda ArenaColor  ; 3 14        
        sta COLUPF      ; 3 17
        sta WSYNC       ; 3 20 - gab between timer and Arena
;---------------------------------------   
                

    ; The Arena is drawn using what is known as a 2 line kernel, or 2LK for
    ; short. Basically the code is designed so that the TIA register updates are
    ; spread out over 2 scanlines instead of one.  TIA has a feature for the
    ; player objects, as well as the ball, called Vertical Delay which allows
    ; the objects to still start on any scanline even though they are only
    ; updated every-other scanline.  Vertical Delay is controlled by the TIA
    ; registers VDELP0, VDELP1 and VDELBL.
    ;
    ; ArenaLoop:
    ;       line 1 - updates player0, playfield
    ;       line 2 - updates player1, playfield
    ;       if not at bottom, goto ArenaLoop
    
    ; we need to preload GRP1 so that player1 can appear on the very first
    ; scanline of the Arena
    
        lda #1              ; 2  2
        sta CTRLPF          ; 3  5 - turn off SCORE mode and turn on REFLECT 
        ldy #ARENA_HEIGHT+1 ; 2  7 - the arena will be 180 scanlines (from 0-89)*2
        ldx ArenaOffset     ; 3 10 - used for drawing playfield
        
    ; prime GRP1 so player1 can appear on topmost scanline of the Arena        
        lda #HUMAN_HEIGHT-1 ; 2 12 - height of player0 graphics, 
        dcp Player0Draw     ; 5 17 - Decrement Player0Draw and compare with height
        bcs DoDrawGrp0pre   ; 2 19 - (3 20) if Carry is Set, then player0 is on current scanline
        lda #0              ; 2 21 - otherwise use 0 to turn off player0
        .byte $2C           ; 4 25 - $2C = BIT with absolute addressing, trick that
                            ;        causes the lda (Player0Ptr),y to be skipped
DoDrawGrp0pre:              ;   20 - from bcs DoDrawGRP0pre
        lda (Player0Ptr),y  ; 5 25 - load the shape for player0
        sta GRP0            ; 3 28 - @0-22, update player0 graphics
        dey                 ; 2 30
        
ArenaLoop:                  ;   30 - (currently 7 from bpl ArenaLoop)
        tya                 ; 2 32 - 2LK loop counter in A for testing
        and #%11            ; 2 34 - test for every 4th time through the loop,
        bne SkipX           ; 2 36 (3 37) branch if not 4th time
        inx                 ; 2 38 - if 4th time, increase X so new playfield data is used
SkipX:                      ;   38 - use 38 as it's the longest path here        

    ; continuation of line 2 of the 2LK
    ; this precalculates data that's used on line 1 of the 2LK
        lda #HUMAN_HEIGHT-1 ; 2 40 - height of the humanoid graphics, subtract 1 due to starting with 0
        dcp Player1Draw     ; 5 45 - Decrement Player1Draw and compare with height
        bcs DoDrawGrp1      ; 2 47 - (3 48) if Carry is Set, then player1 is on current scanline
        lda #0              ; 2 49 - otherwise use 0 to turn off player1
        .byte $2C           ; 4 53 - $2C = BIT with absolute addressing, trick that
                            ;        causes the lda (Player1Ptr),y to be skipped
DoDrawGrp1:                 ;   48 - from bcs DoDrawGrp1
        lda (Player1Ptr),y  ; 5 53 - load the shape for player1
        sta WSYNC           ; 3 56
;---------------------------------------
    ; start of line 1 of the 2LK
        sta GRP1            ; 3  3 - @0-22, update player1 graphics
        lda ArenaPF0,x      ; 4  7 - get current scanline's playfield pattern
        sta PF0             ; 3 10 - @0-22 and update it
        lda ArenaPF1,x      ; 4 14 - get current scanline's playfield pattern
        sta PF1             ; 3 17 - @71-28 and update it
        lda ArenaPF2,x      ; 4 21 - get current scanline's playfield pattern
        sta PF2             ; 3 24 - @60-39
        
    ; precalculate data that's needed for line 2 of the 2LK        
        lda #HUMAN_HEIGHT-1 ; 2 26 - height of the box graphics, 
        dcp Player0Draw     ; 5 31 - Decrement Player0Draw and compare with height
        bcs DoDrawGrp0      ; 2 33 - (3 34) if Carry is Set then player0 is on current scanline
        lda #0              ; 2 35 - otherwise use 0 to turn off player0
        .byte $2C           ; 4 39 - $2C = BIT with absolute addressing, trick that
                            ;        causes the lda (Player0Ptr),y to be skipped
DoDrawGrp0:                 ;   34 - from bcs DoDrawGRP0
        lda (Player0Ptr),y  ; 5 39 - load the shape for player0
        sta WSYNC           ; 3 42
;---------------------------------------
    ; start of line 2 of the 2LK
        sta GRP0            ; 3  3 - @0-22, update player0 graphics
        dey                 ; 2  5 - decrease the 2LK loop counter
        bne ArenaLoop       ; 2  7 - (3  8) branch if there's more Arena to draw
        sty PF0             ; 3 10 - Y is 0, blank out playfield
        sty PF1             ; 3 13 - Y is 0, blank out playfield
        sty PF2             ; 3 16 - Y is 0, blank out playfield
        rts                 ; 6 22 - ReTurn from Subroutine

        
;===============================================================================
; Overscan
; --------------
; Process Object Collisions here
;===============================================================================

OverScan:
        sta WSYNC       ; Wait for SYNC (halts CPU until end of scanline)
        lda #2          ; LoaD Accumulator with 2 so D1=1
        sta VBLANK      ; STore Accumulator to VBLANK, D1=1 turns image output off
        
    ; set the Score+1 for 27 scanlines.  Each scanline lasts 76 cycles,
    ; but the Score+1 counts down once every 64 cycles, so use this
    ; formula to figure out the value to set.  
    ;       (scanlines * 76) / 64    
    ; Also note that it might be slight off due to when on the scanline TIM64T
    ; is updated.  So use Stella to check how many scanlines the code is
    ; generating and adjust accordingly.
    ;
    ; originally 32, changed to 35 after tweaking size of Arena
        lda #35         ; set Score+1 for 27 scanlines, 32 = ((27 * 76) / 64)
        sta TIM64T      ; set Score+1 to go off in 27 scanlines
        
    ; Test if player collided with playfield
        bit CXP0FB      ; N = player0/playfield, V=player0/ball
        bpl notP0PF     ; if N is off, then player0 did not collide with playfield
        lda SavedX      ; recall saved X
        sta ObjectX     ; and move player back to it
        lda SavedY      ; recall saved Y
        sta ObjectY     ; and move player back to it
notP0PF:        
        bit CXP1FB      ; N = player1/playfield, V=player1/ball
        bpl notP1PF     ; if N is off, then player1 did not collide with playfield
        lda SavedX+1    ; recall saved X
        sta ObjectX+1   ; and move player back to it
        lda SavedY+1    ; recall saved Y
        sta ObjectY+1   ; and move player back to it
notP1PF:        
    
OSwait:
        sta WSYNC   ; Wait for SYNC (halts CPU until end of scanline)
        lda INTIM   ; Check the Score+1
        bne OSwait  ; Branch if its Not Equal to 0
        rts         ; ReTurn from Subroutine
    

;===============================================================================
; UpdateTimer
; -----------
; udpates timer display
;===============================================================================
UpdateTimer:
        lda Frame
        and #63
        beq TimerTick
        rts
        
TimerTick:
        lda TimerPF
        and #%11110000
        bne DecrementTimer
    ; reset timer for demo        
        lda #0
        sta GameState
        rts
        
DecrementTimer:
        lsr TimerPF+5   ; PF2 right side, reversed bits so shift right
        rol TimerPF+4   ; PF1 right side, normal bits so shift left
        ror TimerPF+3   ; PF0 right side, reversed bits so shift right
        lda TimerPF+3   ; only upper nybble used, so we need to put bit 3 into C
        lsr
        lsr
        lsr
        lsr
        ror TimerPF+2   ; PF2 left side, reversed bits so shift right
        rol TimerPF+1   ; PF1 left side, normal bits so shift left
        ror TimerPF     ; PF0 left side, reversed bits so shift right
        rts

;===============================================================================
; ProcessJoystick
; --------------
; Read left joystick and move the humanoid
; for testing, read right joystick and move second humanoid
;
; joystick directions are held in the SWCHA register of the RIOT chip.
; Directions are read via the following bit pattern:
;   76543210
;   RLDUrldu
;
; UPPERCASE denotes the left joystick directions
; lowercase denotes the right joystick directions
;
; NOTE the values are the opposite of what you might expect. If the direction
; is held, the bit value will be 0.
;
; Fire buttons are read via INPT4 (left) and INPT5 (right).  They are currently
; used to slow down player movement to make alignment testing easier.
;===============================================================================
ProcessJoystick:
        lda SWCHA       ; reads joystick positions
        
        ldx #0          ; x=0 for left joystick, x=1 for right
PJloop:    
        ldy ObjectX,x   ; save original Y location so the player can be
        sty SavedX,x    ;   bounced back upon colliding with the playfield
        ldy ObjectY,x   ; save original Y location so the player can be
        sty SavedY,x    ;   bounced back upon colliding with the playfield
        ldy INPT4,x     ; check the firebutton for this joystick
        bmi NormalSpeed ; if it's not held down then player moves at full speed 
        pha             ; PusH A onto stack (saves value of A)
        lda Frame       ; if it is held down, then only move once every 8 frames
        and #7
        beq SlowMovement
        pla             ; PuLl A from stack (restores value of A)
        asl             ; shift the 4 direction readings out of A
        asl             ; so the other joystick can be processed
        asl
        asl
        jmp NextJoystick
        
SlowMovement:
        pla                 ; PuLl A from stack (restores value of A)
NormalSpeed:        
        asl                 ; shift A bits left, R is now in the carry bit
        bcs CheckLeft       ; branch if joystick is not held right
        ldy ObjectX,x       ; get the object's X position
        iny                 ; and move it right
        cpy #160            ; test for edge of screen
        bne SaveX           ; save Y if we're not at the edge
        ldy #0              ; else wrap to left edge
SaveX:  sty ObjectX,x       ; saveX
        ldy #0              ; turn off reflect of player, which
        sty REFP0,x         ; makes humanoid image face right

CheckLeft:
        asl                 ; shift A bits left, L is now in the carry bit
        bcs CheckDown       ; branch if joystick not held left
        ldy ObjectX,x       ; get the object's X position
        dey                 ; and move it left
        cpy #255            ; test for edge of screen
        bne SaveX2          ; save X if we're not at the edge
        ldy #159            ; else wrap to right edge
SaveX2: sty ObjectX,x       ; save X
        ldy #8              ; turn on reflect of player, which
        sty REFP0,x         ; makes humanoid image face left 

CheckDown:
        asl                     ; shift A bits left, D is now in the carry bit
        bcs CheckUp             ; branch if joystick not held down
        ldy ObjectY,x           ; get the object's Y position
        dey                     ; move it down
        cpy #255                ; test for bottom of screen
        bne SaveY               ; save Y if we're not at the bottom
        ldy #ARENA_HEIGHT*2+1   ; else wrap to top
SaveY:  sty ObjectY,x           ; save Y

CheckUp:
        asl                     ; shift A bits left, U is now in the carry bit
        bcs NextJoystick        ; branch if joystick not held up
        ldy ObjectY,x           ; get the object's Y position
        iny                     ; move it up
        cpy #ARENA_HEIGHT*2+2   ; test for top of screen
        bne SaveY2              ; save Y if we're not at the top
        ldy #0                  ; else wrap to bottom
SaveY2: sty ObjectY,x           ; save Y
        
NextJoystick:               
        inx                 ; increase loop control
        cpx #2              ; check if we've processed both joysticks
        bne PJloop          ; branch if we haven't
        
        rts
        
;===============================================================================
; PositionObjects
; --------------
; Updates TIA for X position of all objects
; Updates Kernel variables for Y position of all objects
;===============================================================================
PositionObjects:
        ldx #1              ; position objects 0-1: player0 and player1
POloop        
        lda ObjectX,x       ; get the object's X position
        jsr PosObject       ; set coarse X position and fine-tune amount 
        dex                 ; DEcrement X
        bpl POloop          ; Branch PLus so we position all objects
        sta WSYNC           ; wait for end of scanline
        sta HMOVE           ; use fine-tune values to set final X positions
        
    ; prep player 1's Y position for 2LK 
        ldx #1              ; preload X for setting VDELPx
        lda ObjectY         ; get the human's Y position
        clc
        adc #1              ; add 1 to compensate for priming of GRP0        
        lsr                 ; divide by 2 for the 2LK position
        sta Temp            ; save for position calculations
        bcs NoDelay0        ; if carry is set we don't need Vertical Delay
        stx VDELP0          ; carry was clear, so set Vertical Delay
NoDelay0:        
    ; Player0Draw = ARENA_HEIGHT + HUMAN_HEIGHT - Y position + 1
    ; the + 1 compensates for priming of GRP0    
        lda #(ARENA_HEIGHT + HUMAN_HEIGHT + 1)
        sec
        sbc Temp
        sta Player0Draw
        
    ; Player0Ptr = HumanGfx + HUMAN_HEIGHT - 1 - Y position
        lda #<(HumanGfx + HUMAN_HEIGHT - 1)
        sec
        sbc Temp
        sta Player0Ptr
        lda #>(HumanGfx + HUMAN_HEIGHT - 1)
        sbc #0
        sta Player0Ptr+1
        
    ; prep player 2's Y position for 2LK
        lda ObjectY+1       ; get the box's Y position
        lsr                 ; divide by 2 for the 2LK position
        sta Temp            ; save for position calculations
        bcs NoDelay1        ; if carry is set we don't need Vertical Delay
        stx VDELP1          ; carry was clear, so set Vertical Delay
NoDelay1:        
    ; Player1Draw = ARENA_HEIGHT + HUMAN_HEIGHT - Y position + 1
        lda #(ARENA_HEIGHT + HUMAN_HEIGHT)
        sec
        sbc Temp
        sta Player1Draw
        
        ldx #0
        bit SWCHB
        bpl TwoPlayer
        ldx #1
TwoPlayer:        
    ; Player1Ptr = BoxGfx + HUMAN_HEIGHT - 1 - Y position
        lda ShapePtrLow,x
        sec
        sbc Temp
        sta Player1Ptr
        lda ShapePtrHi,x
        sbc #0
        sta Player1Ptr+1
        
        rts
        
ShapePtrLow:
        .byte <(HumanGfx + HUMAN_HEIGHT - 1)
        .byte <(BoxGfx + HUMAN_HEIGHT - 1)
        
ShapePtrHi:
        .byte >(HumanGfx + HUMAN_HEIGHT - 1)
        .byte >(BoxGfx + HUMAN_HEIGHT - 1)

;===============================================================================
; SetObjectColors
; --------------
; Set the 4 color registers based on the state of TV Type.
; Eventually this will also handle color cycling of attract mode
;===============================================================================
SetObjectColors:
        lda #$FF
        sta Temp2       ; default to color mask
        and ColorCycle  ; color cycle
        bit GameState
        bpl SOCgameover
        lda #0          ; if game is active, no color cycle
SOCgameover:
        sta Temp
        ldx #4          ; we're going to set 5 colors (0-4)
        ldy #4          ; default to the color entries in the table (0-4)
        lda SWCHB       ; read the state of the console switches
        and #%00001000  ; test state of D3, the TV Type switch
        bne SOCloop     ; if D3=1 then use color
        ldy #$0f
        sty Temp2       ; set B&W mask
        ldy #9          ; else use the b&w entries in the table (5-9)
SOCloop:        
        lda Colors,y    ; get the color or b&w value
        eor Temp        ; color cycle
        and Temp2       ; B&W mask
        sta COLUP0-1,x  ; and set it
        dey             ; decrease Y
        dex             ; decrease X 
        bne SOCloop     ; Branch Not Equal to Zero
        lda Colors,y    ; get the Arena color
        eor Temp        ; color cycle
        and Temp2       ; B&W mask
        sta ArenaColor  ; save in RAM for Kernal Usage
        
        rts             ; ReTurn from Subroutine
        
Colors:   
        .byte $46   ; red        - goes into COLUPF, color for Arena (after Timer is drawn)
        .byte $86   ; blue       - goes into COLUP0, color for player0 and missile0
        .byte $C6   ; green      - goes into COLUP1, color for player1 and missile1
        .byte $64   ; purple     - goes into COLUPF, color for Timer
        .byte $00   ; black      - goes into COLUBK, color for background
        .byte $0A   ; light grey - goes into COLUPF, color for Arena (after Timer is drawn)
        .byte $0E   ; white      - goes into COLUP0, color for player0 and missile0
        .byte $06   ; dark grey  - goes into COLUP1, color for player1 and missile1
        .byte $04   ; dark grey  - goes into COLUPF, color for Timer
        .byte $00   ; black      - goes into COLUBK, color for background
        
;===============================================================================
; PrepScoreForDisplay
; --------------
; Converts the high and low nybbles of the RAM variables Score and Score+1
; into offsets into the digit graphics so the values can be displayed.
; Each digit uses 5 bytes of data for the graphics.  For the low nybble we need
; to multiply by 5, but the 6507 does not have a multiply feature.  It can,
; however, shift the bits in a byte left, which is the same as a multiply by 2.
; Using this, we can get multiply a # by 5 like this:
;       # * 5 = (# * 2 * 2) + #
; The value in the upper nybble is already times 16, so we need to divide it.
; The 6507 can shift the bits the right, which is the same as divide by 2.
;       (# / 16) * 5 = (# / 2 / 2) + (# / 2 / 2 / 2 / 2)  
;===============================================================================

PrepScoreForDisplay:
    ; for testing purposes, set Score to Humanoid Y and Score+1 to Box Y
        lda ObjectY
        sta Score
        lda ObjectY+1
        sta Score+1
        
PSFDskip        
        ldx #1          ; use X as the loop counter for PSFDloop
PSFDloop:
        lda Score,x     ; LoaD A with Score+1(first pass) or Score(second pass)
        and #$0F        ; remove the tens digit
        sta Temp        ; Store A into Temp
        asl             ; Accumulator Shift Left (# * 2)
        asl             ; Accumulator Shift Left (# * 4)
        adc Temp        ; ADd with Carry value in Temp (# * 5)
        sta DigitOnes,x  ; STore A in DigitOnes+1(first pass) or DigitOnes(second pass)
        lda Score,x     ; LoaD A with Score+1(first pass) or Score(second pass)
        and #$F0        ; remove the ones digit
        lsr             ; Logical Shift Right (# / 2)
        lsr             ; Logical Shift Right (# / 4)
        sta Temp        ; Store A into Temp
        lsr             ; Logical Shift Right (# / 8)
        lsr             ; Logical Shift Right (# / 16)
        adc Temp        ; ADd with Carry value in Temp ((# / 16) * 5)
        sta DigitTens,x ; STore A in DigitTens+1(first pass) or DigitTens(second pass)
        dex             ; DEcrement X by 1
        bpl PSFDloop    ; Branch PLus (positive) to PSFDloop
        rts             ; ReTurn from Subroutine      

        
;===============================================================================
; ProcessSwitches
; --------------
; This routine processes the SELECT and RESET switches on the console.  The
; state of the switches is in the SWCHB register. 
;   - D1=0 means SELECT is held.  Turn off an active game and increment game variation
;   - D0=0 means RESET is held.  Start a new game
;===============================================================================
ProcessSwitches:
        lda SWCHB       ; load in the state of the switches
        lsr             ; D0 is now in C
        bcs NotReset    ; if D0 was on, the RESET switch was not held
        jsr InitPos     ; Prep for new game 
        lda #%10000000  
        sta GameState   ; set D7 on to signify Game Active      
        rts
        
NotReset:
        lsr             ; D1 is now in C
        bcs NotSelect
        lda #0
        sta GameState   ; clear D7 to signify Game Over
        
NotSelect:
        rts
        
        
;===============================================================================
; InitPos
; --------------
;===============================================================================
InitPos:
    ; set starting location of player0 and player1 objects
        lda #10
        sta ObjectX
        sta REFP1       ; bit D3 is on, so reflect player1
        lda #142
        sta ObjectX+1
        lda #$63
        sta ObjectY
        sta ObjectY+1
        sta REFP0       ; bit D3 is off, so don't reflect player0
    ; reset timer        
        lda #%11111111
        sta TimerPF
        sta TimerPF+1
        sta TimerPF+2
        sta TimerPF+3
        sta TimerPF+4
        sta TimerPF+5        
        rts        
        
        
;===============================================================================
; free space check before DigitGfx
;===============================================================================
        
 if (* & $FF)
    echo "------", [(>.+1)*256 - .]d, "bytes free before DigitGfx"
    align 256
  endif    
    
  
;===============================================================================
; Digit Graphics
;===============================================================================
        align 256
DigitGfx:
        .byte %01110111
        .byte %01010101
        .byte %01010101
        .byte %01010101
        .byte %01110111
        
        .byte %00010001
        .byte %00010001
        .byte %00010001
        .byte %00010001        
        .byte %00010001
        
        .byte %01110111
        .byte %00010001
        .byte %01110111
        .byte %01000100
        .byte %01110111
        
        .byte %01110111
        .byte %00010001
        .byte %00110011
        .byte %00010001
        .byte %01110111
        
        .byte %01010101
        .byte %01010101
        .byte %01110111
        .byte %00010001
        .byte %00010001
        
        .byte %01110111
        .byte %01000100
        .byte %01110111
        .byte %00010001
        .byte %01110111
           
        .byte %01110111
        .byte %01000100
        .byte %01110111
        .byte %01010101
        .byte %01110111
        
        .byte %01110111
        .byte %00010001
        .byte %00010001
        .byte %00010001
        .byte %00010001
        
        .byte %01110111
        .byte %01010101
        .byte %01110111
        .byte %01010101
        .byte %01110111
        
        .byte %01110111
        .byte %01010101
        .byte %01110111
        .byte %00010001
        .byte %01110111
        
        .byte %00100010
        .byte %01010101
        .byte %01110111
        .byte %01010101
        .byte %01010101
         
        .byte %01100110
        .byte %01010101
        .byte %01100110
        .byte %01010101
        .byte %01100110
        
        .byte %00110011
        .byte %01000100
        .byte %01000100
        .byte %01000100
        .byte %00110011
        
        .byte %01100110
        .byte %01010101
        .byte %01010101
        .byte %01010101
        .byte %01100110
        
        .byte %01110111
        .byte %01000100
        .byte %01100110
        .byte %01000100
        .byte %01110111
        
        .byte %01110111
        .byte %01000100
        .byte %01100110
        .byte %01000100
        .byte %01000100
   
HumanGfx:
        .byte %00011100
        .byte %00011000
        .byte %00011000
        .byte %00011000
        .byte %01011010
        .byte %01011010
        .byte %00111100
        .byte %00000000
        .byte %00011000
        .byte %00011000
HUMAN_HEIGHT = * - HumanGfx      

BoxGfx:
        .byte %00000000
        .byte %00000000
        .byte %11111111
        .byte %10000001
        .byte %10000001
        .byte %10000001
        .byte %10000001
        .byte %10000001
        .byte %10000001
        .byte %11111111
        
ArenaPF0:   ; PF0 is drawn in reverse order, and only the upper nybble
        .byte %11110000 ; Arena 1
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %11110000  
        
        .byte %11110000 ; Arena 2
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %00010000
        .byte %11110000       
        

ArenaPF1:   ; PF1 is drawn in expected order       
        .byte %11111111
        .byte %00000000
        .byte %00000000
        .byte %00111000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %11000000
        .byte %01000000
        .byte %01000000
        .byte %01000001
        .byte %01000001
        .byte %01000000
        .byte %01000000
        .byte %11000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00111000
        .byte %00000000
        .byte %00000000
        .byte %11111111     
        
        .byte %11111111
        .byte %00000000
        .byte %00000000
        .byte %00111000
        .byte %00000001
        .byte %00000001
        .byte %00000000
        .byte %11000000
        .byte %01100000
        .byte %00110000
        .byte %00011000
        .byte %00011000
        .byte %00110000
        .byte %01100000
        .byte %11000000
        .byte %00000000
        .byte %00000001
        .byte %00000001
        .byte %00111000
        .byte %00000000
        .byte %00000000
        .byte %11111111   
        
        
ArenaPF2:   ; PF2 is drawn in reverse order
        .byte %11111111 ; Arena 1
        .byte %10000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00011100
        .byte %00000100
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000100
        .byte %00011100
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %10000000
        .byte %11111111       
        
        .byte %11111111 ; Arena 2
        .byte %00000000
        .byte %00000100
        .byte %00000100
        .byte %00011100
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %11000000
        .byte %10000000
        .byte %10000000
        .byte %11000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00000000
        .byte %00011100
        .byte %00000100
        .byte %00000100
        .byte %00000000
        .byte %11111111       

        
;===============================================================================
; free space check before End of Cartridge
;===============================================================================
        
 if (* & $FF)
    echo "------", [$FFFA - *]d, "bytes free before End of Cartridge"
    align 256
  endif    
        
;===============================================================================
; Define End of Cartridge
;===============================================================================
        ORG $FFFA        ; set address to 6507 Interrupt Vectors 
        .WORD InitSystem ; NMI
        .WORD InitSystem ; RESET
        .WORD InitSystem ; IRQ
