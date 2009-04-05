;test the "NETBOOT65 Cartridge API"
.include "../inc/nb65_constants.i"
 

; load A/X macro
	.macro ldax arg
	.if (.match (.left (1, arg), #))	; immediate mode
	lda #<(.right (.tcount (arg)-1, arg))
	ldx #>(.right (.tcount (arg)-1, arg))
	.else					; assume absolute or zero page
	lda arg
	ldx 1+(arg)
	.endif
	.endmacro

; store A/X macro
	.macro stax arg
	sta arg
	stx 1+(arg)
	.endmacro	


  print_a = $ffd2
    
  .zeropage
temp_ptr:		.res 2
  
  .bss
  nb65_param_buffer: .res $20  


	.segment "STARTUP"    ;this is what gets put at the start of the file on the C64

	.word basicstub		; load address

.macro print_failed
  ldax #failed_msg
	ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
  print_cr
.endmacro


.macro print_ok
  ldax #ok_msg
	ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
  print_cr
.endmacro

.macro print_cr
  lda #13
	jsr print_a
.endmacro


basicstub:
	.word @nextline
	.word 2003
	.byte $9e
	.byte <(((init / 1000) .mod 10) + $30)
	.byte <(((init / 100 ) .mod 10) + $30)
	.byte <(((init / 10  ) .mod 10) + $30)
	.byte <(((init       ) .mod 10) + $30)
	.byte 0
@nextline:
	.word 0

init:
  
  lda #$01    
  sta $de00   ;turns on RR cartridge (since it will have been banked out when exiting to BASIC)
   
  ldy #NB65_INIT_IP
  jsr NB65_DISPATCH_VECTOR 
	bcc :+  
  print_failed
  jsr print_errorcode
  jmp bad_boot    
:

  ldy #NB65_GET_DRIVER_NAME
  jsr NB65_DISPATCH_VECTOR 

  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR

  ldax #initialized
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR

  print_cr

  ldy #NB65_INIT_DHCP
  jsr NB65_DISPATCH_VECTOR 

	bcc :+  
  print_failed
  jsr print_errorcode
  jmp bad_boot    
:
 
  ldy #NB65_PRINT_IP_CONFIG
  jsr NB65_DISPATCH_VECTOR 
 
  jmp callback_test
  
  ldax #hostname_1
  jsr do_dns_query  

  ldax #hostname_2
  jsr do_dns_query  

  ldax #hostname_3
  jsr do_dns_query  

  ldax #hostname_4
  jsr do_dns_query  

  ldax #hostname_5
  jsr do_dns_query  

  ldax #hostname_6
  jsr do_dns_query  


callback_test:
  
  ldax  #64
  stax nb65_param_buffer+NB65_UDP_LISTENER_PORT
  ldax  #udp_callback
  stax nb65_param_buffer+NB65_UDP_LISTENER_CALLBACK
  ldax  #nb65_param_buffer
  ldy   #NB65_UDP_ADD_LISTENER
  jsr NB65_DISPATCH_VECTOR 
	bcc :+  
  print_failed
  jsr print_errorcode
  jmp bad_boot    
:

  ldax #listening
	ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 

@loop_forever:
  jsr NB65_PERIODIC_PROCESSING_VECTOR
  jmp @loop_forever
  
  jmp $a7ae  ;exit to basic
  
udp_callback:

  ldax #nb65_param_buffer
  ldy #NB65_GET_INPUT_PACKET_INFO
  jsr NB65_DISPATCH_VECTOR 

  ldax #port
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR

  lda nb65_param_buffer+NB65_LOCAL_PORT+1
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR

  lda nb65_param_buffer+NB65_LOCAL_PORT
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR

  print_cr

  ldax #recv_from
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 

  ldax #nb65_param_buffer+NB65_REMOTE_IP
  ldy #NB65_PRINT_DOTTED_QUAD
  jsr NB65_DISPATCH_VECTOR 
  
  lda #' '
  jsr print_a
  ldax #port
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR
  
  lda nb65_param_buffer+NB65_REMOTE_PORT+1
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR
  lda nb65_param_buffer+NB65_REMOTE_PORT
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR
  
  print_cr
  
  ldax #length
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR

  lda nb65_param_buffer+NB65_PAYLOAD_LENGTH+1
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR
  lda nb65_param_buffer+NB65_PAYLOAD_LENGTH
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR
  
  ldax #data
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR

  ldax nb65_param_buffer+NB65_PAYLOAD_POINTER
  stax temp_ptr
  ldx nb65_param_buffer+NB65_PAYLOAD_LENGTH ;assumes length is < 255
  ldy #0
:
  lda (temp_ptr),y
  jsr print_a
  iny
  dex
  bne :-
  
  print_cr

  rts  
  
do_dns_query: ;AX points at the hostname on entry 
  stax nb65_param_buffer+NB65_DNS_HOSTNAME

  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 

  lda #' '
  jsr print_a
  lda #':'
  jsr print_a
  lda #' '
  jsr print_a
  ldax  #nb65_param_buffer
  ldy #NB65_DNS_RESOLVE_HOSTNAME
  jsr NB65_DISPATCH_VECTOR 
  bcc :+
  ldax #dns_lookup_failed_msg
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
  print_cr
  jmp print_errorcode
:  
  ldax #nb65_param_buffer+NB65_DNS_HOSTNAME_IP
  ldy #NB65_PRINT_DOTTED_QUAD
  jsr NB65_DISPATCH_VECTOR
  print_cr
  rts

bad_boot:
  ldax  #press_a_key_to_continue
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
  jsr get_key
  jmp $fe66   ;do a wam start


print_errorcode:
  ldax #error_code
  ldy #NB65_PRINT_ASCIIZ
  jsr NB65_DISPATCH_VECTOR 
  ldy #NB65_GET_LAST_ERROR
  jsr NB65_DISPATCH_VECTOR
  ldy #NB65_PRINT_HEX
  jsr NB65_DISPATCH_VECTOR
  print_cr
  rts


;use C64 Kernel ROM function to read a key
;inputs: none
;outputs: A contains ASCII value of key just pressed
get_key:
  jsr $ffe4
  cmp #0
  beq get_key
  rts
  
	.rodata

buffer1: .res 256
hostname_1:
  .byte "SLASHDOT.ORG",0          ;this should be an A record

hostname_2:
  .byte "VICTA.JAMTRONIX.COM",0   ;this should be a CNAME

hostname_3:
  .byte "FOO.BAR.BOGUS",0         ;this should fail

hostname_4:                       ;this should work (without hitting dns)
  .byte "111.22.3.4",0

hostname_5:                       ;make sure doesn't get treated as a number
  .byte "3COM.COM",0

hostname_6:
  .repeat 200
  .byte 'X'
  .endrepeat
  .byte 0     ;this should generate an error as it is too long

recv_from:  
  .asciiz "RECEIVED FROM: "
  
listening:  
  .byte "LISTENING.",13,0

  
initialized:  
  .byte " INITIALIZED.",13,0

port:  
  .byte "PORT: ",0

length:  
  .byte "LENGTH: ",0
data:
  .byte "DATA: ",0
  
error_code:  
  .asciiz "ERROR CODE: "
press_a_key_to_continue:
  .byte "PRESS A KEY TO CONTINUE",13,0

failed_msg:
	.byte "FAILED", 0

ok_msg:
	.byte "OK", 0
 
dns_lookup_failed_msg:
 .byte "DNS LOOKUP FAILED", 0
