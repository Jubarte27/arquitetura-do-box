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

__pushRegs macro regs
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
	SaveRegs ax

    printf_c <(>
    mov      ax, line
    call     printf_w
    printf_c <:>
    mov      ax, col
    call     printf_w
    printf_c <)>

	RestoreRegs
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

	.model small
	.code
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

ErrorUnexpectedChar:
    mov TheUnexpectedChar, bl

    print_FilePosition

    printf_c < Erro: caracter inexperado: ">
    lea      bx, TheUnexpectedChar
	call     printf_s

	jmp ExitFailure


;====================================================================
; Functions

ReadEmptyLines proc near
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
			jmp ErrorUnexpectedChar
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
	mov      FileIsOpen, 0        ; 0 means it is open
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
; A partir daqui, estão as funções já desenvolvidas
;	1) printf_s
;	2) printf_w
;	3) sprintf_w
;====================================================================
	
;--------------------------------------------------------------------
;Função Escrever um string na tela
;printf_s(char *s -> bx)
;--------------------------------------------------------------------
printf_s proc	near
	SaveRegs ax, bx, dx

	.WHILE byte ptr [bx] != 0
		mov ah, 2
		mov dl, [bx]
		int 21H
		inc bx
	.ENDW

	RestoreRegs
	ret
printf_s endp

;
;--------------------------------------------------------------------
;Função: Escreve o valor de ax na tela
;printf("%
;--------------------------------------------------------------------
printf_w proc	near
	SaveRegs bx

	lea  bx, BufferWRWORD
	call sprintf_w
	call printf_s
	
	RestoreRegs
	ret
printf_w  endp

;
;--------------------------------------------------------------------
;Função: Converte um inteiro (n) para (string)
; sprintf(string->bx, "%d", n->ax)
;--------------------------------------------------------------------
sprintf_w proc	near
	local n:word, f:word, m:word
	SaveRegs ax,bx,cx,dx
	mov n,  ax
	mov cx, 5
	mov m,  10000
	mov f,  0
	
sw_do:
	mov dx, 0
	mov ax, n
	div m
	
	cmp al, 0
	jne sw_store
	cmp f,  0
	je  sw_continue
sw_store:
	add al,   '0'
	mov [bx], al
	inc bx
	
	mov f, 1
sw_continue:
	
	mov n, dx
	
	mov dx, 0
	mov ax, m
	mov bp, 10
	div bp
	mov m,  ax
	
	dec cx
	cmp cx, 0
	jnz sw_do

	cmp f,    0
	jnz sw_continua2
	mov [bx], '0'
	inc bx
sw_continua2:

	mov byte ptr[bx], 0
	RestoreRegs
	ret
sprintf_w endp


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
; Variável interna usada na rotina printf_w
BufferWRWORD      db  10 dup (?)
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

;--------------------------------------------------------------------
end
;--------------------------------------------------------------------

