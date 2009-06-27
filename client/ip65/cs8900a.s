; Ethernet driver for CS8900A chip (as used in RR-NET and Uthernet adapters)
;
; Based on Doc Bacardi's tftp source


.ifndef NB65_API_VERSION_NUMBER
  .define EQU     =
  .include "../inc/nb65_constants.i"
.endif

.include "../inc/common.i"
.include "cs8900a.i"

	.export eth_init
	.export eth_rx
	.export eth_tx

	.export eth_inp
	.export eth_inp_len
	.export eth_outp
	.export eth_outp_len

	.exportzp eth_dest
	.exportzp eth_src
	.exportzp eth_type
	.exportzp eth_data

	.import cs_init
	.import cs_packet_page
	.import cs_packet_data
	.import cs_rxtx_data
	.import cs_tx_cmd
	.import cs_tx_len

	.import cfg_mac

  .import ip65_error

	.macro write_page page, value
	lda #page/2
	ldx #<value
	ldy #>value
	jsr cs_write_page
	.endmacro


	.segment "IP65ZP" : zeropage

eth_packet:	.res 2


	.bss

; input and output buffers
eth_inp_len:	.res 2		; input packet length
eth_inp:	.res 1518	; space for input packet
eth_outp_len:	.res 2		; output packet length
eth_outp:	.res 1518	; space for output packet

; ethernet packet offsets
eth_dest	= 0		; offset of destination mac address in an ethernet packet
eth_src		= 6		; offset of source address in an ethernet packet
eth_type	= 12		; offset of packet type in an ethernet packet
eth_data	= 14		; offset of packet data in an ethernet packet


	.code

;initialize the ethernet adaptor
;inputs: none
;outputs: carry flag is set if there was an error, clear otherwise
eth_init:
	jsr cs_init

	lda #0			; check magic signature
	jsr cs_read_page
	cpx #$0e
	bne @notfound
	cpy #$63
	bne @notfound

	lda #1
	jsr cs_read_page
	cpx #0
	bne @notfound
	; y contains chip rev

	write_page pp_self_ctl, $0055	; $0114, reset chip

	write_page pp_rx_ctl, $0d05	; $0104, accept individual and broadcast packets

	lda #pp_ia/2			; $0158, write mac address
	ldx cfg_mac
	ldy cfg_mac + 1
	jsr cs_write_page

	lda #pp_ia/2 + 1
	ldx cfg_mac + 2
	ldy cfg_mac + 3
	jsr cs_write_page

	lda #pp_ia/2 + 2
	ldx cfg_mac + 4
	ldy cfg_mac + 5
	jsr cs_write_page

	write_page pp_line_ctl, $00d3	; $0112, enable rx and tx

	clc
	rts

@notfound:
	sec
	rts


;receive a packet
;inputs: none
;outputs:
; if there was an error receiving the packet (or no packet was ready) then carry flag is set
; if packet was received correctly then carry flag is clear, 
; eth_inp contains the received packet, 
; and eth_inp_len contains the length of the packet
eth_rx:
	lda #$24			; check rx status
	sta cs_packet_page
	lda #$01
	sta cs_packet_page + 1

	lda cs_packet_data + 1
	and #$0d
	bne :+

	sec				; no packet ready
	rts

:	lda cs_rxtx_data + 1		; ignore status
	lda cs_rxtx_data

	lda cs_rxtx_data + 1		; read packet length
	sta eth_inp_len + 1
	tax				; save
	lda cs_rxtx_data
	sta eth_inp_len

	lda #<eth_inp			; set packet pointer
	sta eth_packet
	lda #>eth_inp
	sta eth_packet + 1

	ldy #0
	cpx #0				; < 256 bytes left?
	beq @tail

@get256:
	lda cs_rxtx_data
	sta (eth_packet),y
	iny
	lda cs_rxtx_data + 1
	sta (eth_packet),y
	iny
	bne @get256
	inc eth_packet + 1
	dex
	bne @get256

@tail:
	lda eth_inp_len			; bytes left / 2, round up
	lsr
	adc #0
	beq @done
	tax

@get:
	lda cs_rxtx_data
	sta (eth_packet),y
	iny
	lda cs_rxtx_data + 1
	sta (eth_packet),y
	iny
	dex
	bne @get

@done:
	clc
	rts


; send a packet
;inputs:
; eth_outp: packet to send
; eth_outp_len: length of packet to send
;outputs:
; if there was an error sending the packet then carry flag is set
; otherwise carry flag is cleared
eth_tx:
	
	lda #$c9			; ask for buffer space
	sta cs_tx_cmd
	lda #0
	sta cs_tx_cmd + 1

	lda eth_outp_len		; set length
	sta cs_tx_len
	lda eth_outp_len + 1
	sta cs_tx_len + 1
	cmp #7
  bmi :+
  lda #NB65_ERROR_INPUT_TOO_LARGE
  sta ip65_error
	sec				; oversized packet
	rts

:	lda #<pp_bus_status		; select bus status register
	sta cs_packet_page
	lda #>pp_bus_status
	sta cs_packet_page + 1

@waitspace:
	lda cs_packet_data + 1		; wait for space
	ldx cs_packet_data
	lsr
	bcs @gotspace
	jsr @done			; polling too fast doesn't work, delay added by David Schmidt
	jmp @waitspace
@gotspace:
	ldax #eth_outp			; send packet
	stax eth_packet

	ldy #0
	ldx eth_outp_len + 1
	beq @tail

@send256:
	lda (eth_packet),y
	sta cs_rxtx_data
	iny
	lda (eth_packet),y
	sta cs_rxtx_data + 1
	iny
	bne @send256
	inc eth_packet + 1
	dex
	bne @send256

@tail:
	ldx eth_outp_len
	beq @done

@send:
	lda (eth_packet),y
	sta cs_rxtx_data
	dex
	beq @done
	iny
	lda (eth_packet),y
	sta cs_rxtx_data + 1
	iny
	dex
	bne @send

@done:					; also used by timeout code above
	clc
	rts


; read X/Y from page A * 2
cs_read_page:
	asl
	sta cs_packet_page
	lda #0
	rol
	sta cs_packet_page + 1
	ldx cs_packet_data
	ldy cs_packet_data + 1
	rts

; write X/Y to page A * 2
cs_write_page:
	asl
	sta cs_packet_page
	lda #0
	rol
	sta cs_packet_page + 1
	stx cs_packet_data
	sty cs_packet_data + 1
	rts
