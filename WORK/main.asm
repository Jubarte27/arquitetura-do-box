	.model small
	.stack
CR   equ 0dh
LF   equ 0ah
QUOT equ 22h

	.data

BuffSize               equ 100                                       ; tam. máximo dos dados lidos no buffer
FileName               db  "MAT.TXT",0                               ; Nome do arquivo a ser lido
FileBuffer             db  BuffSize dup (?)                          ; Buffer de leitura do arquivo
FileHandle             dw  0                                         ; Handler do arquivo
FileNameBuffer         db  150 dup (?)
caractere              db  0

MsgErroOpenFile        db  "Erro na abertura do arquivo.", CR, LF, 0
MsgErroReadFile        db  "Erro na leitura do arquivo.", CR, LF, 0
MsgUnexpectedCharacter db  "Erro: caracter inexperado: ",QUOT, 0
MsgCRLF                db  CR, LF, 0

; Used when reporting the error
TheUnexpectedChar      db  0,QUOT,0
; Variável interna usada na rotina printf_w
BufferWRWORD           db  10 dup (?)
; Variaveis para uso interno na função sprintf_w
sw_n                   dw  0
sw_f                   db  0
sw_m                   dw  0
; used in main
Row                    dw  0
Col                    dw  0
TotalRow               dw  0
TotalCol               dw  0

Matrix                 dw  0


	.code
	.startup

Main:
	; abre arquivo
	mov al,         0
	lea dx,         FileName
	mov ah,         3dh
	int 21h
	jc  ErrorOpen
    mov FileHandle, ax
Again:
    ; lê um caractere do arquivo
	mov bx, FileHandle
	mov ah, 3fh
	mov cx, 1
	lea dx, FileBuffer
	int 21h
	jc  ErrorRead

	; verifica se terminou o arquivo
	;if (ax==0) {
	;	fclose(bx=FileHandle);
	;	exit(0);
	;}
	cmp ax, 0
	jne Continua
	mov al, 0
	jmp CloseAndFinal
Continua:

	mov bl, FileBuffer

	.IF bl > '9' || bl < '0'
	jmp ErrorUnexpectedChar
    .ENDIF

	sub bl, '0'

NextLoop:
	;Contador[bl]++
	jmp Again

CloseAndFinal:
	; fecha arquivo
	mov ah, 3eh
	mov bx, FileHandle
	jmp Final

Final:
	.exit


ErrorOpen:
	lea  bx, MsgErroOpenFile
	call printf_s
	mov  al, 1
	jmp  Final

ErrorRead:
    lea  bx, MsgErroReadFile
	call printf_s
	mov  al, 1
	jmp  CloseAndFinal

ErrorUnexpectedChar:
    mov  TheUnexpectedChar, bl
    lea  bx,                MsgUnexpectedCharacter
	call printf_s
    lea  bx,                TheUnexpectedChar
	call printf_s
	mov  al,                1
	jmp  CloseAndFinal


;====================================================================
; Functions


;====================================================================
; A partir daqui, estão as funções já desenvolvidas
;	1) printf_s
;	2) printf_w
;	3) sprintf_w
;====================================================================
	
;--------------------------------------------------------------------
;Função Escrever um string na tela
;printf_s(char *s -> BX)
;--------------------------------------------------------------------
printf_s proc	near
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
	ret
printf_s endp

;
;--------------------------------------------------------------------
;Função: Escreve o valor de AX na tela
;printf("%
;--------------------------------------------------------------------
printf_w proc	near
	; sprintf_w(AX, BufferWRWORD)
	lea  bx, BufferWRWORD
	call sprintf_w
	
	; printf_s(BufferWRWORD)
	lea  bx, BufferWRWORD
	call printf_s
	
	ret
printf_w  endp

;
;--------------------------------------------------------------------
;Função: Converte um inteiro (n) para (string)
; sprintf(string->BX, "%d", n->AX)
;--------------------------------------------------------------------
sprintf_w proc	near
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
	ret
sprintf_w endp


;--------------------------------------------------------------------
end
;--------------------------------------------------------------------

