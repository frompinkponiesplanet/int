BITS 16

ORG 0x7C00


; ============================================================

; REAL MODE MONITOR 2.0

;

; Stage 1: Bootloader

; Stage 2: System Monitor

;

; CPU:  x86 Real Mode

; BIOS: INT 13h, INT 1Ah

; IRQ:  INT 1Ch, INT 09h

; VIDEO: B800:0000

;

; ============================================================


; ============================================================

; STAGE 1 — BOOTLOADER

; ============================================================


boot:


    cli


    xor ax, ax

    mov ds, ax

    mov es, ax


    mov ss, ax

    mov sp, 0x7C00


    cld


    mov [boot_drive], dl


    sti


; ------------------------------------------------------------

; Загружаем Stage 2 по одному сектору.

;

; Это исключает пересечение границ дорожек.

;

; Дискета:

; 18 секторов на дорожку.

;

; Stage 2:

; Сектора 2-17.

;

; Адрес загрузки:

; 0000:7E00.

; ------------------------------------------------------------


    mov byte [current_sector], 2

    mov word [remaining_sectors], 16

    mov word [destination], 0x7E00


load_loop:


    mov byte [retry_count], 3


read_sector:


    xor ax, ax

    mov es, ax


    mov bx, [destination]


    mov ah, 0x02

    mov al, 1


    mov ch, 0

    mov cl, [current_sector]

    mov dh, 0


    mov dl, [boot_drive]


    int 0x13


    jnc sector_loaded


    ; При ошибке сбрасываем дисковод.


    xor ah, ah

    mov dl, [boot_drive]

    int 0x13


    dec byte [retry_count]

    jnz read_sector


    jmp boot_error


sector_loaded:


    inc byte [current_sector]


    add word [destination], 512


    dec word [remaining_sectors]


    jnz load_loop


    jmp 0x0000:stage2


boot_error:


    mov si, error_message


.error_loop:


    lodsb


    test al, al

    jz .halt


    mov ah, 0x0E

    int 0x10


    jmp .error_loop


.halt:


    cli

    hlt

    jmp .halt


boot_drive:

    db 0


current_sector:

    db 0


retry_count:

    db 0


remaining_sectors:

    dw 0


destination:

    dw 0


error_message:

    db 'BOOT ERROR: DISK READ FAILED', 0


; ------------------------------------------------------------

; Размер первого этапа: 512 байт.

; ------------------------------------------------------------


times 510 - ($ - $$) db 0


dw 0xAA55


; ============================================================

; STAGE 2 — REAL MODE MONITOR

;

; Загружается по адресу 0000:7E00.

; ============================================================


stage2:


    cli


    xor ax, ax


    mov ds, ax

    mov es, ax


    mov ss, ax

    mov sp, 0x7C00


    cld


    ; --------------------------------------------------------

    ; Включаем текстовый режим 80x25.

    ; --------------------------------------------------------


    mov ax, 0x0003

    int 0x10


    ; Скрываем курсор.


    mov ah, 0x01

    mov cx, 0x2000

    int 0x10


; ============================================================

; ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ

; ============================================================


    mov dword [total_ticks], 0

    mov dword [tick_accum], 0


    mov word [event_count], 0

    mov word [key_count], 0


    mov byte [dirty], 1


    mov byte [last_ascii], 0

    mov byte [last_scan], 0


    mov byte [last_event], 0


    mov byte [modifier_flags], 0


    mov byte [hours], 0

    mov byte [minutes], 0

    mov byte [seconds], 0


; ============================================================

; ПОЛУЧЕНИЕ НАЧАЛЬНОГО ВРЕМЕНИ

; ============================================================


    call update_rtc


; ============================================================

; УСТАНОВКА ОБРАБОТЧИКОВ ПРЕРЫВАНИЙ

; ============================================================


install_handlers:


    cli


    ; --------------------------------------------------------

    ; INT 1Ch.

    ;

    ; Вектор находится по адресу:

    ; 0000:0070.

    ; --------------------------------------------------------


    mov ax, [0x0070]

    mov [old1c], ax


    mov ax, [0x0072]

    mov [old1c+2], ax


    mov word [0x0070], timer_handler

    mov word [0x0072], 0x0000


    ; --------------------------------------------------------

    ; INT 09h.

    ;

    ; Вектор находится по адресу:

    ; 0000:0024.

    ; --------------------------------------------------------


    mov ax, [0x0024]

    mov [old09], ax


    mov ax, [0x0026]

    mov [old09+2], ax


    mov word [0x0024], keyboard_handler

    mov word [0x0026], 0x0000


    sti


; ============================================================

; MAIN LOOP

;

; Основной цикл ничего не выводит постоянно.

;

; Отрисовка происходит только при изменении данных.

; ============================================================


main_loop:


    cli


    cmp byte [dirty], 0

    jne update_screen


    ; STI непосредственно перед HLT.

    ;

    ; Это предотвращает потерю события между

    ; проверкой dirty и переходом в спящий режим.


    sti

    hlt


    jmp main_loop


update_screen:


    mov byte [dirty], 0


    sti


    ; Получаем актуальное время RTC.


    call update_rtc


    ; Запрещаем прерывания на время отрисовки.

    ; Это обеспечивает согласованность отображаемых данных.


    cli


    call render_screen


    sti


    jmp main_loop


; ============================================================

; RTC — ПОЛУЧЕНИЕ СИСТЕМНОГО ВРЕМЕНИ

;

; BIOS INT 1Ah, AH=02h.

;

; CH = часы BCD.

; CL = минуты BCD.

; DH = секунды BCD.

;

; ============================================================


update_rtc:


    push ax

    push bx

    push cx

    push dx


    mov ah, 0x02

    int 0x1A


    jc .rtc_done


    ; Сохраняем значения RTC.


    mov [rtc_hour], ch

    mov [rtc_minute], cl

    mov [rtc_second], dh


    ; Часы.


    mov al, [rtc_hour]

    call bcd_to_bin


    mov [hours], al


    ; Минуты.


    mov al, [rtc_minute]

    call bcd_to_bin


    mov [minutes], al


    ; Секунды.


    mov al, [rtc_second]

    call bcd_to_bin


    mov [seconds], al


.rtc_done:


    pop dx

    pop cx

    pop bx

    pop ax


    ret


; ============================================================

; BCD -> BIN

;

; Пример:

; 0x23 -> 23

; 0x45 -> 45

; ============================================================


bcd_to_bin:


    push bx

    push dx


    mov bl, al


    and al, 0x0F


    and bl, 0xF0

    shr bl, 4


    mov dl, al


    mov al, bl

    mov bl, 10


    mul bl


    add al, dl


    pop dx

    pop bx


    ret


; ============================================================

; INT 1Ch — ОБРАБОТЧИК ТАЙМЕРА

;

; BIOS вызывает INT 1Ch примерно 18.2065 раз/сек.

;

; Мы:

; 1. Вызываем старый обработчик.

; 2. Увеличиваем счётчик тиков.

; 3. Используем аккумулятор для периодического обновления.

;

; Системное время берётся непосредственно из RTC.

; ============================================================


timer_handler:


    push ax

    push bx

    push cx

    push dx

    push ds

    push es


    ; Вызываем старый обработчик INT 1Ch.

    ;

    ; PUSHF + CALL FAR совместимы с его IRET.


    pushf

    call far [cs:old1c]


    ; DS = 0000.


    xor ax, ax

    mov ds, ax


    ; Общее количество тиков.


    inc dword [total_ticks]


    ; Аккумулятор PIT.

    ;

    ; 65536 / 1193182 секунды за один тик.


    add dword [tick_accum], 65536


    cmp dword [tick_accum], 1193182

    jb .timer_exit


    sub dword [tick_accum], 1193182


    ; Требуется обновить интерфейс.


    mov byte [dirty], 1


.timer_exit:


    pop es

    pop ds

    pop dx

    pop cx

    pop bx

    pop ax


    iret


; ============================================================

; INT 09h — ОБРАБОТЧИК КЛАВИАТУРЫ

;

; BIOS продолжает самостоятельно обрабатывать клавиатуру.

;

; Мы:

; 1. Сохраняем указатель BIOS tail.

; 2. Передаём управление старому INT 09h.

; 3. Проверяем, добавилось ли слово в BIOS-буфер.

; 4. Сохраняем ASCII и Scan Code.

; 5. Считываем флаги модификаторов из BDA.

;

; ВАЖНО:

; Порт 0x60 самостоятельно не читаем.

; ============================================================


keyboard_handler:


    push ax

    push bx

    push cx

    push dx

    push si

    push di

    push bp

    push ds

    push es


    xor ax, ax

    mov ds, ax


    ; Считаем все аппаратные события IRQ1.


    inc word [event_count]


    ; Запоминаем старый указатель tail BIOS.


    mov ax, [0x041C]

    mov [old_tail], ax


    ; Вызываем старый обработчик INT 09h.


    pushf

    call far [cs:old09]


    ; После возвращения BIOS анализируем буфер.


    xor ax, ax

    mov ds, ax


    mov ax, [0x041C]


    cmp ax, [old_tail]

    je .no_new_key


    ; --------------------------------------------------------

    ; Получаем новое слово из BIOS-буфера.

    ;

    ; BIOS BDA:

    ; Сегмент 0040h.

    ;

    ; Старый tail указывает на записанное слово.

    ; --------------------------------------------------------


    mov bx, [old_tail]


    mov ax, 0x0040

    mov es, ax


    mov ax, [es:bx]


    ; AL = ASCII.

    ; AH = Scan Code.


    mov [last_ascii], al

    mov [last_scan], ah

    ; Освобождаем BIOS keyboard buffer после копирования клавиши.
    ; Это не даёт очереди BIOS заполниться.
    push ax
    mov ax, [0x041C]       ; BDA keyboard buffer tail
    mov [0x041A], ax       ; BDA keyboard buffer head = tail
    pop ax

    mov byte [last_event], 1


    inc word [key_count]


    jmp .read_modifiers


.no_new_key:


    ; Аппаратное событие было,

    ; но BIOS не добавил новое слово в буфер.


    mov byte [last_event], 2


.read_modifiers:


    ; --------------------------------------------------------

    ; Читаем состояние клавиатуры BIOS.

    ;

    ; 0040:0017 — Keyboard Shift Flags 1.

    ; --------------------------------------------------------


    mov ax, 0x0040

    mov es, ax


    mov al, [es:0x0017]


    xor bx, bx


    ; SHIFT: bit 0 или bit 1.


    test al, 0x03

    jz .no_shift


    or bl, 0x01


.no_shift:


    ; CTRL: bit 2.


    test al, 0x04

    jz .no_ctrl


    or bl, 0x02


.no_ctrl:


    ; ALT: bit 3.


    test al, 0x08

    jz .no_alt


    or bl, 0x04


.no_alt:


    ; CAPS LOCK: bit 6.


    test al, 0x40

    jz .no_caps


    or bl, 0x08


.no_caps:


    ; NUM LOCK: bit 5.


    test al, 0x20

    jz .no_num


    or bl, 0x10


.no_num:


    ; SCROLL LOCK: bit 4.


    test al, 0x10

    jz .no_scroll


    or bl, 0x20


.no_scroll:


    mov [modifier_flags], bl


    ; Устанавливаем флаг обновления экрана.


    mov byte [dirty], 1


.keyboard_exit:


    pop es

    pop ds

    pop bp

    pop di

    pop si

    pop dx

    pop cx

    pop bx

    pop ax


    iret


; ============================================================

; RENDER SCREEN

;

; Прямой вывод в видеопамять B800:0000.

;

; Вызывается только основным циклом.

; Во время вызова прерывания запрещены.

; ============================================================


%macro PRINT 3


    mov di, (%1 * 160 + %2 * 2)

    mov si, %3


    call print_string


%endmacro


render_screen:


    push ax

    push bx

    push cx

    push dx

    push si

    push di

    push es


    ; ES указывает на видеопамять.


    mov ax, 0xB800

    mov es, ax


    ; --------------------------------------------------------

    ; Очищаем экран пробелами.

    ;

    ; 80 * 25 = 2000 слов.

    ; --------------------------------------------------------


    xor di, di


    mov ax, 0x0720

    mov cx, 2000


    rep stosw


    ; --------------------------------------------------------

    ; Заголовок.

    ; --------------------------------------------------------


PRINT 1, 27, title


    ; --------------------------------------------------------

    ; SYSTEM.

    ; --------------------------------------------------------


PRINT 3, 5, system_title


PRINT 4, 5, time_label


    mov di, (4 * 160 + 22 * 2)


    mov al, [hours]

    call print_decimal_2


    mov al, ':'

    call put_char


    mov al, [minutes]

    call print_decimal_2


    mov al, ':'

    call put_char


    mov al, [seconds]

    call print_decimal_2


    ; Количество тиков.


PRINT 5, 5, ticks_label


    mov di, (5 * 160 + 22 * 2)


    mov ax, [total_ticks+2]

    call print_hex_word


    mov ax, [total_ticks]

    call print_hex_word


PRINT 6, 5, status_label

PRINT 6, 22, running_text


    ; --------------------------------------------------------

    ; KEYBOARD.

    ; --------------------------------------------------------


PRINT 9, 5, keyboard_title


PRINT 10, 5, character_label


    mov di, (10 * 160 + 22 * 2)


    mov al, [last_ascii]

    call print_character


PRINT 11, 5, ascii_label


    mov di, (11 * 160 + 22 * 2)


    mov al, [last_ascii]

    call print_hex_byte


PRINT 12, 5, scan_label


    mov di, (12 * 160 + 22 * 2)


    mov al, [last_scan]

    call print_hex_byte


PRINT 13, 5, event_label


    cmp byte [last_event], 1

    je .key_pressed


PRINT 13, 22, no_key_text


    jmp .modifiers


.key_pressed:


PRINT 13, 22, pressed_text


    ; --------------------------------------------------------

    ; MODIFIERS.

    ; --------------------------------------------------------


.modifiers:


PRINT 15, 5, shift_label


    mov di, (15 * 160 + 22 * 2)


    mov al, [modifier_flags]

    and al, 0x01


    call print_on_off


PRINT 16, 5, ctrl_label


    mov di, (16 * 160 + 22 * 2)


    mov al, [modifier_flags]

    and al, 0x02


    shr al, 1


    call print_on_off


PRINT 17, 5, alt_label


    mov di, (17 * 160 + 22 * 2)


    mov al, [modifier_flags]

    and al, 0x04


    shr al, 2


    call print_on_off


PRINT 18, 5, caps_label


    mov di, (18 * 160 + 22 * 2)


    mov al, [modifier_flags]

    and al, 0x08


    shr al, 3


    call print_on_off


PRINT 19, 5, num_label


    mov di, (19 * 160 + 22 * 2)


    mov al, [modifier_flags]

    and al, 0x10


    shr al, 4


    call print_on_off


    ; --------------------------------------------------------

    ; STATISTICS.

    ; --------------------------------------------------------


PRINT 21, 5, statistics_title


PRINT 22, 5, events_label


    mov di, (22 * 160 + 22 * 2)


    mov ax, [event_count]

    call print_hex_word


PRINT 23, 5, keys_label


    mov di, (23 * 160 + 22 * 2)


    mov ax, [key_count]

    call print_hex_word


    pop es

    pop di

    pop si

    pop dx

    pop cx

    pop bx

    pop ax


    ret


; ============================================================

; ВЫВОД СТРОКИ

;

; DS:SI -> строка.

; ES:DI -> видеопамять.

; ============================================================


print_string:


    push ax


.next:


    lodsb


    test al, al

    jz .done


    call put_char


    jmp .next


.done:


    pop ax


    ret


; ============================================================

; ВЫВОД СИМВОЛА

;

; AL = ASCII.

; ============================================================


put_char:


    mov ah, 0x07


    stosw


    ret


; ============================================================

; ВЫВОД ДВУХ ДЕСЯТИЧНЫХ ЦИФР

;

; AL = 0..99.

; ============================================================


print_decimal_2:


    push ax

    push bx

    push dx


    xor ah, ah


    mov bl, 10


    div bl


    ; AL = десятки.

    ; AH = единицы.


    mov dl, ah


    add al, '0'

    call put_char


    mov al, dl

    add al, '0'


    call put_char


    pop dx

    pop bx

    pop ax


    ret


; ============================================================

; HEX: AL -> две шестнадцатеричные цифры.

; ============================================================


print_hex_byte:


    push ax

    push bx


    mov bl, al


    shr al, 4


    call print_hex_nibble


    mov al, bl

    and al, 0x0F


    call print_hex_nibble


    pop bx

    pop ax


    ret


; ============================================================

; HEX: AX -> четыре шестнадцатеричные цифры.

; ============================================================


print_hex_word:


    push ax


    mov al, ah

    call print_hex_byte


    pop ax


    call print_hex_byte


    ret


; ============================================================

; HEX: AL -> одна шестнадцатеричная цифра.

; ============================================================


print_hex_nibble:


    and al, 0x0F


    cmp al, 9

    jbe .number


    add al, 7


.number:


    add al, '0'


    call put_char


    ret


; ============================================================

; ВЫВОД СОСТОЯНИЯ ON/OFF.

;

; AL = 0 -> OFF.

; AL != 0 -> ON.

; ============================================================


print_on_off:


    test al, al


    jz .off


    mov si, on_text

    call print_string


    ret


.off:


    mov si, off_text

    call print_string


    ret


; ============================================================

; ОТОБРАЖЕНИЕ ASCII-СИМВОЛА.

; ============================================================


print_character:


    cmp al, 33

    jb .control


    cmp al, 126

    ja .control


    call put_char


    ret


.control:


    mov si, control_text

    call print_string


    ret


; ============================================================

; ПЕРЕМЕННЫЕ

; ============================================================


; Сохранённые BIOS-векторы.


old1c:

    dw 0, 0


old09:

    dw 0, 0


; BIOS keyboard tail.


old_tail:

    dw 0


; Счётчик аппаратных тиков.


total_ticks:

    dd 0


; Аккумулятор PIT.


tick_accum:

    dd 0


; Счётчики клавиатуры.


event_count:

    dw 0


key_count:

    dw 0


; Системное время.


hours:

    db 0


minutes:

    db 0


seconds:

    db 0


; Временные значения RTC в BCD.


rtc_hour:

    db 0


rtc_minute:

    db 0


rtc_second:

    db 0


; Флаг обновления экрана.


dirty:

    db 0


; Последняя клавиша.


last_ascii:

    db 0


last_scan:

    db 0


; 0 = нет события.

; 1 = BIOS добавил клавишу в буфер.

; 2 = аппаратное событие без нового слова в буфере.


last_event:

    db 0


; Флаги модификаторов.

;

; bit 0 = SHIFT

; bit 1 = CTRL

; bit 2 = ALT

; bit 3 = CAPS LOCK

; bit 4 = NUM LOCK

; bit 5 = SCROLL LOCK


modifier_flags:

    db 0


; ============================================================

; ТЕКСТОВЫЕ ДАННЫЕ

; ============================================================


title:

    db 'REAL MODE MONITOR', 0


system_title:

    db 'SYSTEM', 0


time_label:

    db 'TIME:', 0


ticks_label:

    db 'TIMER INTERRUPTS:', 0


status_label:

    db 'STATUS:', 0


running_text:

    db 'RUNNING', 0


keyboard_title:

    db 'KEYBOARD', 0


character_label:

    db 'LAST CHARACTER:', 0


ascii_label:

    db 'ASCII:', 0


scan_label:

    db 'SCANCODE:', 0


event_label:

    db 'EVENT:', 0


pressed_text:

    db 'PRESSED', 0


no_key_text:

    db 'NO BIOS KEY', 0


shift_label:

    db 'SHIFT:', 0


ctrl_label:

    db 'CTRL:', 0


alt_label:

    db 'ALT:', 0


caps_label:

    db 'CAPS LOCK:', 0


num_label:

    db 'NUM LOCK:', 0


statistics_title:

    db 'STATISTICS', 0


events_label:

    db 'KEY EVENTS:', 0


keys_label:

    db 'KEY PRESSES:', 0


on_text:

    db 'ON', 0


off_text:

    db 'OFF', 0


control_text:

    db 'N/A', 0


; ============================================================

; КОНЕЦ STAGE 2

; ============================================================


stage2_end:


%if (stage2_end - stage2) > 8192

    %error "ERROR: Stage 2 exceeds 16 sectors!"

%endif