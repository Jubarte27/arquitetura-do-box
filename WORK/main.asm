;====================================================================
; Macros
SaveRegs macro regs:VARARG
	local reg
	FOR   reg, <regs>
		push reg
	ENDM
ENDM
; RestoreRegs - Macro to generate a pop instruction for registers
; saved by the SaveRegs macro. Restores one group of registers.
RestoreRegs macro regs:VARARG
	local reg
	FOR   reg, <regs>
		pop reg
	ENDM
ENDM


printf_c macro string:req
	SaveRegs ax,   dx
	FORC     char, <string>
		mov ah, 02h     ;; Select DOS Print Char function
		mov dl, '&char' ;; Select ASCII char
		int 21h         ;; Call DOS
	ENDM
	RestoreRegs dx, ax
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

	RestoreRegs ax
ENDM

print_FilePosition macro
	print_Pair FileLine, FileCol
ENDM

print_TotalRowCol macro
	print_Pair TotalRow, TotalCol
endm

HandleCR macro
	call PeekChar
	mov  bh, PeekBuffer
	.IF  bh != LF
		jmp ErrorUnexpectedChar
	.ENDIF
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
		mov ax, Col
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

    printf_c < Erro: caracter inexperado: >
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
    RestoreRegs bx, ax
	ret
ReadEmptyLines endp

OpenFile       proc near
	SaveRegs    ax,         dx
    mov         al,         0
	lea         dx,         FileName
	mov         ah,         3dh
	int         21h
	jc          ErrorOpen
    mov         FileHandle, ax
	mov         FileIsOpen, 0        ; 0 means it is open
	RestoreRegs dx,         ax
    ret
OpenFile endp

ReadChar proc near
    SaveRegs dx
	lea      dx, FileBuffer
    call     ReadCharToDX
    
    inc         FileCol
    RestoreRegs dx
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

    RestoreRegs cx, bx
    ret
ReadCharToDX endp

PeekChar     proc near
    SaveRegs ax, bx, cx, dx

	lea  dx, PeekBuffer
	call ReadCharToDX

    ; move back by one byte
    mov bx, FileHandle
    mov ah, 42h
    mov cx, 0FFFFh ; Means dx is negative
    mov dx, -1
    mov al, 1
    int 21h
	jc ErrorRead

EndPeek:
	RestoreRegs dx, cx, bx, ax
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
	; SaveRegs ax, bx, dx
	
	mov dl, [bx]
	cmp dl, 0
	je  ps_1

	push bx
	mov  ah, 2
	int  21H
	pop  bx

	inc bx
	jmp printf_s

ps_1:
	; RestoreRegs dx, bx, ax
	ret
printf_s endp

;
;--------------------------------------------------------------------
;Função: Escreve o valor de ax na tela
;printf("%
;--------------------------------------------------------------------
printf_w proc	near
	; SaveRegs bx
	; sprintf_w(ax, BufferWRWORD)
	lea  bx, BufferWRWORD
	call sprintf_w
	
	; printf_s(BufferWRWORD)
	lea  bx, BufferWRWORD
	call printf_s
	
	; RestoreRegs bx
	ret
printf_w  endp

;
;--------------------------------------------------------------------
;Função: Converte um inteiro (n) para (string)
; sprintf(string->bx, "%d", n->ax)
;--------------------------------------------------------------------
sprintf_w proc	near
	; SaveRegs ax,bx,cx,dx
	mov sw_n, ax
	mov cx,   5
	mov sw_m, 10000
	mov sw_f, 0
	
sw_do:
	mov dx, 0
	mov ax, sw_n
	div sw_m
	
	cmp al,   0
	jne sw_store
	cmp sw_f, 0
	je  sw_continue
sw_store:
	add al,   '0'
	mov [bx], al
	inc bx
	
	mov sw_f, 1
sw_continue:
	
	mov sw_n, dx
	
	mov dx,   0
	mov ax,   sw_m
	mov bp,   10
	div bp
	mov sw_m, ax
	
	dec cx
	cmp cx, 0
	jnz sw_do

	cmp sw_f, 0
	jnz sw_continua2
	mov [bx], '0'
	inc bx
sw_continua2:

	mov byte ptr[bx], 0
	; RestoreRegs dx,cx,bx,ax
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
; Variaveis para uso interno na função sprintf_w
sw_n              dw  0
sw_f              db  0
sw_m              dw  0
; used in main
FileCol           dw  1
FileLine          dw  1

Row               dw  0
Col               dw  0
TotalRow          dw  0
TotalCol          dw  0

Matrix            dw  0

;--------------------------------------------------------------------
end
;--------------------------------------------------------------------

