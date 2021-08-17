%macro	exit 1
	mov	rdi, %1
	mov	rax, SYSCALL_EXIT
	syscall
%endmacro

%macro	next 0
	mov	rsp, rbp
	mov	rbp, rbx	; pop stack frame
	jmp eval_next_word
%endmacro

%define prev_link 0

; **********************
; defcode	defines a new codeword
; 
; In:	%1	word name
;	%2	label for the word
;	%3	flags (optional, defaults to 0)
; **********************
%macro	defcode 2-3 0
	SECTION .data
	align 8
%2:
	dq prev_link		; prev link in dictionary
	%define prev_link %2	; update prev_link to point here
	%strlen %%word_length %1
	db %3			; flags
	db %%word_length	; length of word label
	db %1			; word label
	align 8
	dq code_%2  		; address of the code

	SECTION .text
code_%2:
%endmacro

%include "probes.asm"		; debugging stuff


; **********************
; Useful constants
; **********************
	SECTION .data

; Syscalls
	SYSCALL_READ equ 0
	SYSCALL_WRITE equ 1
	SYSCALL_EXIT equ 60

; File descriptors
	STDIN equ 0
	STDOUT equ 1

; Flags for words
	FLAG_IMMEDIATE equ 0x1

	SECTION .text
; **********************


; **********************
; x86_64 System-V Calling Convention
; **********************
;
; (ref: https://wiki.osdev.org/System_V_ABI)
;
; Parameters to functions are passed in the registers
; rdi, rsi, rdx, rcx, r8, r9, and further values are passed
; on the stack in reverse order.
; 
; Functions preserve the registers rbx, rsp, rbp, r12, r13, r14, and r15.
;
; rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11 are scratch registers
;
; The return value is stored in the rax register, or if it is
; a 128-bit value, then the higher 64-bits go in rdx.
; **********************


; **********************
; parse_int	parses an integer from a string
;
; In:	rdi	addr of string to parse
;	rsi	length of string to parse
; Out:	rax	parsed value
; **********************
parse_int:
	xor	rax, rax	; accumulator
	mov	rcx, 10		; base
	xor	r8, r8		; index
.next_byte:
	cmp	r8, rsi		; end of string?
	je	.done

	mul	rcx		; rax = rax*rcx
				; rdx = overflow
	; TODO check overflow;
	mov	dl, [rdi+r8]	; fetch next character
	sub	rdx, '0'	; convert it to a digit
	add	rax, rdx	; add it to the acc
	inc	r8		; i++
	jmp	.next_byte
.done:
	ret


; **********************
; format_int	formats an int into a string buffer
;
; In:	rdi	value to format
;	rsi	destination buffer
; Out:	rax	number of bytes written
; **********************
format_int:
	push	rbp
	mov	rbp, rsp

	mov	rax, rdi	; value
	mov	rcx, 10		; base = 10

; Compute the digits from least- to most-significant,
; and store them on the stack
.next_byte:
	xor	rdx, rdx	; reset rdx because div uses it as upper bytes 😐
	div	rcx		; rax = rdx:rax/rcx
				; rdx = rax%rcx
	add	rdx, 0x30	; convert to ASCII digit
	push	rdx		; (not very space-efficient:
				;  we use a whole word for a byte)

	cmp	rax, 0		; check whether there's anything left to print
	jne	.next_byte	; if so, loop

; Compute the number of bytes written by measuring the height of the stack
	mov	rax, rbp	; rax = # of bytes written = (rbp - rsp) / 8
	sub	rax, rsp	; (remember that rsp <= rbp)
	shr	rax, 3

; Successively pop from the stack and write each digit
; from most- to least-significant
.write:
	; pop each byte one by one and write it, until rsp == rbp
	pop	rdx		; pop next number
	mov	[rsi], dl	; we only want a byte (not very hungry)
	inc	rsi		; next location
	; TODO buffer overflow check
	cmp	rsp, rbp	; did we pop everything?
	jne	.write		; if not, loop

.end:
	leave
	ret




; **********************
; read_next_word	reads the next word from STDIN, writing it to [word_buffer]
;
; Out:	rax	number of bytes written, 0 if EOI
; **********************
read_next_word:
	push	rbx		; rbx is a saved register
	mov	rbx, word_buffer	; pointer to next free buffer space

.skip_whitespace:
	cmp 	byte [.peek], ' '
	je	.is_whitespace	; skip space
	cmp 	byte [.peek], `\n`
	je	.is_whitespace	; skip newline
	jmp 	.break
.is_whitespace:
	; read next
	mov	rax, SYSCALL_READ
	mov	rdi, STDIN
	mov	rsi, .peek
	mov	rdx, 1
	syscall
	cmp	rax, 0		; check return code
	je .done		; return if we didn't read anything
	jmp 	.skip_whitespace

.break:
	; .peek now contains a non-whitespace

	; store [.peek] into the buffer
	mov	al, byte [.peek]
	mov	byte [rbx], al
	inc	rbx

	; return if we have a paren
	cmp 	byte [.peek], '('
	je	.done_but_reset_peek
	cmp 	byte [.peek], ')'
	je	.done_but_reset_peek

	; otherwise, read until whitespace/paren
.read_word:
	; read next
	mov	rax, SYSCALL_READ
	mov	rdi, STDIN
	mov	rsi, .peek
	mov	rdx, 1
	syscall
	cmp	rax, 0		; check return code
	je 	.done_but_reset_peek	; return if we didn't read anything

	; return if whitespace/paren
	cmp 	byte [.peek], ' '
	je	.done
	cmp 	byte [.peek], `\n`
	je	.done
	cmp 	byte [.peek], '('
	je	.done
	cmp 	byte [.peek], ')'
	je	.done

	; else, store [.peek] into the buffer
	mov	al, byte [.peek]
	mov	byte [rbx], al
	inc	rbx
	; TODO check for buffer overflow
	cmp	rbx, 256

	jmp 	.read_word

.done_but_reset_peek:
	mov	byte [.peek], ' '
.done:
	mov	rax, rbx
	sub	rax, word_buffer	; return number of bytes read
	pop rbx
	ret

	SECTION .data
.peek: db ' '			; peek buffer
word_buffer: times 255 db ' '	; word buffer
	SECTION .text


; **********************
; find_word	traverses the dictionary backwards, looking for the first
;		word matching the word in `word_buffer`
;
; /!\ Non-standard calling convention, because why not?
;
; In:	rdx	length of word in `word_buffer`
; Out:	rax	the address of the word's header if found, 0 otherwise
; **********************
find_word:
	mov	rdi, word_buffer
	mov	rax, last_word

.loop:
	mov	rax, [rax]	; fetch previous word
	cmp	rax, 0		; did we reach the end of the list?
	je	.done		; if so, return 0 (not found)

	; Check whether words are equal
	xor	rcx, rcx
	mov	cl, byte [rax+9]; get the length
	cmp	cl, dl		; are they equal?
	jne	.loop		; if not, loop

	lea	rsi, [rax+10] 	; addr. of label of current word
	push	rdi		; save address (jambled by repe)
	repe cmpsb		; find non-matching bytes in [rdi] and [rsi],
				; stopping after at most rcx operations
	pop	rdi
	jne	.loop		; if strings are different, loop
.done:
	ret


eval_next_word:
	call	read_next_word	; read next word
	cmp	rax, 0		; if nothing was read, report EOI
	je	.eoi

	mov	rdx, rax	; length read
	call	find_word	; look up word in dictionary
	cmp	rax, 0		; if not found, it's a literal
	je	.literal	; => process it below

	; otherwise, [rax] is now a codeword header
	xor	rcx, rcx	; get its flags
	mov	cl, [rax+8]
	xor	rdx, rdx	; get its label length
	mov	dl, [rax+9]

	; skip a few bytes to get rax to point at the codeword
	add	rax, 8		; skip link pointer
	add	rax, 1		; skip the flags
	add	rax, 1		; skip the length
	add	rax, rdx	; skip the label
	add	rax, 7		; 8-align
	and	rax, -8

	test	rcx, FLAG_IMMEDIATE	; test if it's an immediate (macro)
	jz	.func

.macro:
	; it's an immediate => run it immediately :-)
	jmp	[rax]

.func:
	; it's a function => push its codeword address
	push	qword [rax]
	jmp	eval_next_word	; continue interpreting

.literal:
	; it's an immediate => parse it and push it
	mov	rdi, word_buffer	; string to parse
	mov	rsi, rdx	; string length
	call	parse_int	; parse int
	push	rax		; push literal onto stack
	jmp	eval_next_word	; continue interpreting

.eoi:
	; we reached EOI, let's quit nicely
	exit	0


; **********************
; Here begin the codewords.
; **********************

; **********************
; lparen	creates a new stack frame
; **********************
defcode "(", lparen, FLAG_IMMEDIATE
	; made_it_here
	push 	rbp		; push current stack frame
	mov	rbp, rsp	; update stack frame to next free block
	jmp eval_next_word

; **********************
; rparen	runs the current stack frame
; **********************
defcode ")", rparen, FLAG_IMMEDIATE
	mov	rbx, [rbp]	; store previous stack frame in rbx
	jmp	[rbp-8]		; execute stack frame

; **********************
; plus		sums all its arguments
; **********************
defcode "+", plus
	pop	rax
.loop:
	pop	rcx
	cmp	rbp, rsp
	je	.done
	add	rax, rcx
	; TODO overflow
	jmp	.loop
.done:
	mov	[rbp], rax
	next

; **********************
; multiply	multiplies all its arguments
; **********************
defcode "*", multiply
	; Sum all its arguments
	pop	rax
.loop:
	pop	rcx
	cmp	rbp, rsp
	je	.done
	mul	rcx
	; TODO overflow
	jmp	.loop
.done:
	mov	[rbp], rax
	next

; **********************
; print		prints its argument to STDOUT
; **********************
defcode "print", print
	; Print its argument
	pop	rdi
	mov	rsi, .buf
	call format_int
	mov	byte [.buf+rax], `\n`
	inc	rax

	mov	 rdi, STDOUT
	mov	 rsi, .buf
	mov	 rdx, rax
	mov	 rax, SYSCALL_WRITE
	syscall

	next
	SECTION .bss
.buf: resb 20
	SECTION .text


	SECTION .data
last_word: dq prev_link		; address of the last word defined
	SECTION .text
	global _start
_start:
	mov	rbp, rsp	; make a fresh stack frame
	
	jmp eval_next_word	; run the interpreter

	exit	1		; this should never happen
