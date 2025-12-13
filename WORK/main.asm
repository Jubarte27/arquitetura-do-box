.model small, stdcall

;===========================================================
;===========================================================
	.stack
CR            equ 0dh
LF            equ 0ah
QUOT          equ 22h
SEMI          equ 3Bh
COL_SEPARATOR equ SEMI

	.data

BuffSize          equ 100              ; tam. máximo dos dados lidos no buffer
FileName          db  "MAT.TXT",0      ; Nome do arquivo a ser lido
FileBuffer        db  BuffSize dup (?) ; Buffer de leitura do arquivo
FileHandle        dw  0                ; Handler do arquivo
FileIsOpen        db  1                ; closed at the start
FileNameBuffer    db  150 dup (?)
caractere         db  0

MsgCRLF           db  CR, LF, 0

; Used on PeekChar
PeekBuffer        db  ?
; Used when reporting the error
TheUnexpectedChar db  0,QUOT,0
; Variaveis para uso interno na função sprintf_w
; used in main
FileCol           dw  1
FileLine          dw  1

Row               dw  0
Col               dw  0
TotalRow          dw  0
TotalCol          dw  0

numberBeingRead   dw  ?

N                 dw  0
Matrix            dw  0

;====================================================================
; Macros
;--------------------------------------------------------------------
; Save and restore registers
OPEN_DELIMITER    textequ <!<>
CLOSE_DELIMITER   textequ <!>>
REG_SET_DELIMITER textequ <|>

regStack          textequ <>   ; starts empty

__popRegs         macro
	local regs_end, regs
	regs_end instr 1, regStack, REG_SET_DELIMITER
	if    regs_end eq 0
		regs     substr regStack, 1
		regStack textequ <>
	else
		regs substr regStack, 1, (regs_end - 1)
		regStack substr regStack, (regs_end + 1)
	endif
	exitm regs
endm

__pushRegs macro regs:req
	size_s SIZESTR regStack
	if     size_s eq 0
		regStack CATSTR regs
	else
		regStack CATSTR regs, REG_SET_DELIMITER, regStack
	endif
endm

SaveRegs macro regs:VARARG
	LOCAL reg, comma, regpushed
	comma     TEXTEQU <>
	regpushed TEXTEQU <>
	FOR       reg, <regs>
		push  reg
		regpushed CATSTR <reg>, comma, regpushed
		comma CATSTR <, >
	ENDM
	regpushed CATSTR OPEN_DELIMITER, regpushed, CLOSE_DELIMITER
	__pushRegs regpushed
ENDM

RestoreRegs MACRO
	LOCAL reg
%	FOR reg, __popRegs(regStack) ;; Pop each register
		pop reg
	ENDM
ENDM
;--------------------------------------------------------------------
; Prints
putc macro c:req
	SaveRegs ax, dx
	mov      ah, 02h ;; Select DOS Print Char function
	mov      dl, c   ;; Select ASCII char
	int      21h     ;; Call DOS
	RestoreRegs
endm

printf_c macro string:req
	SaveRegs ax,   dx
	FORC     char, <string>
		mov ah, 02h     ;; Select DOS Print Char function
		mov dl, '&char' ;; Select ASCII char
		int 21h         ;; Call DOS
	ENDM
	RestoreRegs
ENDM

print_Pair macro line:req, col:req
    printf_c <(>
    invoke   printf_w, line
    printf_c <:>
    invoke   printf_w, col
    printf_c <)>
ENDM

print_FilePosition macro
	print_Pair FileLine, FileCol
ENDM

print_TotalRowCol macro
	print_Pair TotalRow, TotalCol
endm

;--------------------------------------------------------------------
; Miscellaneous
HandleCR macro
	call PeekChar
	mov  bh, PeekBuffer
	.IF  bh != LF
		jmp ErrorUnexpectedChar
	.ENDIF
endm

MoveBack macro
	SaveRegs ax, bx, cx, dx
    ; Move back by one byte
    mov bx, FileHandle
    mov ah, 42h
    mov cx, 0FFFFh     ; Means dx is negative
    mov dx, -1
    mov al, 1
    int 21h
	jc  ErrorRead
	RestoreRegs
endm

;====================================================================
; Program
	.code
;--------------------------------------------------------------------
; Prototypes
;--------------------------------------------------------------------
printf_s proto near, string:ptr byte
printf_w proto near, number:word
sprintf_w proto near, string:ptr byte, number:word

	.startup
Main:
	call OpenFile
	
MainLoop:
    call ReadChar
    .IF  ax == 0  ; EOF
		mov ax, TotalCol
		dec ax             ; ax = N
		.IF TotalRow != ax
			jmp ErrorRowCount
		.ENDIF
        jmp ExitSuccess
    .ENDIF

	mov bl, FileBuffer

    .IF bl == COL_SEPARATOR
        inc Col
    .ELSEIF bl == LF
        inc FileLine
        mov FileCol, 1
		;====================================================================
		; On a new line, the number of columns should always be the same
		mov ax,      Col
		.IF Row == 0
			mov TotalCol, ax
		.ELSEIF TotalCol != ax
			jmp ErrorColumnCount
		.ENDIF
		;====================================================================
		; If next line is empty, all next lines should be empty
		call PeekChar
		mov  bh, PeekBuffer
		.IF  bh == LF || bh == CR
			call ReadEmptyLines
		;====================================================================
		; Otherwise, next line must have data
		.ELSE
			inc Row
			inc TotalRow
			mov Col, 0
		.ENDIF
    .ELSEIF bl == CR ; accept cr only before lf
        HandleCR
    .ELSEIF bl == '-'
        ;do something
	.ELSEIF bl <= '9' && bl >= '0'
		sub bl, '0'
	.ELSE
        jmp ErrorUnexpectedChar
    .ENDIF
NextLoop:
	jmp MainLoop

;====================================================================
; Exiting

ExitSuccess:
	mov al, 0
	jmp ExitAndClose

ExitFailure:
	mov al, 1
	jmp ExitAndClose

ExitAndClose:
	.IF FileIsOpen
		mov ah,         3eh
		mov bx,         FileHandle
		int 21h
		mov FileIsOpen, 1          ; file is now closed
	.ENDIF
	.exit

;====================================================================
; Error reporting

ErrorOpen:
	printf_c <Erro na abertura do arquivo.>
	jmp      ExitFailure

ErrorRead:
    printf_c <Erro na leitura do arquivo.>
	jmp      ExitFailure

ErrorColumnCount:
    print_FilePosition
    printf_c < Erro: a quantidade de colunas deve ser igual em todas as linhas.>
	jmp      ExitFailure

ErrorRowCount:
    printf_c <Erro: a quantidade de linhas deve ser 1 a menos que a quantidade de colunas. O encontrado foi: >
	print_TotalRowCol
	jmp      ExitFailure

ErrorUnexpectedChar proc near
	SaveRegs bx
	mov      bl, [FileBuffer]
    mov      [TheUnexpectedChar], bl

    print_FilePosition

    printf_c < Erro: caracter inexperado: ">
	invoke   printf_s, addr TheUnexpectedChar

	jmp ExitFailure

	ret
ErrorUnexpectedChar endp


;====================================================================
; Functions

ReadEmptyLines      proc near
	SaveRegs ax, bx
    call     ReadChar
	.WHILE   ax != 0
		mov bl, FileBuffer

		.IF bl == LF
			inc FileLine
			mov FileCol, 1
		.ELSEIF bl == CR
			HandleCR
		.ELSE
			call ErrorUnexpectedChar
		.ENDIF

		call ReadChar
	.ENDW
    RestoreRegs
	ret
ReadEmptyLines endp

OpenFile       proc near
	SaveRegs ax,         dx
    mov      al,         0
	lea      dx,         FileName
	mov      ah,         3dh
	int      21h
	jc       ErrorOpen
    mov      FileHandle, ax
	mov      FileIsOpen, 0        ; 0 means it is open, anything else it is closed
	RestoreRegs
    ret
OpenFile endp

ReadChar proc near
    SaveRegs dx
	lea      dx, FileBuffer
    call     ReadCharToDX
    
    inc FileCol
    RestoreRegs
    ret
ReadChar     endp

ReadCharToDX proc near
	SaveRegs bx, cx

	mov bx, FileHandle
	mov ah, 3fh
	mov cx, 1
	int 21h
	jc  ErrorRead

    ; EOF
    .IF ax == 0
        mov bx,           dx
        mov byte ptr[bx], 0
    .ENDIF

    RestoreRegs
    ret
ReadCharToDX endp

PeekChar     proc near
    SaveRegs dx

	lea  dx, PeekBuffer
	call ReadCharToDX
	MoveBack

	RestoreRegs
    ret
PeekChar endp

;====================================================================
printf_s proc near uses ax bx bp dx, string:ptr byte
	mov    bx, string
	.WHILE byte ptr [bx] != 0
		mov ah, 2
		mov dl, [bx]
		int 21H
		inc bx
	.ENDW
	ret
printf_s endp

printf_w PROC near, number:word
    local  buf[6]:byte
    invoke sprintf_w, addr buf, number
    invoke printf_s, addr buf
    ret
printf_w ENDP

sprintf_w proc near uses ax bx cx dx si bp, string:ptr byte, number:word
    local value:word, divisor:word, first:byte

    mov divisor, 10000
    mov first,   1     ; 0 is true

    mov ax,    number
    mov value, ax

    mov bx, string
    mov cx, 5
	.repeat
		mov dx,    0
		mov ax,    value
		div divisor
		mov value, dx

		.if (ax != 0) || (first == 0)
			add  al,            '0'
			mov  byte ptr [bx], al
			inc  bx
			mov  first,         0
		.endif

		mov dx,      0
		mov ax,      divisor
		mov si,      10
		div si
		mov divisor, ax

	.untilcxz

    .IF (first == 1)
        mov byte ptr [bx], '0'
        inc bx
    .ENDIF

    mov byte ptr [bx], 0
    ret

sprintf_w ENDP

;--------------------------------------------------------------------
end
;--------------------------------------------------------------------

