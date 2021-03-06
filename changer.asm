	processor 16f716
        include "p16f716.inc"
        include "coff.inc"
        __CONFIG _HS_OSC & _WDT_ON & _CP_OFF & _BOREN_OFF
        radix dec

        CONSTANT IRQ_W=0x7f
        CONSTANT IRQ_STATUS=0x7e
        CONSTANT COMMAND=0x7d
        CONSTANT SRQ_COUNT=0x7c

        CONSTANT XFER_TMP_BUF=0x30
        CONSTANT RESP_BUF=0x40
        CONSTANT RESP_BUF_LEN=0x4F

        ; 0x30 - 0x38 send/receive temp space
        ; 0x40 - 0x4E command response buffer

MAIN CODE
start

        .sim ".frequency=20e6"
        .sim "module library libgpsim_modules"
        .sim "module load usart U1"

        .sim "node n0"
        .sim "node n1"

        .sim "attach n0 portb2 U1.RXPIN"
        .sim "attach n1 portb1 U1.TXPIN"

        .sim "U1.txbaud = 19200"
        .sim "U1.rxbaud = 19200"

        org 0
        goto main
        nop
        nop
        nop
        goto irq

wait_clk_low macro
        btfsc   PORTB, 4
        goto    $-1
        endm

wait_clk_low_safe macro
        clrwdt
        btfsc   PORTB, 4
        goto    $-2
        endm

wait_clk_high macro
        btfss   PORTB, 4
        goto    $-1
        endm

wait_data_low macro
        btfsc   PORTA, 4
        goto    $-1
        endm

wait_data_high macro
        btfss   PORTA, 4
        goto    $-1
        endm

wait_data_high_safe macro
        clrwdt
        btfss   PORTA, 4
        goto    $-2
        endm

wait_clk_high_safe macro
        clrwdt
        btfss   PORTB, 4
        goto    $-2
        endm

main:
        clrf    PORTA
        clrf    PORTB
        clrf    SRQ_COUNT
        bsf     PORTA, 4

        bsf     STATUS, RP0
        bcf     OPTION_REG^0x80, T0CS
        bcf     TRISB^0x80, 0
        bsf     TRISB^0x80, 1
        bsf     TRISB^0x80, 2
        bsf     TRISB^0x80, 4
        bsf     TRISB^0x80, 5
        movlw   0x10
        movwf   TRISA^0x80
        bcf     STATUS, RP0

        bsf     INTCON, GIE
        bsf     INTCON, PEIE

        wait_clk_high_safe
        wait_data_high_safe

decode_burst:
        clrf    0x20
        clrf    0x21
        movlw   XFER_TMP_BUF
        movwf   FSR
        clrwdt

        ; Bit 0 (MSB)
        wait_clk_low_safe
        bcf     INTCON, GIE
        bsf     PORTB, 0
        wait_clk_high
        movfw   PORTA
        clrwdt
        movwf   INDF
        incf    FSR, F

        ; Bit 1
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 2
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 3
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 4
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 5
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 6
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; Bit 7 (LSB)
        wait_clk_low
        clrwdt
        wait_clk_high
        movfw   PORTA
        movwf   INDF
        incf    FSR, F

        ; wait for HU to release data line
        wait_data_high
        clrwdt

        ; end timing-critical
        bsf     INTCON, GIE

        ; compress 8 bytes to one
        movlw   XFER_TMP_BUF
        movwf   FSR
        clrf    0x20
        bcf     STATUS, C

decode_loop:
        rlf     0x20, F
        btfsc   INDF, 4
        bsf     0x20, 0
        incf    FSR, F
        clrwdt
        btfss   FSR, 3
        goto    decode_loop

        bcf     PORTB, 0
        ; sets up CMD_BUF_LEN and buffer contents
        movfw   0x20
        call    command_logic

        movlw   RESP_BUF
        movwf   FSR

send_next_byte:
        movfw   INDF
        call    send_byte
        incf    FSR, F
        decf    RESP_BUF_LEN, F
        clrwdt
        skpz
        goto    send_next_byte

        call    ack_byte
        goto    decode_burst
        ; end main

        ; must preserve FSR
send_byte:
        movwf   0x20
        movfw   FSR
        movwf   0x21
        ; blow out one byte to 8
        movlw   XFER_TMP_BUF
        movwf   FSR

encode_loop:
        movlw   0
        rlf     0x20, F
        btfsc   STATUS, C
        iorlw    0x10
        movwf   INDF
        incf    FSR, F
        clrwdt
        btfss   FSR, 3
        goto    encode_loop

        call    ack_byte

        ; switch data line to output
        bsf     PORTA, 4
        bsf     STATUS, RP0
        bcf     TRISA^0x80, 4
        bcf     STATUS, RP0
        movlw   XFER_TMP_BUF
        movwf   FSR
        movfw   INDF

        ; Bit 0 (MSB)
        clrwdt
        wait_clk_low
        movwf   PORTA
        bcf     INTCON, GIE
        wait_clk_high
        clrwdt
        incf    FSR, F
        movfw   INDF

        ; Bit 1
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 2
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 3
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 4
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 5
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 6
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; Bit 7 (LSB)
        wait_clk_low
        movwf   PORTA
        clrwdt
        wait_clk_high
        incf    FSR, F
        movfw   INDF

        ; release data line
        wait_clk_low
        clrwdt
        bsf     PORTA, 4
        bsf     STATUS, RP0
        bsf     TRISA^0x80, 4
        bcf     STATUS, RP0

        ; end time critical
        bsf     INTCON, GIE

        ; restore FSR
        movfw   0x21
        movwf   FSR
        return
        ; end send_byte

delay macro
        clrf    TMR0
        bcf     INTCON, T0IF
        clrwdt 
        btfss   INTCON, T0IF
        goto    $-2
        endm
        
ack_byte:
        ; switch data line to output
        bsf     PORTA, 4
        bsf     STATUS, RP0
        bcf     TRISA^0x80, 4
        bcf     STATUS, RP0

        delay
        delay
        delay
        delay
        delay
        delay
        delay
        delay
        delay
        delay

        wait_clk_high
        clrwdt
        wait_clk_low
        bcf     PORTA, 4
        clrwdt

        wait_clk_high
        wait_clk_low
        clrwdt

        wait_clk_high
        wait_clk_low
        clrwdt

        wait_clk_high
        wait_clk_low
        clrwdt

        wait_clk_high
        wait_clk_low
        clrwdt

        wait_clk_high
        wait_clk_low
        clrwdt
        bsf     PORTA, 4
        bsf     STATUS, RP0
        bsf     TRISA^0x80, 4
        bcf     STATUS, RP0
        wait_clk_high
        clrwdt
        return

command_logic:
        clrf    RESP_BUF_LEN
        movwf   COMMAND
        movwf   RESP_BUF
        movlw   RESP_BUF
        movwf   FSR
        incf    FSR, F
        incf    RESP_BUF_LEN, F

        clrwdt
        movlw   0x09
        subwf   COMMAND, W
        skpnz
        goto    cmd_09

        clrwdt
        movlw   0x4c
        subwf   COMMAND, W
        skpnz
        goto    cmd_4c

        clrwdt
        movlw   0x45
        subwf   COMMAND, W
        skpnz
        goto    cmd_45

        clrwdt
        movlw   0x4b
        subwf   COMMAND, W
        skpnz
        goto    cmd_4b

        clrwdt
        movlw   0x41
        subwf   COMMAND, W
        skpnz
        goto    cmd_41

        clrwdt
        movlw   0x50
        subwf   COMMAND, W
        skpnz
        goto    cmd_50

        clrwdt
        movlw   0x51
        subwf   COMMAND, W
        skpnz
        goto    cmd_51

        clrwdt
        movlw   0xe2
        subwf   COMMAND, W
        skpnz
        goto    cmd_e2

        clrwdt
        movlw   0x61
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x70
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x81
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x5c
        subwf   COMMAND, W
        skpnz
        goto    cmd_5c

        clrwdt
        movlw   0xe1
        subwf   COMMAND, W
        skpnz
        goto    cmd_e1

        clrwdt
        movlw   0x00
        subwf   COMMAND, W
        skpnz
        goto    cmd_00

        clrwdt
        movlw   0xf7
        subwf   COMMAND, W
        skpnz
        goto    cmd_f7

        clrwdt
        movlw   0x11
        subwf   COMMAND, W
        skpnz
        goto    cmd_11

        clrwdt
        movlw   0x62
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x70
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x81
        subwf   COMMAND, W
        skpnz
        goto    empty_cmd

        clrwdt
        movlw   0x01
        subwf   COMMAND, W
        skpnz
        goto    cmd_01
        return

cmd_09:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x1a
        call    enqueue_byte
        return
        ; end command_logic

cmd_4c:
        movlw   0x02
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        return

cmd_45:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x1a
        call    enqueue_byte
        return

cmd_4b:
        movlw   0x02
        call    enqueue_byte
        movlw   0x12
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        return

cmd_41:
        movlw   0x04
        call    enqueue_byte
        movlw   0x1a
        call    enqueue_byte
        movlw   0x55
        call    enqueue_byte
        movlw   0x50
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        return

cmd_50:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x1a
        call    enqueue_byte
        return

cmd_51:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x1a
        call    enqueue_byte
        return

cmd_e2:
        movlw   0x03
        call    enqueue_byte
        movlw   0x42
        call    enqueue_byte
        movlw   0xff
        call    enqueue_byte
        movlw   0xff
        call    enqueue_byte
        return

empty_cmd:
        movlw   0x00
        call    enqueue_byte
        return

cmd_5c:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x06
        call    enqueue_byte
        return

cmd_e1:
        movlw   0x03
        call    enqueue_byte
        movlw   0x41
        call    enqueue_byte
        movlw   0xff
        call    enqueue_byte
        movlw   0xff
        call    enqueue_byte

        call    enable_timer
        return

        ; cmd 0x00 is sent during interrupt servicing.  rather than being
        ; echo'ed, we reply with 0xf7
cmd_00:
        movlw   0xf7
        movwf   RESP_BUF
        return

        ; cmd 0xf7 causes the interrupt line to be released
cmd_f7:
        bsf     STATUS, RP0
        bsf     TRISB, 5
        bcf     STATUS, RP0
        return

cmd_11:
        incf    SRQ_COUNT, F
        movlw   8
        subwf   SRQ_COUNT, W
        skpz
        call    enable_timer

        clrwdt
        movlw   1
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_1

        clrwdt
        movlw   2
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_2

        clrwdt
        movlw   3
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_3

        clrwdt
        movlw   4
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_2

        clrwdt
        movlw   5
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_3

        clrwdt
        movlw   6
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_4

        clrwdt
        movlw   7
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_5

        clrwdt
        movlw   8
        subwf   SRQ_COUNT, W
        skpnz
        goto    cmd_11_6

        return

cmd_11_1:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x04
        call    enqueue_byte
        return

cmd_11_2:
        movlw   0x03
        call    enqueue_byte
        movlw   0x41
        call    enqueue_byte
        movlw   0x12
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        return

cmd_11_3:
        movlw   0x03
        call    enqueue_byte
        movlw   0x31
        call    enqueue_byte
        movlw   0x43
        call    enqueue_byte
        movlw   0x31
        call    enqueue_byte
        return

cmd_11_4:
        movlw   0x02
        call    enqueue_byte
        movlw   0x31
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        return

cmd_11_5:
        movlw   0x03
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        movlw   0x01
        call    enqueue_byte
        return

cmd_11_6:
        movlw   0x03
        call    enqueue_byte
        movlw   0x10
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        movlw   0x00
        call    enqueue_byte
        return

cmd_01:
        movlw   0x00
        call    enqueue_byte
        ; reset SRQ count for next run
        clrf    SRQ_COUNT
        return

enqueue_byte:
        movwf   INDF
        incf    FSR, F
        incf    RESP_BUF_LEN, F
        xorlw   0xff
        movwf   INDF
        incf    FSR, F
        incf    RESP_BUF_LEN, F
        return
        ; end enqueue_byte

enable_timer:
        bcf     T1CON, TMR1ON
        clrf    TMR1L
        clrf    TMR1H
        bcf     PIR1, TMR1IF
        bsf     STATUS, RP0
        bsf     PIE1^0x80, TMR1IE
        bcf     STATUS, RP0
        bsf     T1CON, TMR1ON
        return
        ; end enable_timer

irq:
        movwf   IRQ_W
        swapf   STATUS, W
        movwf   IRQ_STATUS

        btfsc   PIR1, TMR1IF
        call    timer_expired

        swapf   IRQ_STATUS, W
        movwf   STATUS
        swapf   IRQ_W, F
        swapf   IRQ_W, W
        retfie
        ; end of irq

timer_expired:
        bsf     STATUS, RP0
        movfw   PIE1^0x80
        bcf     STATUS, RP0
        movwf   0x20
        btfss   0x20, TMR1IE
        return

        ; clear and disable interrupt
        bsf     STATUS, RP0
        bcf     PIE1^0x80, TMR1IE
        bcf     STATUS, RP0
        bcf     PIR1, TMR1IF

        ; assert SRQ
        bcf     PORTB, 5
        bsf     STATUS, RP0
        bcf     TRISB^0x80, 5
        bcf     STATUS, RP0
        return
        ; end of timer_expired

        end
