TARGET=lilith

.PHONY: run test

target/$(TARGET): target/$(TARGET).o
	cd target ; ld -o $(TARGET) $(TARGET).o

target/$(TARGET).o: target src/$(TARGET).asm
	cd src ; nasm -f elf64 -o ../target/$(TARGET).o $(TARGET).asm

target:
	mkdir target

run: target/$(TARGET)
	./target/$(TARGET)

test:
	env TEST=1 nasm -f elf64 -o target/$(TARGET)_test.o src/$(TARGET).asm
	ld -o target/$(TARGET)_test target/$(TARGET)_test.o
	./target/$(TARGET)_test && printf "\nAll tests passed\n" || printf "\nTests failed at assert %d\n" $$?
