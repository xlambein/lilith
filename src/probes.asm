
%macro	made_it_here 0
	push	rax
	push	rdi
	push	rsi
	push	rdx
	push	rcx
	push	r11
	mov	rdi, STDOUT
	mov	rsi, made_it_here_text
	mov	rdx, 17
	mov	rax, SYSCALL_WRITE
	syscall
	pop	r11
	pop	rcx
	pop	rdx
	pop	rsi
	pop	rdi
	pop	rax
%endmacro
	SECTION .rodata
made_it_here_text: db `*** made it here\n`
	SECTION .text

%macro	printbuf 2
	push	rax
	push	rdi
	push	rsi
	push	rdx
	push	rcx
	push	r11
	push	%2	; size
	push	%1	; addr
	mov	rdi, STDOUT
	pop	rsi	; addr
	pop	rdx	; size
	mov	rax, SYSCALL_WRITE
	syscall
	pop	r11
	pop	rcx
	pop	rdx
	pop	rsi
	pop	rdi
	pop	rax
%endmacro

;; print stack from most recent to oldest item, up to [rbp-8] including
dump_stack:
	push	rbx
	lea	rbx, [rsp+16]	; skip rbx and return address
.loop:
	cmp	rbx, rbp
	je	.done

	mov	rdi, [rbx]
	mov	rsi, .buf
	call	format_int
	mov	byte [.buf+rax], `\n`
	inc	rax

	mov	rdi, STDOUT
	mov	rsi, .buf
	mov	rdx, rax
	mov	rax, SYSCALL_WRITE
	syscall

	add	rbx, 8
	jmp	.loop
.done:
	pop	rbx
	ret
	SECTION .bss
.buf: resb 20
	SECTION .text
