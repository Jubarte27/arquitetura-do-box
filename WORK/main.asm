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
	
	MULMatrix proto near, LINHA:byte, CONSTANTE: sword
	DIVMatrix proto near, LINHA:byte, CONSTANTE: sword

	ADDMatrix proto near, LINHA_DST:byte, LINHA_ORG: byte
	SUBMatrix proto near, LINHA_DST:byte, LINHA_ORG: byte

	WRITEMatrix proto near, NOME:ptr byte

	PrintMatrix proto near

;====================================================================
; Memory
		.stack
		.data
	

	CMD_NONE  EQU 0
	CMD_MUL   EQU 1
	CMD_DIV   EQU 2
	CMD_ADD   EQU 3
	CMD_SUB   EQU 4
	CMD_UNDO  EQU 5
	CMD_WRITE EQU 6

	CR            equ 0dh
	LF            equ 0ah
	QUOT          equ 22h
	SEMI          equ 3Bh
	COL_SEPARATOR equ SEMI
	SPACE         equ 20h

	COLUMN_SEP db ";",0
	CRLF       db CR, LF, 0

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

	LastCommand   db 0
	LastCommand@a dw 0
	LastCommand@b sword 0
	LastCommand@exists db 0


	NonTerminalErrorBuffer db 255 dup(0)

	@Comando      db "Comando",0
	@espera       db "espera",0
	@como         db "como",0
	@parametro    db "parametro",0
	@@parametro   db "Parametro",0
	@desconhecido db "desconhecido",0
	@space        db " ",0

	@deve_estar_entre_1_e_N                           db "deve estar entre 1 e N",0
	@@nao_foi_possivel_abrir_ou_criar_o_arquivo       db "Nao foi possivel abrir ou criar o arquivo",0
	@@parametros_nao_reconhecidos_ao_final_do_comando db "Parametros nao reconhecidos ao final do comando",0
	
	COLON_SPACE db ": ",0

	ExplanationSeparator textequ <COLON_SPACE>


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
		mov      ah,   02h
		forc     char, <string>
			mov dl, '&char'
			int 21h
		endm
		RestoreRegs
	endm

	strcpy_c macro src:req, dst:req
		ifdifi <dst>, <di>
			lea di, dst
		endif

		forc char, <src>
			mov byte ptr [di], '&char'
			inc di
		endm
		mov byte ptr [di], 0
	endm

	strcpy macro src:req, dst:req
		SaveRegs ax
		ifdifi   <src>, <si>
			lea si, src
		endif
		ifdifi <dst>, <di>
			lea di, dst
		endif
		.repeat
			mov al,   [si]
			mov [di], al
			inc si
			inc di
		.until (al == 0)
		dec    si
		dec    di
		RestoreRegs
	endm

	DEFINED MACRO symbol:REQ
		IFDEF symbol
			EXITM <-1> ;; True
		ELSE
			EXITM <0> ;; False
		ENDIF
	ENDM

	strcpy_all macro dst:req, strings:vararg
		ifdifi <dst>, <di>
			lea di, dst
		endif
		for string, <strings>
			if DEFINED(string)
				strcpy string, di
			else
				strcpy_c <string>, di
			endif
		endm
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

	ErrorCommandExpectsNumber macro command:req, paramName:req, positionName:req
		strcpy_all NonTerminalErrorBuffer, \
		<@Comando, !< &command !>, @espera, !< &paramName !>, @como, !< &positionName !>, @parametro, ExplanationSeparator, CommandBufferString>
	endm

	ErrorNumberOutOfBounds macro paramName:req
		strcpy_all NonTerminalErrorBuffer, \
		<@@parametro, !< &paramName !>, @deve_estar_entre_1_e_N, ExplanationSeparator, CommandBufferString>
	endm

	ErrorCantOpenNorCreate macro
		strcpy_all                                    NonTerminalErrorBuffer, \
		<@@nao_foi_possivel_abrir_ou_criar_o_arquivo, ExplanationSeparator,   CommandBufferString>
	endm

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
	@whiletrue:
		invoke PrintMatrix
		@SkipPrint:
		invoke ReadCommand
		@Validate:
			jnc    @ValidCommand
			invoke printf_s,      addr NonTerminalErrorBuffer
			lea    bx,            NonTerminalErrorBuffer
			mov    byte ptr [bx], 0
			putc   CR
			putc   LF
			invoke ReadCommand
			jmp    @Validate
		@ValidCommand:

		.if (ax == CMD_ADD)
			call Main@ADD
		.elseif  (ax == CMD_MUL)
			call Main@MUL
		.elseif (ax == CMD_UNDO)
			call Main@UNDO
		.elseif (ax == CMD_WRITE)
			call Main@WRITE
			jmp  @SkipPrint
		.endif

		jmp ExitSuccess
		
		@MainLoopEnd:
		putc CR
		putc LF
	jmp @whiletrue

	Main@ADD proc near
		mov LastCommand,        CMD_ADD
		mov bh,                 0
		mov LastCommand@a,      bx
		mov ch,                 0
		mov LastCommand@b,      cx
		mov LastCommand@exists, 1

		invoke ADDMatrix, bl, cl

		ret
	Main@ADD endp
	Main@MUL proc near
		mov LastCommand,        CMD_MUL
		mov bh,                 0
		mov LastCommand@a,      bx
		mov LastCommand@b,      sword ptr cx
		mov LastCommand@exists, 1

		invoke MULMatrix, bl, cx
		ret
	Main@MUL endp
	Main@UNDO proc near
		mov al, LastCommand@exists
		.if !al
			jmp @MainLoopEnd
		.endif
		mov al,           LastCommand
		mov bx,           LastCommand@a
		mov sword ptr cx, LastCommand@b
		.if (al == CMD_ADD)
			invoke SUBMatrix, bl, cl
			mov LastCommand, CMD_SUB
		.elseif (al == CMD_MUL)
			invoke DIVMatrix, bl, cx
			mov LastCommand, CMD_DIV
		.elseif (al == CMD_SUB)
			invoke ADDMatrix, bl, cl
			mov LastCommand, CMD_ADD
		.elseif (al == CMD_DIV)
			invoke MULMatrix, bl, cx
			mov LastCommand, CMD_MUL
		.endif
		ret
	Main@UNDO  endp
	Main@WRITE proc near
		invoke WRITEMatrix, dx
		ret
	Main@WRITE endp


;====================================================================
; MUL
	MULMatrix proc near uses RegsInvokeUses, LINHA:byte, CONSTANTE: sword
		mov al, LINHA
		dec al
		mov bl, TotalCol
		inc bl
		mul bl

		shl ax, 1

		mov bx, offset Matrix
		add bx, ax

		mov ch, 0
		mov cl, NPlusOne

		MULMatrix@Loop:
			mov  ax,             sword ptr [bx]
			imul CONSTANTE
			mov  sword ptr [bx], ax

			add  bx, 2
			loop MULMatrix@Loop

		ret
	MULMatrix endp

	DIVMatrix proc near uses RegsInvokeUses, LINHA:byte, CONSTANTE: sword
		mov al, LINHA
		dec al
		mov bl, TotalCol
		inc bl
		mul bl

		shl ax, 1

		mov bx, offset Matrix
		add bx, ax

		mov ch, 0
		mov cl, NPlusOne
		DIVMatrix@Loop:
			mov ax, sword ptr [bx]
			cwd                    ; extend sign to dx
			
			idiv CONSTANTE
			
			mov sword ptr [bx], ax

			add  bx, 2
			loop DIVMatrix@Loop

		ret
	DIVMatrix endp

;====================================================================
; ADD
	ADDMatrix proc near uses RegsInvokeUses di si, LINHA_DST:byte, LINHA_ORG: byte

		mov al, LINHA_DST
		dec al
		mov bl, TotalCol
		inc bl
		mul bl
		shl ax, 1
		
		lea di, Matrix
		add di, ax


		mov al, LINHA_ORG
		dec al
		mov bl, TotalCol
		inc bl
		mul bl
		shl ax, 1

		lea si, Matrix
		add si, ax

		mov ch, 0
		mov cl, NPlusOne
		ADDMatrix@Loop:
			mov ax,   [di]
			add ax,   [si]
			mov [di], ax

			add  di, 2
			add  si, 2
			loop ADDMatrix@Loop

		ret
	ADDMatrix endp

	SUBMatrix proc near uses RegsInvokeUses di si, LINHA_DST:byte, LINHA_ORG: byte

		mov al, LINHA_DST
		dec al
		mov bl, TotalCol
		inc bl
		mul bl
		shl ax, 1
		
		lea di, Matrix
		add di, ax


		mov al, LINHA_ORG
		dec al
		mov bl, TotalCol
		inc bl
		mul bl
		shl ax, 1

		lea si, Matrix
		add si, ax

		mov ch, 0
		mov cl, NPlusOne
		SUBMatrix@Loop:
			mov ax,   [di]
			sub ax,   [si]
			mov [di], ax

			add  di, 2
			add  si, 2
			loop SUBMatrix@Loop

		ret
	SUBMatrix endp

;====================================================================
; WRITE

	WriteToFile macro handle:req, offset_buf:req, len:req
		SaveRegs bx, cx, dx

		mov cx, len
		mov bx, handle
		lea dx, offset_buf
		mov ah, 40h
		int 21h

		RestoreRegs
	endm
	WRITEMatrix proc near uses RegsInvokeUses di si, NOME:ptr byte
		local buf[7]:byte, handle:word
		mov   ah,          3Dh         ; open
		mov   al,          02h         ; read/write
		mov   dx,          NOME
		int   21h
		jc    create_file              ; if not exists

		mov bx, ax      ; BX = file handle
		jmp file_opened

		create_file:
		mov ah, 3Ch  ; create
		mov cx, 0
		mov dx, NOME
		int 21h
		mov bx, ax

		file_opened:
		mov ah, 42h
		mov al, 02h ; SEEK_END
		xor cx, cx
		xor dx, dx
		int 21h

		.if (carry?)
			ErrorCantOpenNorCreate
			stc
			ret
		.endif

		mov handle, bx
		mov bx,     0  ; Low tells if its not first column

		mov di, offset Matrix
		mov cx, 0             ; High has row, Low has column
		
		WRITEMatrix@ForRow: ; for (row = 0; row < N; row++)
			cmp ch, N                 ; row < N
			jge WRITEMatrix@EndForRow

			mov bl, 0 ; new first column
			mov cl, 0 ; col = 0
			
			WRITEMatrix@ForCol: ; for (col = 0; col < NPlusOne; col++)
				cmp cl, NPlusOne          ; col < NPlusOne
				jge WRITEMatrix@EndForCol

				.if (bl) ; no longer firstCol?
					WriteToFile handle, COLUMN_SEP, 1
				.endif

				mov ax, sword ptr [di]

				invoke string_from_sword, addr buf, ax ; ax now has length

				WriteToFile handle, buf, ax

				add di, 2 ; size in bytes of a sword

				mov bl, 1 ; no longer first col
				inc cl    ; col ++
				
				jmp WRITEMatrix@ForCol
			WRITEMatrix@EndForCol:

			WriteToFile handle, CRLF, 2

			inc ch ; row++
			
			jmp WRITEMatrix@ForRow
		WRITEMatrix@EndForRow:

		clc
		ret
	WRITEMatrix endp
;====================================================================
; Exiting

	ExitSuccess proc near
		mov al, 0
		jmp ExitAndClose
		ret
	ExitSuccess endp

	ExitFailure proc near
		mov al, 1
		jmp ExitAndClose
		ret
	ExitFailure endp

	ExitAndClose proc near
		.if (FileIsOpen)
			CloseFileHandle
		.endif
		.exit
		ret
	ExitAndClose endp

;====================================================================
; Reading input

	ReadCommand proc near uses si
		mov dx, offset CommandBuffer
		mov ah, 0Ah
		int 21h

		mov si, offset CommandBufferString
		mov bh, 0
		mov bl, CommandBufferLength
		
		mov byte ptr [CommandBufferString+bx], 0


		putc CR
		putc LF

		invoke ParseCommand
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

	SkipSpacesInSI macro string:req
		.while (BYTE PTR [string] == ' ' )
			inc string
		.endw
	endm

	; Return the value read in result, and the end of the string read in si
	ReadNumFromString proc near uses RegsInvokeUses, string:ptr byte, result:ptr sword
		mov ax, 0
		mov bx, 0
		mov si, string
		mov cx, 0

		.if byte ptr [si] == '-'
			inc si
			mov cx, 1
		.endif

		.while (byte ptr [si] >= '0') && (byte ptr [si] <= '9')
			mov dx, 10
			mul dx

			mov bl, [si]
			sub bl, '0'
			add ax, bx

			inc si
		.endw

		mov bx, string
		add bx, cx
		.if (si == bx)
			stc
			ret
		.endif

		.if (cx)
			neg ax
		.endif

		mov bx,           result
		mov word ptr[bx], ax
		clc
		ret
	ReadNumFromString endp

	skipAndRead macro string:req, numberInMemory:req, resultReg:req
		SkipSpacesInSI string
		invoke ReadNumFromString, string, addr numberInMemory
		.if            (carry?)
			stc
		.else
			mov resultReg, numberInMemory
			clc
		.endif
	endm

	; string in memory mus be in si
	jumpIfSIComparesTo macro constStr:req, jumpTarget:req
		StartsWith <constStr> si
		
		.if (!zero?)
			add si, @SizeStr(constStr)
			jmp jumpTarget
		.endif
	endm


	;   AX = command ID (CMD_*)
	;   BX = param1 (if any)
	;   CX = param2 (if any)
	;   DX = offset of string (WRITE)
	ParseCommand proc near uses si di bp
		local a:sword

		mov si, offset CommandBufferString
		
		SkipSpacesInSI si

		jumpIfSIComparesTo <MUL> ParseCommand@MUL
		jumpIfSIComparesTo <ADD> ParseCommand@ADD
		jumpIfSIComparesTo <UNDO> ParseCommand@UNDO
		jumpIfSIComparesTo <WRITE> ParseCommand@WRITE
		jumpIfSIComparesTo <EXIT> ParseCommand@EXIT
		jumpIfSIComparesTo <QUIT> ParseCommand@EXIT
	
		strcpy_all NonTerminalErrorBuffer, @Comando, @space, @desconhecido, ExplanationSeparator, CommandBufferString
	ParseCommand@error:
		stc
		ret
	ParseCommand@MUL:

		skipAndRead si, a, bx
		.if (carry?)
			call ParseCommand@LINHA_AUSENTE
			jmp ParseCommand@error
		.elseif (bl > N)
			call ParseCommand@LINHA_INVALIDA
			jmp ParseCommand@error
		.elseif (bl < 1)
			call ParseCommand@LINHA_INVALIDA
			jmp ParseCommand@error
		.endif
		
		skipAndRead si, a, cx
		.if (carry?)
			call ParseCommand@CONSTANTE_AUSENTE
			jmp ParseCommand@error
		.endif

		mov ax, CMD_MUL

		jmp ParseCommand@success

	ParseCommand@ADD:

		skipAndRead si, a, bx
		.if (carry?)
			call ParseCommand@LINHA_DST_AUSENTE
			jmp ParseCommand@error
		.elseif (bl > N)
			call ParseCommand@LINHA_DST_INVALIDA
			jmp ParseCommand@error
		.elseif (bl < 1)
			call ParseCommand@LINHA_DST_INVALIDA
			jmp ParseCommand@error
		.endif

		skipAndRead si, a, cx
		.if (carry?)
			call ParseCommand@LINHA_ORG_AUSENTE
			jmp ParseCommand@error
		.elseif (bl > N)
			call ParseCommand@LINHA_ORG_INVALIDA
			jmp ParseCommand@error
		.elseif (bl < 1)
			call ParseCommand@LINHA_ORG_INVALIDA
			jmp ParseCommand@error
		.endif

		mov ax, CMD_ADD
		
		jmp ParseCommand@success

	ParseCommand@UNDO:
		mov ax, CMD_UNDO
		jmp ParseCommand@success

	ParseCommand@WRITE:
		SkipSpacesInSI si
		
		mov    dx, si               ; filename pointer
		mov    ax, CMD_WRITE
		.while (BYTE PTR [si] != 0)
			inc si
		.endw
		jmp ParseCommand@success

	ParseCommand@EXIT:
		jmp ParseCommand@success

	ParseCommand@success:
		SkipSpacesInSI si
		
		.if (byte ptr [si] != 0)
		
			strcpy_all                                          NonTerminalErrorBuffer, \
			<@@parametros_nao_reconhecidos_ao_final_do_comando, ExplanationSeparator,   CommandBufferString>
			
			jmp ParseCommand@error
		.endif
		clc
		ret
	ParseCommand endp


	ParseCommand@LINHA_AUSENTE proc near
		ErrorCommandExpectsNumber <"MUL">, <LINHA>, <PRIMEIRO>
		ret
	ParseCommand@LINHA_AUSENTE endp

	ParseCommand@CONSTANTE_AUSENTE proc near
		ErrorCommandExpectsNumber <"MUL">, <CONSTANTE>, <SEGUNDO>
		ret
	ParseCommand@CONSTANTE_AUSENTE endp
	
	ParseCommand@LINHA_DST_AUSENTE proc near
		ErrorCommandExpectsNumber <"ADD">, <LINHA_DST>, <PRIMEIRO>
		ret
	ParseCommand@LINHA_DST_AUSENTE endp

	ParseCommand@LINHA_ORG_AUSENTE proc near
		ErrorCommandExpectsNumber <"ADD">, <LINHA_ORG>, <SEGUNDO>
		ret
	ParseCommand@LINHA_ORG_AUSENTE endp

	ParseCommand@LINHA_INVALIDA proc near
		ErrorNumberOutOfBounds <LINHA>
		ret
	ParseCommand@LINHA_INVALIDA endp

	ParseCommand@LINHA_DST_INVALIDA proc near
		ErrorNumberOutOfBounds <LINHA_DST>
		ret
	ParseCommand@LINHA_DST_INVALIDA endp

	ParseCommand@LINHA_ORG_INVALIDA proc near
		ErrorNumberOutOfBounds <LINHA_ORG>
		ret
	ParseCommand@LINHA_ORG_INVALIDA endp



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
		.if (carry?)
			call ErrorOpen
		.endif
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
		.if (carry?)
			call ErrorRead
		.endif

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
		.if (carry?)
			call ErrorRead
		.endif
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
				inc al                 ; TotalCol starts at 0
				mov NPlusOne, al
				dec al                 ; ax = N
				mov N,        al       ; TotalCol starts at 0
				dec al
				.if (TotalRow != al)
					jmp ErrorRowCount
				.elseif (al < 2 ) || (al > 7)
					jmp ErrorInvalidN
				.endif
				jmp EndReading
			.endif

			mov bl, FileBuffer

			.if bl == 3Bh
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
		.ForRow:                   ; for (row = 0; row < N; row++)
			cmp ch, N      ; row < N
			jge .EndForRow

			mov      cl, 0 ; col = 0
			.ForCol:       ; for (col = 0; col < NPlusOne; col++)
				cmp cl, NPlusOne ; col < NPlusOne
				jge .EndForCol

				mov ax, sword ptr [bx]
				invoke printf_d_padded, ax, dx

				add bx, 2 ; size in bytes of a sword

				inc cl      ; col ++
				jmp .ForCol
			.EndForCol:
			putc CR
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
