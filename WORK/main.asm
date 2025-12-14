.model small, stdcall
;===================================================================
; Prototypes
	printf_s proto near, string:ptr byte
	printf_u proto near, number:word
	printf_d proto near, number:sword
	printf_d_padded proto near, number:sword, padTo:sword

	string_from_word proto near, string:ptr byte, number:word
	string_from_sword proto near, string:ptr byte, number:sword

	OpenFile       proto near
	MoveBack       proto near
	ReadCharTo     proto near, Buffer:ptr byte
	ReadChar       proto near
	PeekChar       proto near
	ReadNum        proto near, result:ptr word
	ReadEmptyLines proto near
	ReadMatrix     proto near


	ParseCommand proto near
	ReadCommand  proto near

	PrintMatrix proto near

;====================================================================
; Memory
		.stack
		.data

	CR            equ 0dh
	LF            equ 0ah
	QUOT          equ 22h
	SEMI          equ 3Bh
	COL_SEPARATOR equ SEMI
	SPACE         equ 20h

	BuffSize       equ 100              ; tam. máximo dos dados lidos no buffer
	FileName       db  "MAT.txt",0      ; Nome do arquivo a ser lido
	FileBuffer     db  BuffSize dup (?) ; Buffer de leitura do arquivo
	FileHandle     dw  0                ; Handler do arquivo
	FileIsOpen     db  0                ; closed at the start
	FileNameBuffer db  150 dup (?)
	caractere      db  0

	CommandBuffer       db 254
	CommandBufferLength db 0          ; max length, actual length
	CommandBufferString db 254 dup(0)

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

	N        byte 0
	NPlusOne byte 0
	; should be at most 7x7
	Matrix   sword (7 * 7) dup (?)

;====================================================================
; Macros
;--------------------------------------------------------------------
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
		size_s sizestr regStack
		if     size_s eq 0
			regStack catstr regs
		else
			regStack catstr regs, REG_SET_DELIMITER, regStack
		endif
	endm

	SaveRegs macro regs:vararg
		local reg, comma, regpushed
		comma     textequ <>
		regpushed textequ <>
		for       reg, <regs>
			push  reg
			regpushed catstr <reg>, comma, regpushed
			comma catstr <, >
		endm
		regpushed catstr OPEN_DELIMITER, regpushed, CLOSE_DELIMITER
		__pushRegs regpushed
	endm

	RestoreRegs macro
		local reg
	%	for reg, __popRegs(regStack) ;; Pop each register
			pop reg
		endm
	endm

	RegsInvokeUses textequ <ax bx cx dx bp>

	RegsReturningOnAX textequ <bx cx dx bp>
	RegsReturningOnBX textequ <ax cx dx bp>
;--------------------------------------------------------------------
; Prints
	putc macro c:req
		SaveRegs ax, dx
		mov      ah, 02h
		mov      dl, c
		int      21h
		RestoreRegs
	endm

	printf_c macro string:req
		SaveRegs ax,   dx
		forc     char, <string>
			mov ah, 02h
			mov dl, '&char'
			int 21h
		endm
		RestoreRegs
	endm

	print_Pair macro line:req, col:req
		printf_c <(>
		invoke   printf_u, line
		printf_c <:>
		invoke   printf_u, col
		printf_c <)>
	endm

	print_FilePosition macro
		print_Pair FileLine, FileCol
	endm

	print_TotalRowCol macro
		print_Pair TotalRow, TotalCol
	endm

;--------------------------------------------------------------------
; Miscellaneous

	CloseFileHandle macro
		mov ah, 3eh
		mov bx, FileHandle
		int 21h
		
		mov FileIsOpen, 0 ; 0 means it is now closed
	endm

	CurrentIndexToBx macro
		; returns in bx
		SaveRegs ax
		mov      al, TotalCol
		inc      al           ; TotalCol starts at 0

		mov bl, Row
		mov bh, Col

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
	invoke ReadMatrix
	invoke PrintMatrix
	@whiletrue:
		invoke ReadCommand
	jmp @whiletrue
	jmp ExitSuccess
;====================================================================
; Exiting
	ExitSuccess:
		mov al, 0
		jmp ExitAndClose

	ExitFailure:
		mov al, 1
		jmp ExitAndClose

	ExitAndClose:
		.if (FileIsOpen)
			CloseFileHandle
		.endif
		.exit

;====================================================================
; Reading input

	ReadCommand proc near uses RegsInvokeUses si
		mov dx, offset CommandBuffer
		mov ah, 0Ah
		int 21h

		mov si, offset CommandBufferString
		mov bh, 0
		mov bl, CommandBufferLength
		
		mov byte ptr [CommandBufferString+bx], 0

		invoke ParseCommand

		jc ErrorInvalidCommand

		printf_c <aceitamos a batata>
		putc LF

		ret
	ReadCommand endp

	; constStr must be uppercase, doesn't work with symbols
	StartsWith macro constStr, memString
		LOCAL i, @@eq, @@ne, @@done
		SaveRegs ax, bx

		i = 0
		
		mov bx, memString
		
		forc char, <constStr>
			mov al, [bx+i]
			and al, 11011111b ; toUpperCase
			cmp al, '&char'
			jne @@ne

			i = i + 1
		endm 
		mov ax, 1

		jmp @@done
		@@ne:
			mov ax, 0

		@@done:
			cmp ax, 0
			RestoreRegs
	endm


	CMD_NONE  EQU 0
	CMD_MUL   EQU 1
	CMD_ADD   EQU 2
	CMD_UNDO  EQU 3
	CMD_WRITE EQU 4
	; OUT:
	;   AX = command ID (CMD_*)
	;   BX = param1 (if any)
	;   CX = param2 (if any)
	;   DX = offset of string (WRITE)
	; CF = 1 on error

	SkipSpacesInSI macro string:req
		.while BYTE PTR [string] == ' '
			inc si
		.endw
	endm

	; Return the value read in result, and the end of the string read in si
	ReadNumFromString proc near uses RegsInvokeUses, string:ptr byte, result:ptr sword
		mov ax, 0
		mov bx, 0
		mov si, string
		mov cx, 0
		mov dx, 10

		.if byte ptr [si] == '-'
			inc si
			mov cx, 1
		.endif

		.while (byte ptr [si] >= '0') && (byte ptr [si] <= '9')
			mul cx

			mov bl, [si]
			sub bl, '0'
			add ax, bx

			inc si
		.endw

		.if (cx)
			neg ax
		.endif

		mov bx,           result
		mov word ptr[bx], ax
		ret
	ReadNumFromString endp

	skipAndRead macro string:req, numberInMemory:req, resultReg:req
		SkipSpacesInSI string

		.if (byte ptr [string] > '9' || byte ptr [string] < '0' )
			jmp ErrorCommandExpectsNumber
		.endif
		
		invoke ReadNumFromString, string, addr numberInMemory
		
		mov resultReg, numberInMemory
	endm

	; string in memory mus be in si
	jumpIfSIComparesTo macro constStr:req, jumpTarget:req
		StartsWith <constStr> si
		
		.if (!zero?)
			add si, @SizeStr(constStr)
			jmp jumpTarget
		.endif
	endm

	ParseCommand proc near uses si di bp
		local a:sword

		mov si, offset CommandBufferString
		
		SkipSpacesInSI si

		jumpIfSIComparesTo <MUL> ParseCommand@MUL
		jumpIfSIComparesTo <ADD> ParseCommand@ADD
		jumpIfSIComparesTo <UNDO> ParseCommand@UNDO
		jumpIfSIComparesTo <WRITE> ParseCommand@WRITE
		
	ParseCommand@error:
		stc
		ret
	ParseCommand@MUL:

		skipAndRead si, a, bx
		skipAndRead si, a, cx
		mov ax, CMD_MUL

		jmp ParseCommand@success

	ParseCommand@ADD:

		skipAndRead si, a, bx
		skipAndRead si, a, cx
		mov ax, CMD_ADD
		
		jmp ParseCommand@success

	ParseCommand@UNDO:
		mov ax, CMD_UNDO
		jmp ParseCommand@success

	ParseCommand@WRITE:
		SkipSpacesInSI si
		
		mov dx, si        ; filename pointer
		mov ax, CMD_WRITE

	ParseCommand@success:
		clc
		ret
	ParseCommand endp


;====================================================================
; Reading error reporting
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

	ErrorInvalidCommand:
		printf_c <Unable to parse command: >
		invoke   printf_s, addr CommandBufferString
		jmp      ExitFailure

	ErrorCommandExpectsNumber:
		printf_c <Command expects arguments: >
		invoke   printf_s, addr CommandBufferString
		jmp      ExitFailure


;====================================================================
; Reading Functions

	HandleCR macro
		invoke PeekChar
		mov    bh, PeekBuffer
		.if    bh != LF
			jmp ErrorUnexpectedChar
		.endif
	endm
	
	ReadEmptyLines proc near uses RegsInvokeUses
		invoke ReadChar
		.while ax != 0
			mov bl, FileBuffer

			.if bl == LF
				inc FileLine
				mov FileCol, 1
			.elseif bl == CR
				HandleCR
			.else
				jmp ErrorUnexpectedChar
			.endif

			invoke ReadChar
		.endw
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
		mov      FileIsOpen, 1
		RestoreRegs
		ret
	OpenFile endp

	ReadChar proc near uses RegsReturningOnAX
		invoke ReadCharTo, addr FileBuffer
		inc    FileCol
		ret
	ReadChar endp

	ReadCharTo proc near uses RegsReturningOnAX, Buffer:ptr byte
		mov dx, Buffer
		mov bx, FileHandle
		mov ah, 3Fh
		mov cx, 1
		int 21h
		jc  ErrorRead

		; EOF
		.if ax == 0
			mov bx,           dx
			mov byte ptr[bx], 0
		.endif

		ret
	ReadCharTo endp

	MoveBack proc near uses RegsInvokeUses
		; Move back by one byte
		mov bx, FileHandle

		mov ah, 42h
		mov cx, 0FFFFh ; Means dx is negative
		mov dx, -1
		mov al, 1
		int 21h
		jc  ErrorRead
		ret
	MoveBack endp

	PeekChar proc near uses RegsReturningOnAX
		invoke ReadCharTo, addr PeekBuffer
		invoke MoveBack
		ret
	PeekChar endp

	ReadNum proc near uses RegsInvokeUses, result:ptr word
		invoke ReadChar
		mov    ax, 0
		mov    bx, 0
		mov    cx, 10
		mov    bl, FileBuffer
		.while ((bl <= '9') && (bl >= '0'))
			mul cx

			sub bl, '0'
			add ax, bx

			push   ax
			invoke ReadChar
			pop    ax
			mov    bl, FileBuffer
		.endw
		invoke MoveBack

		mov bx,           result
		mov word ptr[bx], ax
		ret
	ReadNum endp

	ReadMatrix proc near uses ax bx cx dx bp
		invoke OpenFile
		ReadMatrixLoop:
			invoke ReadChar
			.if    ax == 0  ; EOF
				mov al,       TotalCol
				mov NPlusOne, al
				dec al                 ; ax = N
				mov N,        al
				.if (TotalRow != al)
					jmp ErrorRowCount
				.elseif (al < 2 ) || (al > 7)
					jmp ErrorInvalidN
				.endif
				jmp EndReading
			.endif

			mov bl, FileBuffer

			.if bl == COL_SEPARATOR
				inc Col
			.elseif bl == LF
				inc FileLine
				mov FileCol, 1
				;====================================================================
				; On a new line, the number of columns should always be the same
				mov al,      Col
				.if Row == 0
					mov TotalCol, al
				.elseif TotalCol != al
					jmp ErrorColumnCount
				.endif
				;====================================================================
				; If next line is empty, all next lines should be empty
				invoke PeekChar
				mov    bh, PeekBuffer
				.if    bh == LF || bh == CR
					invoke ReadEmptyLines
				;====================================================================
				; Otherwise, next line must have data
				.else
					inc Row
					inc TotalRow
					mov Col, 0
				.endif
			.elseif bl == CR
			; accept CR only before LF
				HandleCR
			.elseif (bl == '-')
				CurrentIndexToBx
				invoke ReadNum, bx
				neg    sword ptr [bx]
			.elseif (bl <= '9') && (bl >= '0')
				invoke MoveBack
				CurrentIndexToBx
				invoke ReadNum, bx
			.else
				jmp ErrorUnexpectedChar
			.endif
			jmp ReadMatrixLoop
		EndReading:
			CloseFileHandle
		ret
	ReadMatrix endp

;====================================================================
; Printf

	PrintMatrix proc near uses RegsInvokeUses
		mov      bx, offset Matrix
		mov      dx, 8
		mov      cx, 0             ; High has row, Low has column
		.ForRow:                   ; for (row = 0; row <= N; row++)
			cmp ch, N      ; row <= N
			jg  .EndForRow

			mov      cl, 0 ; col = 0
			.ForCol:       ; for (col = 0; col <= NPlusOne; col++)
				cmp cl, NPlusOne ; col <= NPlusOne
				jg  .EndForCol

				mov ax, sword ptr [bx]
				invoke printf_d_padded, ax, dx

				add bx, 2 ; size in bytes of a sword

				inc cl      ; col ++
				jmp .ForCol
			.EndForCol:
			putc LF

			inc ch      ; row++
			jmp .ForRow
		.EndForRow:
		ret
	PrintMatrix endp

	printf_s proc near uses RegsInvokeUses, string:ptr byte
		mov    bx, string
		.while byte ptr [bx] != 0
			mov ah, 2
			mov dl, [bx]
			int 21H
			inc bx
		.endw
		ret
	printf_s endp

	printf_u proc near uses RegsInvokeUses, number:word
		local  buf[6]:byte
		invoke string_from_word, addr buf, number
		invoke printf_s, addr buf
		ret
	printf_u endp

	printf_d proc near uses RegsInvokeUses, number:sword
		local  buf[7]:byte
		invoke string_from_sword, addr buf, number
		invoke printf_s, addr buf
		ret
	printf_d endp
	
	printf_d_padded proc near uses RegsInvokeUses, number:sword, padTo:sword
		local  buf[7]:byte
		invoke string_from_sword, addr buf, number
		; string_from_sword gives length on AX
		mov    cx, padTo
		sub    cx, ax
		.WHILE (sword ptr cx > 0)
			putc SPACE
			dec  cx
		.ENDW
		invoke printf_s, addr buf
		ret
	printf_d_padded endp

	; length of string goes to ax (including sign)
	string_from_sword proc near uses RegsReturningOnAX, string:ptr byte, number:sword
		mov dx, number
		mov bx, string
		mov cx, 0
		.if (sword ptr dx < 0)
			mov byte ptr[bx], '-'
			inc bx
			inc cx
			neg dx
		.endif
		invoke string_from_word, bx, dx
		add ax, cx
		ret
	string_from_sword endp

	; length of string goes to ax
	string_from_word proc near uses RegsReturningOnAX si, string:ptr byte, number:word
		local value:word, divisor:word, first:byte

		mov divisor, 10000
		mov first,   1     ; anything not 0 is true

		mov ax,    number
		mov value, ax

		mov bx, string
		mov cx, 5
		.repeat
			mov dx,    0
			mov ax,    value
			div divisor
			mov value, dx

			.if (ax != 0) || (!first) ; no zeroes on the left
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

		.if (first)
			mov byte ptr [bx], '0'
			inc bx
		.endif

		mov cx, string
		mov ax, bx
		sub ax, cx     ; ax = bx - string = len

		mov byte ptr [bx], 0
		ret
	string_from_word endp

;--------------------------------------------------------------------
end
