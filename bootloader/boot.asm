;
; 系统引导程序
;
; treelite(c.xinle@gmail.com)
;

; 引导程序会被 BIOS 加载到 0x7C00 位置
; 使用 org 可以指定后续所有的编译地址都加上这个偏移量
; 以使编译后的地址与实际运行地址一致
org 7C00h

; Kernel loaded address
KERNEL_LOADED_ADDRESS equ 0x7E00

; Kernel code address
KERNEL_CODE_ADDRESS equ 0x800000

; 指定为16位汇编
bits 16

; Set boot stack
mov ax, 0x7C0
mov ss, ax
mov ax, 0
mov sp, ax

; Query memory info
; Get the size of physical memory
mov ax, 0
mov es, ax
mov di, M_INFO
mov ebx, 0
mov edx, 0x534D4150
mov ecx, 20

queryMemory:
    mov eax, 0xE820
    int 0x15
	; Error
    jc queryMemoryEnd
    mov eax, [M_INFO + 16]
    cmp eax, 1
	; If it's reserved
	; Query next one
    jnz queryMemoryNext
    ; Get base address
    mov eax, [M_INFO]
    ; Add length
    add eax, [M_INFO + 8]
    mov [M_SIZE], eax
    queryMemoryNext:
        cmp ebx, 0
        jnz queryMemory

queryMemoryEnd:

; 加载内核文件
; 读取引导区后内核文件到 0x7E00 位置
mov ax, 0x7E0
mov es, ax
mov bx, 0
; TODO
; 假设内核文件大小在50个扇区以内
; 一次性加载内核文件
mov ax, 50
push ax
mov ax, 1 ;从2号扇区开始加载
push ax
call readSector

; 准备进入保护模式
; 屏蔽中断
cli

; 加载全局描述符表
lgdt [GDTR]

; 打开第21条地址线(A20)
in al, 0x92
or al, 2
out 0x92, al

; 开启保护模式
mov eax, cr0
or al, 1
mov cr0, eax

; 远跳，其目的是刷新 CS 段寄存器
; 并且终止CPU流线操作，抛弃所有已进入流水管线执行的结果
; 0x8 为段选择子，选择代码段
jmp 0x8:protected

%include 'util/io.asm'

; 以下代码开始使用 32 位编码
bits 32
protected:
    ; 重新设置所有的段寄存器
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    ; 选择 VGA
    mov ax, 0x20
    mov gs, ax

    mov ax, 0x18
    mov ss, ax
    ;Set the stack under the kernel code
    mov eax, KERNEL_CODE_ADDRESS
    mov esp, eax


    ; 展开内核文件到运行地址
    mov esi, KERNEL_LOADED_ADDRESS
    ; Save kernel entry
    mov eax, [esi + 24]

    mov [KERNEL_ENTRY], eax
    ; Program header offset
    mov ebx, [esi + 28]
    ; Program header item size
    mov edx, 0
    mov dx, [esi + 42]
    ; Program header item count
    mov ecx, 0
    mov cx, [esi + 44]

    ; Load segment by program header item
    add esi, ebx
    loadSegment:
        ; p_type
        mov eax, [esi]
        ; TYPE = 1 -> a loadable segment
        cmp eax, 1
        jnz nextSegment

        ; load program segment
        ; Segment size (in file)
        push ecx
        mov ecx, [esi + 16]

        ; Segment virtual address
        mov edi, [esi + 8]

        ; Segment file address
        push esi
        mov ebx, [esi + 4]
        mov esi, KERNEL_LOADED_ADDRESS
        add esi, ebx

        ; Copy segment to runtime address
        cpySegment:
            lodsb
            stosb
            loop cpySegment

        pop esi
        ; Compare the segment size and the memory size
        ; If the memory size is bigger
        ; Extend zero up to the memory size
        mov ecx, [esi + 20]
        sub ecx, [esi + 16]
        jz finishCpy

        extendZero:
            mov byte [edi], 0
            inc edi
            loop extendZero

        finishCpy:
            pop ecx

    nextSegment:
        add esi, edx
        loop loadSegment

    ; Pass memory size as a argument
    mov eax, [M_SIZE]
    push eax
    ; Go to kernel
    call [KERNEL_ENTRY]
    end jmp $

; 全局描述符表
; TODO 区分内核段与用户段
GDT:
    ; Null
    times 2 dd 0
    ; Code descriptor
    ; all memory
    dw 0xFFFF ; 段界限(低16位)
    dw 0      ; 段基地址(低16位)
    db 0      ; 段基地址(中8位) 0
    db 0x9A   ; 1001 1010（P:1, DPL:0, S:1, TYPE:1010）
    db 0xCF   ; 1100 1111 (G:1, D/B:1, L:0, AVL:0, 段界限高4位:1111)
    db 0      ; 段基地址(高8位)
    ; Data descriptor
    ; all memory
    dw 0xFFFF
    dw 0
    db 0
    db 0x92   ; 10010010
    db 0xCF   ; 11001111
    db 0
    ; Stack descriptor
    ; 0x510000 - 0xFFFFFFFF
    ; dw 0xFAEF
    dw 0x0510
    dw 0
    db 0
    db 0x96   ; 10010110
    db 0xC0   ; 11001111
    db 0
    ; VGA descriptor
    dw 0x7FFF
    dw 0x8000
    db 0x0B
    db 0x92
    db 0x40
    db 0
GDT_LEN equ $ - GDT

; 全局描述符表地址与界限
GDTR:
    dw GDT_LEN - 1
    dd GDT

; 内核入口地址
KERNEL_ENTRY dd 0

; Physical memory size
M_SIZE dd 0

; Memory address range descriptor
M_INFO times 20 db 0

; 填充剩余的扇区空间
; 并标记当前扇区为引导区
times 512 - 2 - ($ - $$) db 0
; 以 0xAA55 结尾的扇区是可引导扇区
dw 0AA55h
