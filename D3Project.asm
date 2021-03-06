$NOMOD51
$NOSYMBOLS
;*****************************************************************************
;  
;
;  FILE NAME   :  D3Project.ASM 
;  TARGET MCU  :  C8051F340
;
;*****************************************************************************
;
$NOLIST
$include (c8051f340.inc)              ; Include register definition file.
$LIST
;
;*****************************************************************************
;*****************************************************************************
;
; EQUATES
;
;*****************************************************************************

ENABLE           EQU  P1.4            ; Enable signal to LCD
RW               EQU  P1.2             ;R/W signal to LCD.
RS               EQU  P1.3            ; RS signal to LCD
LCD              EQU  P2              ; Output port to LCD.

keyport          equ P3               ; Keypad port connected here
row1             equ P3.0             ; Row 1 (pin 8)
row2             equ P3.1             ; Row 2 (pin 1) 
row3             equ P3.2             ; Row 3 (pin 2)
row4             equ P3.3             ; Row 4 (pin 4)

col1             equ P3.4             ; Column 1 (pin 3)
col2             equ P3.5             ; Column 2 (pin 5)
col3             equ P3.6             ; Column 3 (pin 6)
col4             equ P3.7             ; Column 4 (pin 7)

pump1           equ P0.5							; Pump 1 enable/disable
pump2					  equ P0.4							; Pump 2 enable/disable


NULL						 equ 00H

;*****************************************************************************
;*****************************************************************************
;
; RESET and INTERRUPT VECTORS
;
;*****************************************************************************

         ; Reset Vector
                 ORG 0000H
                 ljmp Main            ; Locate a jump to the start of
                                      ; code at the reset vector.

                 org  002BH           ; Vector address for Timer 2 ISR
                 jmp  TIMER2_ISR      ; The ISR is large; need to relocate
                                      ;  and jump to it

;*****************************************************************************
;*****************************************************************************
;
; MAIN CODE
;
;*****************************************************************************


Main:
         ; Disable the WDT.
                 anl PCA0MD,#NOT(040h); Clear Watchdog Enable bit

         ; Enable the Port I/O Crossbar
				 				 mov P0MDOUT, #0FFh   ; Make P0 output push-pull
                 mov P2MDOUT, #0ffh   ; Make P2 output push-pull
                 mov P1MDOUT, #0ffh   ; Make P1 output push-pull
                 mov P1MDIN, #0ffh    ; Make port pins input mode digital
                 mov P3MDOUT, #0fh    ; Make P3 low nibble output push-pull
                 mov XBR1, #40h       ; Enable Crossbar
								 mov P4MDIN, #000h    ; Makes P4 analog input

                 mov AMX0N, #01Fh    ; Set ADC negative to GND
								 mov ADC0CF, #0FCh   ; Make ADC0H:ADC0L left justified
                 mov ADC0CN, #080h   ; Set ADC to enabled and trigger on write to ADC flag
								 mov REF0CN, #008h    ; Set Voltage Regulator to VDD
			
								 	                  
                 mov R3, #0          ; Clears LCD position counter
                 call Init           ; LCD Initialization proceedure
                 call Clear          ; Clear LCD Display
								 call cursor_off     ; Turn the cursor off
								 call delay
								 clr pump1					 ;Initialize the pumps as turned off
								 clr pump2
								 call Names					 ; Display class and group members
								 call Timer2_Init	   ; Initialize the Timer operation for the interrupt

					
			
         ; For this program, the keys are numbered
         ; as:

         ;	+----+----+----+----+
         ;	|  1 |  2 |  3 |  A | row1
         ;	+----+----+----+----+
         ;	|  4 |  5 |  6 |  B | row2
         ;	+----+----|----+----+
         ;	|  7 |  8 |  9 |  C | row3
         ;	+----+----+----+----+
         ;	|  * |  0 |  # |  D | row4
         ;	+----+----+----+----+  
         ;	 col1 col2 col3 col4

         ; The pressed key number will be stored in
         ; R0. Therefore, R0 is initially cleared.
         ; Each key is scanned, and if it is not
         ; pressed R0 is incremented. In that way,
         ; when the pressed key is found, R0 will
         ; contain the key's number.

         ; The general purpose flag, F0, is used
         ; by the column-scan subroutine to indicate
         ; whether or not a pressed key was found
         ; in that column.
         ; If, after returning from colScan, F0 is
         ; set, this means the key was found.



;*****************************************************************************
;*****************************************************************************
;
;  main_menu subroutine
;  
;  Sets up the main menu text, the waits for a selection on the keypad to be
;  made. You can go to the test menu (A), and change the desired moisure level
;  of the plants. 
;
;	 Registers: R0 (to catch the key from keyscan)
;  Flags: F0 (to test if a key has been pressed)
;
;*****************************************************************************


main_menu:       
								 call main_menu_text
mm_scan:				 call keyscan

								 cjne R0, #03h, mm_next1
								 call test_menu
								 CLR F0
								 jmp mm_scan

mm_next1:				 cjne R0, #07h, mm_end
								 call desired_levels
								 CLR F0
								 jmp mm_scan

mm_end:          CLR F0               ; clear flag
                 JMP mm_scan


;*****************************************************************************
;*****************************************************************************
;
;  test_menu subroutine
;  
;  Sets up the test menu text, the waits for a test to be selected or to
;  cancel to go back to the main menu.
;
;	 Registers: R0 (to catch the key from keyscan)
;  Flags: F0 (to test if a key has been pressed)
;
;*****************************************************************************


test_menu:
								 mov IE, #00h			
								 
								 clr pump1
								 clr pump2 
								 					 
							   call test_menu_text

tm_scan:				 CLR F0
								 call keyscan  
							
                 cjne R0, #00h, tm_next1
						     call lcd_test
						     CLR F0
						     jmp tm_scan

tm_next1:        cjne R0, #01h, tm_next2
						     call sensors_test
						     CLR F0
						     jmp tm_scan

tm_next2:        cjne R0, #02h, tm_next3
						     call pumps_test
						     CLR F0
						     jmp tm_scan
						 
tm_next3:	       cjne R0, #0Ch, tm_scan
						     CLR F0

                 call main_menu_text

						     mov IE, #0A0h

								 ret

;*****************************************************************************
;*****************************************************************************
;
;  keyscan subroutine
;
;*****************************************************************************


keyscan:				 MOV R0, #0           ; clear R0 - the first key is key0

; scan row1
                 SETB row4            ; set row4
                 CLR row1             ; clear row1
                 CALL colScan         ; call column-scan subroutine
                 JB F0, finish        ; | if F0 is set, jump to end of program 
                                      ; | (because the pressed key was found
                                      ; | and its number is in R0)

; scan row2
                 SETB row1            ; set row1
                 CLR row2             ; clear row2
                 CALL colScan         ; call column-scan subroutine
                 JB F0, finish        ; | if F0 is set, jump to end of program 
                                      ; | (because the pressed key was found
                                      ; | and its number is in R0)

; scan row3
                 SETB row2            ; set row2
                 CLR row3             ; clear row3
                 CALL colScan         ; call column-scan subroutine
                 JB F0, finish        ; | if F0 is set, jump to end of program 
                                      ; | (because the pressed key was found
                                      ; | and its number is in R0)

; scan row4
                 SETB row3            ; set row3
                 CLR row4             ; clear row4
                 CALL colScan         ; call column-scan subroutine
                 JB F0, finish        ; | if F0 is set, jump to end of program 
                                      ; | (because the pressed key was found
                                      ; | and its number is in R0)

                 JMP keyscan           ; | go back to scan row 1
                                      ; | (this is why row4 is set at the
                                      ; | start of the program - when the
                                      ; | program jumps back to start, row4
                                      ; | has just been scanned)

finish:          ret



;*****************************************************************************
;*****************************************************************************
;
;  colScan subroutine
;
;  The subroutine scans columns. It is called during each scan row event.
;  If a key in the current row being scaned has been pressed, the subroutine
;  will determine which column. when a key if found to be pressed, the
;  subroutine waits until the key has been released before continuing. This
;  method debounces the input keys.
;
;  GLOBAL REGESTERS USED: R0
;  GLOBAL BITS USED: F0(PSW.5)
;  INPUT: col1(P3.4), col2(P3.5), col3(P3.6), col4(P3.7)
;  OUTPUT: R0, F0
;
;*****************************************************************************

colScan:         JB col1, nextcol     ; check if col1 key is pressed
                 JNB col1, $          ; If yes, then wait for key release
                 JMP gotkey           ; Have key, return
nextcol:         INC R0               ; Increment keyvalue
                 JB col2, nextcol2    ; check if col2 key is pressed
                 JNB col2, $          ; If yes, then wait for key release
                 JMP gotkey           ; Have key, return
nextcol2:        INC R0               ; Increment keyvalue
                 JB col3, nextcol3    ; check if col3 key is pressed
                 JNB col3, $          ; If yes, then wait for key release
                 JMP gotkey           ; Have key, return
nextcol3:        INC R0               ; Increment keyvalue
                 JB col4, nokey       ; check if col4 key is pressed
                 JNB col4, $          ; If yes, then wait for key release
                 JMP gotkey           ; Have key, return
nokey:           INC R0               ; Increment keyvalue
                 RET                  ; finished scan, no key pressed

gotKey:          SETB F0              ; key found - set F0
                 RET                  ; and return from subroutine


;*****************************************************************************
;*****************************************************************************
;
;  init subroutine
;
;  The subroutine is used initialize the LCD during startup. 
;
;  LOCAL REGISTERS USED: None
;  INPUT: 
;  OUTPUT: LCD (P2), ENABLE (P1.4)
;
;***************************************************************************** 

init:            CLR RS               ; Register Select ( 0 = Command )
								 CLR RW               ; Read/Write ( 1 = Read ; 0 = Write )
								 clr ENABLE           ; High to Low Transition Stores the data
                 call delay           ; Waits for LCD to stabilize
                 call reset           ; Sends reset bytes to LCD
								                      ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | |
                 mov LCD, #38H        ; 1 0 0 0 0 0 1 1 1 0 0 0 Function Set Word 
                                      ;
                 call Busy            ; Check Busy Flag
                 setb ENABLE          ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch.
                 call busy            ; Check Busy Flag
                                      ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | |
                 mov LCD, #08H        ; 1 0 0 0 0 0 0 0 1 0 0 0 Display Off word
                 call Busy            ; Check Busy Flag
                 setb ENABLE          ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch.
                 call Busy            ; Check Busy Flag
                                      ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | |
                 mov LCD, #0FH        ; 1 0 0 0 0 0 0 0 1 1 1 1 Display On word.
                 call Busy            ; Check Busy Flag
                 setb ENABLE          ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch
                 call Busy            ; Check Busy Flag
                                      ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | |
                 mov LCD, #06H        ; 1 0 0 0 0 0 0 0 0 1 1 0 Entry Mode word
                 call Busy            ; Check Busy Flag
                 setb ENABLE          ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch.
                 call Busy            ; Check Busy Flag
                                      ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | |
                 mov LCD, #02H        ; 1 0 0 0 0 0 0 0 0 0 1 0 Display Home word
                 call Busy            ; Check Busy Flag
                 setb ENABLE          ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch.
                 call Busy            ; Check Busy Flag

                 ret


;*****************************************************************************
;*****************************************************************************
;
;Names subroutine
;
;Prints out the group memebers names

;*****************************************************************************

Names:
								 call cursor_off
								 mov A, #80H
								 call lcd_position

					 			 mov DPTR, #classdb   
  							 call send_string
									
        				 mov A, #0C0H
								 call lcd_position

								 mov DPTR, #fosterdb
								 call send_string

        				 mov A, #94H
								 call lcd_position

								 mov DPTR, #timmydb
								 call send_string
								 
								 
	          		 call four_second_delay

								 call Clear
								 
								 ret

;*****************************************************************************
;*****************************************************************************
;
;  Main menu text subroutine
;
;	 Setup main menu for the device
;
;*****************************************************************************


main_menu_text:
								call clear
								mov A, #80H
								call lcd_position

								mov DPTR, #pnamedb					 
                call send_string

   							mov A, #0C0H
								call lcd_position

								mov DPTR, #msensor1db
								call send_string

  							mov A, #94H
								call lcd_position

								mov DPTR, #msensor2db
								call send_string


  							mov A, #0D4H
								call lcd_position

								mov DPTR, #uvsensordb
								call send_string


mmtend:					mov A, #0C0H
							  call lcd_position

								ret

;*****************************************************************************
;*****************************************************************************
;
;  Test menu text subroutine
;
;	 Setup test menu for the device
;
;*****************************************************************************

test_menu_text:                
						 call clear
						 mov A, #80H
						 call lcd_position

						 mov DPTR, #tmlcddb
						 call send_string


             mov A, #0C0H
						 call lcd_position

						 mov DPTR, #tmsensorsdb
						 call send_string


          	 mov A, #94H
						 call lcd_position

						 mov DPTR, #tmpumpsdb
						 call send_string
       
			 
			       ret


;*****************************************************************************
;*****************************************************************************
;
;  Set desired levels subroutine
;
;	 Menu to set the desired levels for the plants
;
;  Registers: R0 for key, R1 for RAM pointer, R2 for counter
;
;*****************************************************************************


desired_levels:
						clr pump1				
						clr pump2
						
						CLR F0

						mov IE, #00h
						call delay	
		
						call clear

						mov A, #80h
						call lcd_position
						mov DPTR, #desireddb1
						call send_string

						mov A, #0C0h
						call lcd_position
						mov DPTR, #desireddb2
						call send_string

						mov A, #94h
						call lcd_position
						mov DPTR, #desireddb1
						call send_string

						mov A, #0D4h
						call lcd_position
						mov DPTR, #desireddb3
						call send_string

						call cursor_on

						mov A, #0C9h
						call lcd_position

;msensor1
dl_key:			
						clr F0

						call keyscan

						mov A, R0
						mov R7, A

						call number_zero_two

						mov 50h, A
						
						jb F0, dl_key0
						jmp dl_key



dl_key0:		clr F0

						call keyscan

						mov A, R0
						mov R6, A
						
					  cjne R7, #01h, dl_key1

						call number_zero_five

						mov 51h, A

						jb F0, dl_key2
						jmp dl_key0

dl_key1: 		call number_zero_nine

						mov 51h, A

						jb F0, dl_key2
						jmp dl_key0
						

dl_key2:		clr F0

						call keyscan

						cjne R6, #05h, dl_key3
						cjne R7, #01h, dl_key3

						call number_zero_five

						mov 52h, A

						jb F0, dl_key4
						jmp dl_key2

dl_key3:		call number_zero_nine

						mov 52h, A

						jb F0, dl_key4
						jmp dl_key2
						


;msensor2
dl_key4:								
						mov A, #0DDh
						call lcd_position

dl_key5:			
						clr F0

						call keyscan

						mov A, R0
						mov R7, A

						call number_zero_two

						mov 53h, A
						
						jb F0, dl_key6
						jmp dl_key5



dl_key6:		
						clr F0

						call keyscan

						mov A, R0
						mov R6, A

						
					  cjne R7, #01h, dl_key7

						call number_zero_five

						mov 54h, A

						jb F0, dl_key8
						jmp dl_key6

dl_key7: 		call number_zero_nine

						mov 54h, A

						jb F0, dl_key8
						jmp dl_key6
						

dl_key8:		clr F0

						call keyscan

						cjne R6, #05h, dl_key9
						cjne R7, #01h, dl_key9

						call number_zero_five

						mov 55h, A

						jb F0, dl_end
						jmp dl_key8

dl_key9:		call number_zero_nine

						mov 55h, A

						jb F0, dl_end
						jmp dl_key8



dl_end:			CLR F0

						call keyscan 

						cjne R0, #0Eh, dl_end
						clr F0
						call cursor_off
						call delay

						call main_menu_text
						mov IE, #0A0h
						
						ret



;*****************************************************************************
;*****************************************************************************
;
;  Get mumber from keypad subroutine
;
;	 Subroutine checks if grabbed key is a number, and displays it, if it is.
;	 Checks 0-9
;
;*****************************************************************************

number_zero_nine:
						cjne R0, #0dh, nzn0
						mov A, #30h
						call display
						jmp nzn_end

nzn0:				cjne R0, #00h, nzn1
						mov A, #31h
						call display
						jmp nzn_end

nzn1:				cjne R0, #01h, nzn2
						mov A, #32h
						call display
						jmp nzn_end

nzn2:				cjne R0, #02h, nzn3
						mov A, #33h
						call display
						jmp nzn_end

nzn3:				cjne R0, #04h, nzn4
						mov A, #34h
						call display
						jmp nzn_end

nzn4:				cjne R0, #05h, nzn5
						mov A, #35h
						call display
						jmp nzn_end

nzn5:				cjne R0, #06h, nzn6
						mov A, #36h
						call display
						jmp nzn_end

nzn6:				cjne R0, #08h, nzn7
						mov A, #37h
						call display
						jmp nzn_end

nzn7:				cjne R0, #09h, nzn8
						mov A, #38h
						call display
						jmp nzn_end

nzn8:				cjne R0, #0Ah, nzn_no_key
						mov A, #39h
						call display
						
nzn_end:
						ret

nzn_no_key:
						clr F0
						ret


number_zero_five:
						cjne R0, #0dh, nzf0
						mov A, #30h
						call display
						jmp nzf_end

nzf0:				cjne R0, #00h, nzf1
						mov A, #31h
						call display
						jmp nzf_end

nzf1:				cjne R0, #01h, nzf2
						mov A, #32h
						call display
						jmp nzf_end

nzf2:				cjne R0, #02h, nzf3
						mov A, #33h
						call display
						jmp nzf_end

nzf3:				cjne R0, #04h, nzf4
						mov A, #34h
						call display
						jmp nzf_end

nzf4:				cjne R0, #05h, nzf_no_key
						mov A, #35h
						call display

nzf_end:		ret

nzf_no_key:
						clr F0
						ret



number_zero_two:
						cjne R0, #0dh, nzt0
						mov A, #30h
						call display
						jmp nzt_end

nzt0:				cjne R0, #00h, nzt1
						mov A, #31h
						call display
						jmp nzt_end

nzt1:				cjne R0, #01h, nzt_no_key
						mov A, #32h
						call display
				
nzt_end:		ret

nzt_no_key: clr F0
						ret




;*****************************************************************************
;*****************************************************************************
;
;  lcd_position subroutine
;
;	 Set the cursor on specified location in ACC. 
;
;*****************************************************************************


lcd_position: 
								 mov R3, #00H
								 clr RS
								 clr RW
								 mov LCD, A
								 setb ENABLE
								 call delay
								 clr ENABLE

								 ret


;*****************************************************************************
;*****************************************************************************
;  
;  bin_to_ascii subroutine
;
;  Converts 8 bit binary number to hex ASCII numbers
;
;  Input: 8 bit binary number in ACC
;  Output: ASCII numbers in 42h (Hundreds), 41h (tens), 40h (Ones) to LCD
;
;
;
;*****************************************************************************



bin_to_ascii:		;Binary to BCD
    						mov B, #64h   ; 100
    						DIV AB        ; /100
    						mov 40h, A     ; store A in R0
    						mov A, B      ; get remainder
    						mov B, #0AH
   						  DIV AB        ; / 10
    						mov 41h, A     ; save tens elsewhere
    						mov A, B      ; get units
    						mov 42h,A      ; save in R1

								;BCD to ASCII
								mov A, 40h
								add A, #30h
								mov 40h, A
								mov A, 41h
								add A, #30h
								mov 41h, A
								mov A, 42h 
								add A, #30h
								mov 42h, A

								ret
								

;*****************************************************************************
;*****************************************************************************
;  
;  ascii_to_bin subroutine
;
;  Converts 12 bit ASCII number (in three registers) to binary number
;
;  Input: R3 (Hundreds), R4 (Tens), R5 (Ones)
;  Output: Binary number in R5
;
;
;
;*****************************************************************************

ascii_to_bin:
							clr A
							clr c
							
							mov A, R3
							subb A, #30h
							mov R3, A
							mov A, R4
							subb A, #30h
							mov R4, A
							mov A, R5
							subb A, #30h
							mov R5, A
							
							mov B, #0ah
							mov A, R4
							mul AB
							add A, R5
							mov R5, A
							mov B, #64h
							mov A, R3
							mul AB
							add A, R5
							mov 49h, A

							ret


;*****************************************************************************
;*****************************************************************************
;
;  Get Sensor levels subroutine
;
;  Subroutines that check the sensors levels.  
;
;*****************************************************************************

;UV Sensor
check_uv:		 
						 mov amx0p, #0Ch 

						 setb ad0busy
						 call delay
						 clr ad0busy

						 mov A, ADC0H
             call bin_to_ascii ; get reading from sensor
						 
						 mov A, #0DEh
						 call lcd_position

						 mov A, 40h
						 call display

						 mov A, 41h
						 call display

						 mov A, #2Eh
						 call display

						 mov A, 42h
						 call display
						  
             ret



;Moisture Sensor 1
check_moisture1:
						mov amx0p, #0Dh

						setb ad0busy
						call delay
						clr ad0busy

						mov 46h, ADC0H

						mov A, ADC0H
						call bin_to_ascii

						mov A, #0C9h
						call lcd_position

						mov A, 40h
						call display

						mov A, 41h
						call display

						mov A, 42h
						call display

						mov R3, 50h
						mov R4, 51h
						mov R5, 52h

						call ascii_to_bin

						mov A, 46h

						call compare

						cjne A, #00h, pump1_off
						setb pump1
						ret

pump1_off:	clr pump1			
 
						ret


;Moisture Sensor 2
check_moisture2:
						mov amx0p, #0Eh

						setb ad0busy
						call delay
						clr ad0busy
						call delay

						mov 47h, ADC0H

						mov A, ADC0H
						call bin_to_ascii

						mov A, #9Dh
						call lcd_position

						mov A, 40h
						call display

						mov A, 41h
						call display

						mov A, 42h
						call display

						mov R3, 53h
						mov R4, 54h
						mov R5, 55h

						call ascii_to_bin

						mov A, 47h

						call compare

						cjne A, #00h, pump2_off
						setb pump2
						ret

pump2_off:	clr pump2	

						ret


;*****************************************************************************
;*****************************************************************************
;
;  Compare subroutine
;
;  Compares the input level with the desired level
;
;*****************************************************************************

compare:
						cjne A, 49h, check_less
						mov A, #01h
						jmp cmp_end

check_less:
						jc less_than
						mov A, #01h
						jmp cmp_end


less_than:	mov A, #00h

cmp_end:		ret 



;*****************************************************************************
;*****************************************************************************
;
;  Test LCD subroutine
;
;	 Fill all dots on the LCD to test if any are dead
;
;*****************************************************************************

lcd_test:
					 call clear

					 mov R0, #80H						
						
lcdt1:		 mov A, R0
					 call lcd_position
					 mov A, #0FFH
					 call display
					 inc R0
					 cjne R0, #94H, lcdt1
					 
					 mov R0, #0C0H

lcdt2:		 mov A, R0
					 call lcd_position
					 mov A, #0FFH
					 call display
					 inc R0
					 cjne R0, #0D4H, lcdt2					  

					 mov R0, #94H

lcdt3:		 mov A, R0
					 call lcd_position
					 mov A, #0FFH
					 call display
					 inc R0
					 cjne R0, #0A8H, lcdt3	

					 mov R0, #0D4H

lcdt4:		 mov A, R0
					 call lcd_position
					 mov A, #0FFH
					 call display
					 inc R0
					 cjne R0, #0E8H, lcdt4


					 call four_second_delay

					 call Clear
						
					 mov R0, #0
					 
					 call test_menu_text	

					 ret



;*****************************************************************************
;*****************************************************************************
;
;  Test Sensors subroutine
;
;  Tests the sensors
;
;*****************************************************************************

sensors_test:

            ;UV Sensor Test	
						;--------------
						mov amx0p, #00Ch 
            setb ad0busy
						call delay
						clr ad0busy 

						clr F0

            	
					  call clear
						mov A, #80h
						call lcd_position

						mov DPTR, #uvtestdb1
						call send_string

									
            mov A, #0C0h
						call lcd_position

						mov DPTR, #uvtestdb2
						call send_string


            mov A, #94h
						call lcd_position

						mov DPTR, #testreadydb
						call send_string



uvkey:
						call keyscan

						cjne R0, #0Eh, uvk1
						mov A, ADC0L
						cjne A, #00h, uvpass
						call fail
						jmp uvend
uvpass:	    call pass
						
uvcont1:		CLR F0
						jmp uvend

uvk1:       cjne R0, #0Ch, uvkey
						call test_menu_text
						ret

uvend:      call four_second_delay


						;Moisture sensor 1 test
						;----------------------
						mov amx0p, #00Dh
						setb ad0busy
						call delay
						clr ad0busy

						clr F0

						mov A, #80h
						call lcd_position

						mov DPTR, #msensortestdb1
						call send_string

						mov A, #0C0h
						call lcd_position
						
						mov DPTR, #msensortestdb2
						call send_string

						mov A, #94h
						call lcd_position
						
						mov DPTR, #testreadydb
						call send_string


m1key:
						call keyscan

						cjne R0, #0Eh, m1k1
						mov A, ADC0L
						cjne A, #00h, m1pass
						call fail
						jmp m1end
m1pass:	    call pass
						
m1cont1:		CLR F0
						jmp m1end

m1k1:       cjne R0, #0Ch, m1key
						call test_menu_text
						ret

m1end:      call four_second_delay						


						;Moisture sensor 2 test
						;----------------------
						mov amx0p, #00Dh
						setb ad0busy
						call delay
						clr ad0busy

						clr F0

						mov A, #80h
						call lcd_position

						mov DPTR, #msensortestdb1
						call send_string

						mov A, #0C0h
						call lcd_position
						
						mov DPTR, #msensortestdb3
						call send_string

						mov A, #94h
						call lcd_position
						
						mov DPTR, #testreadydb
						call send_string


m2key:
						call keyscan

						cjne R0, #0Eh, m2k1
						mov A, ADC0L
						cjne A, #00h, m2pass
						call fail
						jmp m2end
m2pass:	    call pass
						
m2cont2:		CLR F0
						jmp m2end

m2k1:       cjne R0, #0Ch, m2key
						call test_menu_text
						ret

m2end:      call four_second_delay
												


					

						CLR F0
						call test_menu_text
						
            ret




pass: ;if test passes (reads a voltage)

						call clear

						mov A, #80h
						call lcd_position

						mov DPTR, #testpassdb
						call send_string

        		ret						
						
fail: ;if test fails (doesn't read a voltage)
						
						call clear

						mov A, #80h
						call lcd_position

						mov DPTR, #testfaildb
						call send_string

        		ret



;*****************************************************************************
;*****************************************************************************
;
;  motors_test subroutine
;
;  Tests the motors
;
;
;*****************************************************************************


pumps_test:
						clr F0
							
						call clear


						mov A, #80h
						call lcd_position
						mov DPTR, #pumptestdb1
						call send_string

						mov A, #0C0h
						call lcd_position
						mov DPTR, #pumptestdb2
						call send_string

						mov A, #94h
						call lcd_position
						mov DPTR, #testreadydb
						call send_string

pumpkey:		
						call keyscan
						
						cjne R0, #0Eh, ptk0
						CLR F0
						jmp pump_on

ptk0:				cjne R0, #0Ch, pumpkey
						CLR F0
						jmp pump_end

pump_on:
						call clear
						
						mov DPTR, #pumptestdb3
						call send_string

						setb pump1
						setb pump2

						call four_second_delay

						clr pump1
						clr pump2

						
pump_end:	
						call test_menu_text
						ret
						



;*****************************************************************************
;*****************************************************************************
;
;  TIMER2_ISR interrupt service routine
;
;  Every 0.2 seconds this ISR will be called.
;  You will need to add code to take action during this IRS.
;
;*****************************************************************************

Timer2_ISR:

;         ADD YOUR TIMER2 ISR CODE HERE!!!!
						
					  
						call check_uv

					  mov amx0p, #0Dh
						call check_moisture1

						mov amx0p, #0Eh
						call check_moisture2

						

;         YOUR T2ISR CODE SHOULD STOP HERE!!!

            clr  TF2H                 ; Clears Timer 2 flag because unlike
                                      ;  timers 0 & 1 the hardware does not
                                      ;  clear timer 2 flag automatically
                                      ;  during an ISR
            reti                      ; Return to "where ever" from interrupt



;*****************************************************************************
;*****************************************************************************
;
; TIMER2_INIT subroutine
;
; This subroutine initializes Timer 2 to generate an interupt every 0.2
; seconds.
;
;*****************************************************************************

Timer2_Init:
            mov  TMR2RLL, #LOW(-50000) ; Load low byte reload value
            mov  TMR2RLH, #HIGH(-50000) ; Loads high byte reload value
            mov  TMR2L, #LOW (-50000) ; Loads initial byte value
            mov  TMR2H, #HIGH(-50000) ; Loads initial byte value
            mov  TMR2CN,  #00000100B  ; Configures Timer2
                                      ; 00000100B
                                      ;      1> Sets T2 to run 
            mov  IE, #10100000B       ; Enables interrupts
                                      ; 10100000B
                                      ; 1> Enable Global interrupt
                                      ;   1> Enable Timer2 interrupt
            ret                       ; Return from CALL



;*****************************************************************************
;*****************************************************************************
;
;  CURSOR_OFF subroutine
;
;  Turns LCD cursor off.
;
;  INPUT:  none
;  OUTPUT: Sends command to LCD to turn cursor and cursor position character
;           off.
;  ACTION: Blanks cursor and cursor position character.
;
;*****************************************************************************

cursor_off:
            clr  RS                   ; Register Select ( 0 = Instruction )
            clr  RW
            mov  LCD, #00001100B      ; Sends data to LCD
            setb Enable               ; Latches the data
            call delay                ; Waits
            clr  Enable               ; Then resets the latch
            ret 

;*****************************************************************************
;*****************************************************************************
;
;  CURSOR_ON subroutine
;
;  Turns LCD cursor on.
;
;  INPUT:  none
;  OUTPUT: Sends command to LCD to turn cursor and cursor position character
;           on.
;  ACTION: Turns on cursor and cursor position character.
;
;*****************************************************************************

cursor_on:
            clr  RS                   ; Register Select ( 0 = Instruction )
            clr  RW
            mov  LCD, #00001111B      ; Sends data to LCD
            setb Enable               ; Latches the data
            call delay                ; Waits
            clr  Enable               ; Then resets the latch
            ret
														
;*****************************************************************************
;*****************************************************************************
;
;  clear subroutine
;
;  Clears the LCD.
;  Used one 8-bit data move to send the Clear Display Instruction command
;  (01H) to the LCD.  
;
;  The subroutine is used during initialization and when the display is full
;  to clear the display before it wraps back to DDRAM address 00.
;
;  INPUT: none
;  OUTPUT: Port 2 (LCD) and P1.4 (ENABLE)
;
;***************************************************************************** 

clear:                                ; E X R R D D D D D D D D   
                                      ; | | S W 7 6 5 4 3 2 1 0 
                                      ; | | | | | | | | | | | | 
                 mov LCD, #01H        ; 1 0 0 0 0 0 0 0 0 0 0 1 Clear Display word
                 call Busy            ; Check Busy Flag
                 setb ENABLE           ; Latched the first byte.
                 call delay           ; Waits.
                 clr ENABLE          ; Then resets latch
                 ret


;*****************************************************************************
;*****************************************************************************
;
;  send_string subbroutine
;
;  This routine sends messgaes that terminate with NULL to the display
;  subroutine.
;
;  INPUT: DPTR pointing to the DB table to send.
;  OUTPUT: characters to DISPLAY
;  USES: Accumulator and R4.
;
;*****************************************************************************

send_string:
            mov  R4, #0
sstr1:      mov  A, R4
            movc A, @A+DPTR
            cjne A, #0, sstr2
            jmp  exit_sstr
sstr2:      call DISPLAY
            call DELAY
            inc  R4
            jmp  sstr1
exit_sstr:  ret


;*****************************************************************************
;*****************************************************************************
;
;  display subroutine
;
;  Moves the control or ASCII byte in the accumulator into the LCD 8-bits at
;  a time. 
;
;  LOCAL REGISTERS USED: R3
;  INPUT: byte in the Accumulator
;  OUTPUT: One byte to the LCD. 
;
;*****************************************************************************

display:                              ; The data to be sent is in A.
                 setb RS              ; Register Select ( 1 = Data )                     
                 mov LCD, A           ; Sends data to LCD
								 setb ENABLE          ; Latches the data.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets the latch.

next3:           ret



;*****************************************************************************
;*****************************************************************************
;
;  delay subroutine
;
;  This subroutine is a simple delay loop that is used to provide timing for
;  the LCD interface.
;
;  LOCAL REGISTERS USED: R5
;  INPUT: none
;  OUTPUT: none
;  ACTION: Provides time delay for the LCD interface.
;
;*****************************************************************************

delay:           

                 mov   R5, #00h
                 djnz  R5, $

                 ret


;*****************************************************************************
;*****************************************************************************
;
;  delay subroutine
;
;  This subroutine is a simple delay loop that is used to provide timing for
;  the LCD interface.
;
;  LOCAL REGISTERS USED: R1, 
;  INPUT: none
;  OUTPUT: none
;  ACTION: Waits for ACCx100 amount of milliseconds
;
;*****************************************************************************

four_second_delay:
						mov TMOD, #01H
fsdelay:	 	mov R1, #40
fsagain:		mov TH0, high(-100)
						mov TL0, low(-100)
						setb TR0
fswait:			jnb TF0, fswait
						clr TF0
						clr TR0
						djnz R1, fsagain

						ret

;*****************************************************************************
;*****************************************************************************
;
;  reset
;
;  Initialization by instruction
;  This subroutine sends a Function Set byte (30H) to the LCD three times so that the
;  LCD will reset correctly and communicate with the 8051.
;
;  INPUT: none
;  OUTPUT: LCD (P2), ENABLE (P1.4)
;
;*****************************************************************************

reset:           
								 call delay
                 mov LCD, #30H        ; Writes Function Set.
                 setb ENABLE          ; Latches Instruction.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets latch.
								 call Busy            ; Check Busy Flag delay
                 mov LCD, #30H        ; Writes Function Set.
                 setb ENABLE          ; Latches Instruction.
                 call delay           ; Waits.
                 clr ENABLE           ; Then resets the latch.
                 call Busy            ; Check Busy Flagdelay
								 mov LCD, #30H        ; Writes Function Set.
                 setb ENABLE          ; Latches Instruction
                 call delay           ; Waits
                 clr Enable           ; Then resets the latch
				         call Busy            ; Check Busy Flag
                 ret 

;*****************************************************************************
;
;Busy
;
; This Subroutine check the Busy Flag (DB7) to ensure the LCD is not busy
;
;INPUT  P2.7
;*****************************************************************************
Busy:            
								 clr RS
								 setb RW
								 jb P2.7, $
								 clr RW
                 ret
;
;*****************************************************************************
;
;*****************************************************************************
;
;  Tables
;
;*****************************************************************************



keys:            DB  '1','2','3',NULL,'4','5','6','B','7','8','9','C','*','0','#','D'

classdb:         DB  'ECET 3220-Fall 2017',NULL
fosterdb:				 DB	 '   Foster Gorman',NULL
timmydb:				 DB	 '   Timmy Adeniyi',NULL

pnamedb:         DB	 '------EZ-Water------',NULL
msensor1db:			 DB  'Plant 1: ',NULL
msensor2db:			 DB	 'Plant 2: ',NULL
uvsensordb:      DB  'UV Index: ',NULL

tmlcddb:				 DB  '1. Test LCD',NULL
tmsensorsdb:		 DB	 '2. Test Sensors',NULL
tmpumpsdb:			 DB  '3. Test Pumps',NULL

uvtestdb1:       DB	 'Put the UV sensor',NULL
uvtestdb2:			 DB  'in direct sunlight.',NULL
testreadydb:     DB  'Press # when ready.',NULL
msensortestdb1:  DB  'Put moisture sensor',NULL
msensortestdb2:  DB  '1 in the soil.',NULL
msensortestdb3:	 DB  '2 in the soil.',NULL
testpassdb:      DB  'Test Passed!',NULL
testfaildb:      DB  'Test Failed!',NULL
pumptestdb1:		 DB  'Make sure the tubes',NULL
pumptestdb2:		 DB  'are in the pots.',NULL
pumptestdb3:     DB  ' Testing motors',NULL

desireddb1:      DB	 'Desired level for', NULL
desireddb2:			 DB  'plant 1:',NULL
desireddb3:			 DB  'plant 2:',NULL 


                 END