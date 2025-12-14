.model small, stdcall
;===========================================================
; Prototypes
	printf_s proto near, string:ptr byte
	printf_u proto near, number:word
	printf_d proto near, number:sword
	string_from_word proto near, string:ptr byte, number:word
	string_from_sword proto near, string:ptr byte, number:sword

	ReadNum proto near, result:ptr word
;===========================================================
; Memory
		.stack

		.data

	CR            equ 0dh
	LF            equ 0ah
	QUOT          equ 22h
	SEMI          equ 3Bh
	COL_SEPARATOR equ SEMI

	BuffSize       equ 100              ; tam. máximo dos dados lidos no buffer
	FileName       db  "MAT.TXT",0      ; Nome do arquivo a ser lido
	FileBuffer     db  BuffSize dup (?) ; Buffer de leitura do arquivo
	FileHandle     dw  0                ; Handler do arquivo
	FileIsOpen     db  1                ; closed at the start
	FileNameBuffer db  150 dup (?)
	caractere      db  0

	MsgCRLF           db CR, LF, 0
	; Used on PeekChar
	PeekBuffer        db ?
	; Used when reporting the error
	TheUnexpectedChar db 0,QUOT,0
	; used in main
	FileCol           dw 1
	FileLine          dw 1

	Row      byte 0
	Col      byte 0
	TotalRow byte 0
	TotalCol byte 0

	N      byte 0
	; should be at most 7x7
	Matrix sword (7 * 7) dup (?)

;====================================================================
; Macros
; -----------------------------------------
; Save and restore registers
	OPEN_DELIMITER    textequ <!<>
	CLOSE_DELIMITER   textequ <!>>
	REG_SET_DELIMITER textequ <|>

	regStack textequ <> ; starts empty

	__popRegs macro
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
		invoke   printf_u, line
		printf_c <:>
		invoke   printf_u, col
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

	CurrentIndexToBx macro
		SaveRegs ax
		mov al, TotalRow

		mov bl, Row
		mov bh, Col
		sub bl, 1 ; starting at 0 makes it easier
		sub bh, 1

		mul bl
		add al, bh

		; got index, find position in array

		shl ax, 1
		add ax, offset Matrix

		mov bx, ax

		RestoreRegs
	endm

;====================================================================
; Program
	.code
	.startup
Main:
	call OpenFile
	
MainLoop:
    call ReadChar
    .IF  ax == 0  ; EOF
		mov al, TotalCol
		dec al               ; ax = N
		.IF (TotalRow != al)
			jmp ErrorRowCount
		.ELSEIF (al < 2 ) || (al > 7)
			jmp ErrorInvalidN
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
		mov al,      Col
		.IF Row == 0
			mov TotalCol, al
		.ELSEIF TotalCol != al
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
	.ELSEIF (bl == '-')
		CurrentIndexToBx
		invoke ReadNum, bx
		neg sword ptr [bx]
		invoke printf_d, [bx]
		printf_c < >
	.ELSEIF  (bl <= '9') && (bl >= '0')
		MoveBack
		CurrentIndexToBx
		invoke ReadNum, bx
		invoke printf_d, [bx]
		printf_c < >
	.ELSE
        jmp ErrorUnexpectedChar
    .ENDIF
NextLoop:
	jmp MainLoop

ReadNum proc near uses ax bx cx dx bp, result:ptr word
	call ReadChar
	mov ax, 0
	mov bx, 0
	mov cx, 10
	mov bl, FileBuffer
	.while ((bl <= '9') && (bl >= '0'))
		mul cx

		sub bl, '0'
		add ax, bx

		push ax
		call ReadChar
		pop ax
		mov bl, FileBuffer
	.endw
	MoveBack

	mov bx, result
	mov word ptr[bx], ax
	ret
ReadNum endp
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
		mov bl,                  [FileBuffer]
		mov [TheUnexpectedChar], bl

		print_FilePosition

		printf_c < Erro: caracter inexperado: ">
		invoke   printf_s, addr TheUnexpectedChar

		jmp ExitFailure

	ErrorInvalidN:
		print_FilePosition
		printf_c < Erro: N deve estar entre 2 e 7. N encontrado: >
		invoke   printf_u, N
		jmp      ExitFailure


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

	OpenFile proc near
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
	ReadChar endp

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

	PeekChar proc near
		SaveRegs dx

		lea  dx, PeekBuffer
		call ReadCharToDX
		MoveBack

		RestoreRegs
		ret
	PeekChar endp

;====================================================================
; printf
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

	printf_u PROC near uses ax bx cx dx bp, number:word
		local  buf[6]:byte
		invoke string_from_word, addr buf, number
		invoke printf_s, addr buf
		ret
	printf_u ENDP

	printf_d PROC near uses ax bx cx dx bp, number:sword
		local  buf[7]:byte
		invoke string_from_sword, addr buf, number
		invoke printf_s, addr buf
		ret
	printf_d ENDP

	string_from_sword proc near uses ax bx cx dx bp, string:ptr byte, number:sword
		mov dx, number
		mov bx, string
		.if (sword ptr dx < 0)
			mov byte ptr[bx], '-'
			inc bx
			neg dx
		.endif
		invoke string_from_word, bx, dx
		ret
	string_from_sword endp

	string_from_word proc near uses ax bx cx dx si bp, string:ptr byte, number:word
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
				add al,            '0'
				mov byte ptr [bx], al
				inc bx
				mov first,         0
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
	string_from_word ENDP

;--------------------------------------------------------------------
end
;--------------------------------------------------------------------

