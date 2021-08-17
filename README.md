# Lilith

Lilith is an attempt at making a Forth that looks more like a Lisp, because I like the _idea_ of Forth, but I find concatenative languages to be very hard to reason about.  I'm a big fan of variables.


## Set-up and Usage

Lilith is written in x86_64 assembly, so you'll need a machine that can run it—which shouldn't be a problem, I assume.  You'll also need the NASM assembler.  Here's how I installed it:

```bash
$ sudo pacman -S nasm
```

To run Lilith, clone the repo and execute `make run`:

```bash
$ git clone https://github.com/xlambein/lilith.git
$ cd lilith
$ make run
```

The interpreter reads S-expressions until end-of-input (usually `CTRL+D` in a CLI).  Here's an example:

```lisp
(print (+ 1 2 3))
6
(print
  (* 2
     (+ 3 4)
     5))
70
```

Currently only `print`, `+` and `*` are supported 🙃


## Implementation

The Lilith interpreter works by reading tokens from STDIN one at a time, and executing an action based on the token, typically pushing a value onto the CPU stack.  More specifically:

- `(` produces a new stack frame
- symbols are looked up and:
  - macros are run immediately
  - functions have the address to their source code pushed onto the stack
- literals (i.e., integers) are parsed and pushed onto the stack
- `)` executes the first symbol in the current stack frame

Like Forth words, symbols are stored in a dictionary (linked list), along with their source code.  When reading a token, the interpreter looks up in the dictionary to find the associated symbol header, which indicates whether the symbol is a macro or a function, and where its source code is located.  `(` and `)` are actually macros.

When executed, a symbol is expected to place its return value(s) at the start of its stack frame.  Afterwards, it must pop the current stack frame and continue the interpreter.

Let's visualize a call to the interpreter for the input `(+ 1 (* 2 3))`.  

- `#` signifies the start address of the stack, and `#-x` is `x` items below the start of the stack;
- `&x` signifies the address of `x`
- `rsp` is the stack pointer, located at the bottom of the stack, which grows downwards;
- `rbp` is the frame pointer, indicating the current stack frame;
- `rbx` is the return address, indicating where the previous stack frame is located, so that a symbol can pop its stack frame when it's done.

Each item on the stack is represented inside a little `[box]`.  Addresses that point to the stack (e.g., `rbp`, `#`) are represented without a box.  `rsp` always points to the bottom, so it's not displayed.  `EOI` is the end-of-input token, and `exec x` is just a way to visually split the execution of `)` and of the associated symbol.

```
token  rsp      rbp      rbx    stack (grows dowwards, to the left)
(      #        #        #       rbp   rbx  #
+      #-1      #-1      #       rbp  [  #]  rbx  #
1      #-2      #-1      #      [ &+]  rbp  [  #]  rbx  #
(      #-3      #-1      #      [  1] [ &+]  rbp  [  #]  rbx  #
*      #-4      #-4      #       rbp  [#-1] [  1] [ &+] [  #]  rbx  #
2      #-5      #-4      #      [ &*]  rbp  [#-1] [  1] [ &+] [  #]  rbx  #
3      #-6      #-4      #      [  2] [ &*]  rbp  [#-1] [  1] [ &+] [  #]  rbx  #
)      #-7      #-4      #      [  3] [  2] [ &*]  rbp  [#-1] [  1] [ &+] [  #]  rbx  #
exec * #-7      #-4      #-1    [  3] [  2] [ &*]  rbp  [#-1] [  1] [ &+]  rbx  [  #] #
)      #-4      #-1      #-1    [  5] [  1] [ &+]  rbp   rbx  [  #] #
exec + #-4      #-1      #      [  5] [  1] [ &+]  rbp  [  #]  rbx  #
EOI    #-1      #        #      [  6]  rbp   rbx  #
```


