;Hand-Eye Cordination Game
;Author: Moris Scofield Mukwayi


; PORTC0-PORTC3 reserved for the seven segment that displays high
; PORTC4 Trigger of the sensor
; PORTC5 Slide switch
; PORTD7-Green LED
; PORTD6-Yellow LED
; PORTD5-Red LED
; PORTD4-Echo pin of the sensor

.org 0x000
rjmp initislise_inputs ; Interrupt vector for initializing the game
.org 0x00A
rjmp echo_interrupt_handler ; Jump here when the edge to the echo changes
.org 0x01A
rjmp pulse_handler ; Jump here to send a pulse to the sensor

.def current_game_mode = r0 ; Define a register to store the current game mode
.def random_seed = r1 ; Define the seed that will generate a new random number every time
.def dummy_reg = r16 ; Define a temporary register that will be used to load data into other registers
.def current_timer_val = r17 ; Define a register to hold the value of timer 2 afer 1 echo pulse interval
.def current_region = r18 ; Define the register that stores the current region
.def current_random = r19 ; Define the register that will store the current random number
.def current_turn = r20 ; Define the register to keep track of the current turns
.def current_score = r21 ; Define a register that will store the current score


initislise_inputs: ; Initialize all input output ports
 
	ser dummy_reg
	out ddrb, dummy_reg
	out ddrc, dummy_reg
	out ddrd, dummy_reg
	cbi ddrd, 4 ; DDR for input must be set to low
	cbi ddrc, 5 ; DDR for input must be set to low
	clr dummy_reg
	out portb, dummy_reg
	out portc, dummy_reg
	out portd, dummy_reg

rjmp determine_current_game_mode

finish_setup: ; Return here when the game mode has been determined

	ldi dummy_reg, 0b00000100 ; Setup Pinchange interrupts in portd  
	sts PCICR, dummy_reg  ; Load the value into the pin change interrupt control register
	
	ldi dummy_reg, 0b00010000 ; Initialize pind, 4 to recieve a pin change interrupt
	sts PCMSK2, dummy_reg ; Load the value into pin change mask register 2

	ldi dummy_reg, 0b00001101 ; Set the pre-scaler to slow down timer 1 
	sts TCCR1B, dummy_reg ; Load the value into tc1 control register B
	ldi dummy_reg, 0b00000101 ; Set the prescaler to slow down timer 2
	out TCCR0B, dummy_reg ; Load the value into tc2 control register B
	 
	ldi dummy_reg, 173
	mov random_seed, dummy_reg
	clr current_score ; Initialze the current score
	clr current_turn ; Initialze the current_turns
	clr dummy_reg ; The timer operates in normal mode (No PWM) and overflows when it reaches the value set in the determine_current_game_mode routine
	sts TCCR1A, dummy_reg ; Load the value into tc1 control register A
	ldi dummy_reg, 0b00000010 ; Enable timer 1 overflow interrups
	sts TIMSK1, dummy_reg ; Load the value in the timer/counter 1 interrupt mask register

	sei ; enable global interrupts

main_loop:
rjmp main_loop


determine_current_game_mode:

	sbis pinc, 5 ; If pinc 5 is set to high skip the next instruction
	rjmp set_to_test_mode

	set_to_playing_mode: ; If pinc 5 is set to low set the game mode to playing mode
		ldi dummy_reg, 1
		mov current_game_mode, dummy_reg ; Clear the game_mode register which indicates that we're in test mode

		// Load 62500 into the timer. This number in combination with the prescaler that will be set in the finish_setup routine, 
		// makes timer 1 overflow after 4 seconds
		ldi dummy_reg, 0xF4
		sts OCR1AH, dummy_reg
		ldi dummy_reg, 0x24 	
		sts OCR1AL, dummy_reg
	rjmp finish_setup

	set_to_test_mode: ; If pinc 5 is set to high set the game mode to test mode
		clr current_game_mode ; Clear the game_mode register which indicates that we're in test mode

		// Load 15625 into the timer. This number in combination with the prescaler that will be set in the finish_setup routine,
		// makes timer 1 overflow after 1 seconds
		ldi dummy_reg, 0x3D
		sts OCR1AH, dummy_reg
		ldi dummy_reg, 0x09 	
		sts OCR1AL, dummy_reg
	rjmp finish_setup


echo_interrupt_handler:

	sbis pind, 4 ; If pinc 5 is set to high skip the next instruction
	rjmp handle_low_echo_input

	handle_high_echo_input: ; When a high from the echo is recieved handle it here
		clr dummy_reg ; Restart the timer we get the value when the interrupt returns for low
		out TCNT0, dummy_reg ; Load the value directly into the register that stores the timer value
	reti

	handle_low_echo_input: ; When a low from an echo is recieved handle it here
			in current_timer_val, TCNT0
			rjmp check_region
		back_to_int: ; Return here when were done checking which region we're in
			sbrs current_game_mode, 0 ; If the current game mode is test mode, output the region
			out portb, current_region
			sbrc current_game_mode, 0 ; If the current game mode is play mode, calculate the score 
			rjmp calculate_new_score  
		back_to_int_2:
			sbrc current_game_mode, 0 ;; If the current game mode is play mode, calculate the score
			rjmp next_turn
		back_to_int_3:
			sbrc current_game_mode, 0; If the current game mode is play mode, generate a ranom number
			rjmp generate_random_number
		back_to_int_4:

	reti

pulse_handler:
	sbi portc, 4 ; Send a high to the trigger of the sensor
	// Standard delay that lasts for roughly 14 micro seconds to make sure enough time has passed
	ldi  dummy_reg, 74
	decrement_dummy: dec  dummy_reg
    brne decrement_dummy
	cbi portc, 4 ; Send a low to the trigger of the sensor
reti

check_region:; The allowed play area is between is between 2 and 20 cm away from the sensor seperated into 4 regions. This routine checks if we're within those limits
				
	check_for_limit: 
		cpi current_timer_val, 16  ; If the distance away from the sensor is less than 16cm, check if we're in region 4.
		brlo check_for_region_4
		ldi dummy_reg, 0 ; Else we're out of bounds and save the region as 0
		rjmp save_region ; save the region
	check_for_region_4:
		cpi current_timer_val, 12 ; If the distance away from the sensor is less than 12cm, check if we're in region 3. 
		brlo check_for_region_3
		ldi dummy_reg, 4 ; Else we're in region 4
		rjmp save_region ; save the region
	check_for_region_3:
		cpi current_timer_val, 8 ; If the distance away from the sensor is less than 8cm, check if we're in region 2.
		brlo check_for_region_2
		ldi dummy_reg, 3 ; Else we're in region 3
		rjmp save_region ; save the region
	check_for_region_2:
		cpi current_timer_val, 4 ; If the distance away from the sensor is between 8cm and 4cm, We're in region 1.
		brlo in_region_1
		ldi dummy_reg, 2 ; Else we're in region 2
		rjmp save_region ; save the region
	in_region_1:
		ldi dummy_reg, 1 ; Else we're in region 1
		
		save_region: ; store the region for future use here
			mov current_region, dummy_reg

rjmp back_to_int ; Go back to echo_interrupt_handler

generate_random_number:

	add current_random, random_seed
	swap random_seed
	generate:
		cpi current_random, 4
		brlo save_random
		subi current_random, 4
		rjmp generate
	save_random:
		inc current_random
		out portb, current_random
rjmp back_to_int_4

calculate_new_score:
	
	cbi portd, 7 ; Turn off green LED
	cbi portd, 6 ; Turn off Yellow LED
	cbi portd, 5 ; Turn off Red LED

	clr dummy_reg
	cp current_turn, dummy_reg
	breq back_to_int_2

	cp current_random, current_region ; If region is correct increment
	breq increment_score

	cpi current_region, 0 ; If no player detected, do not dincrement
	breq no_score

	dec current_score ; otherwise decrement
	sbi portd, 5
	rjmp back_to_int_2

	increment_score: ; Add 2 to the score
		inc current_score
		inc current_score
		sbi portd, 7
	rjmp back_to_int_2

	no_score: ; Dont add to the score and turn on the orange LED
		sbi portd, 6

rjmp back_to_int_2

next_turn:
	
	inc current_turn ; increment the current turn
	ldi dummy_reg, 7
	cp current_turn, dummy_reg ; If the number of turns is 7 or higher
	brsh display_score ; Output the score
rjmp back_to_int_3

display_score:
	cli ; Disable all global interrupts

	// Turn off all LED's 
	cbi portd, 7
	cbi portd, 6
	cbi portd, 5

	cpi current_score, 10 ; If the current score is less than 10 only show the units
	brlo display_without_tens
	cpi current_score, 13 ; If the current score is greater than 13, its a negative number in unsigned form and must be converted
	brsh display_negative
	subi current_score, 10
	out portb, current_score
	ldi dummy_reg, 1
	out portc, dummy_reg
	rjmp final_loop

	display_without_tens: 
		out portb, current_score
		rjmp final_loop

	display_negative:
		neg current_score ; Take the two's complement of the score
		out portb, current_score
		sbi portd, 5
		rjmp final_loop
final_loop:

rjmp final_loop