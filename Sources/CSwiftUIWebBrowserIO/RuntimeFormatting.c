/* printf for the Embedded Swift runtime's diagnostics.
 *
 * The only callers of the C library's formatted output in the browser build are the Concurrency runtime's error
 * messages (`swift_task_reportUnexpectedExecutor`, task-local misuse, a task group's overflow), which call
 * `vsnprintf`, `vprintf` and `swift_asprintf`. wasi-libc's printf engine (`printf_core`, its float printing, wide
 * characters and `strerror`) is about 11 KB of code for those messages. These definitions take its place: integers,
 * pointers, strings and characters with flags, width and precision, which is what the runtime formats, and a plain
 * fixed-point rendering of a floating-point argument. Output still goes through the C library's stdio. */
#if defined(__wasm__) && defined(SWIFTUIWEB_EMBEDDED_RUNTIME)
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { char *out; size_t capacity; size_t length; } Sink;

static void put(Sink *sink, char c) {
    if (sink->length + 1 < sink->capacity) sink->out[sink->length] = c;
    sink->length++;
}

static void pad(Sink *sink, char c, int count) { while (count-- > 0) put(sink, c); }

/* One converted field: `prefix` (a sign or 0x), then zeros up to `minimum` digits, then `body`, padded to `width`. */
static void field(Sink *sink, const char *prefix, const char *body, int length, int minimum, int width, int left, int zero) {
    int prefixLength = 0;
    while (prefix[prefixLength]) prefixLength++;
    int zeros = minimum > length ? minimum - length : 0;
    int fill = width - prefixLength - zeros - length;
    if (!left && !zero) pad(sink, ' ', fill);
    for (int i = 0; i < prefixLength; i++) put(sink, prefix[i]);
    if (!left && zero) pad(sink, '0', fill);
    pad(sink, '0', zeros);
    for (int i = 0; i < length; i++) put(sink, body[i]);
    if (left) pad(sink, ' ', fill);
}

static int digits(char *end, uintmax_t value, unsigned base, int upper) {
    const char *alphabet = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int count = 0;
    do { *--end = alphabet[value % base]; value /= base; count++; } while (value);
    return count;
}

int vsnprintf(char *restrict out, size_t capacity, const char *restrict format, va_list arguments) {
    Sink sink = { out, capacity, 0 };
    char buffer[72];
    for (const char *p = format; *p; p++) {
        if (*p != '%') { put(&sink, *p); continue; }
        int left = 0, plus = 0, space = 0, alternate = 0, zero = 0, width = 0, precision = -1, size = 0;
        for (;; p++) {
            if (p[1] == '-') left = 1; else if (p[1] == '+') plus = 1; else if (p[1] == ' ') space = 1;
            else if (p[1] == '#') alternate = 1; else if (p[1] == '0') zero = 1; else break;
        }
        if (p[1] == '*') { width = va_arg(arguments, int); if (width < 0) { left = 1; width = -width; } p++; }
        else while (p[1] >= '0' && p[1] <= '9') width = width * 10 + (*++p - '0');
        if (p[1] == '.') {
            p++; precision = 0;
            if (p[1] == '*') { precision = va_arg(arguments, int); p++; }
            else while (p[1] >= '0' && p[1] <= '9') precision = precision * 10 + (*++p - '0');
        }
        /* Length modifiers: h and hh narrow the int argument; l, ll, j, z and t pick the width of the argument. */
        for (;; p++) {
            char m = p[1];
            if (m == 'h') { size--; continue; }
            if (m == 'l') { size++; continue; }
            if (m == 'j' || m == 'L' || m == 'q') { size = 2; continue; }
            if (m == 'z' || m == 't') { size = sizeof(size_t) == 8 ? 2 : 1; continue; }
            break;
        }
        char conversion = *++p;
        if (!conversion) break;
        char *end = buffer + sizeof buffer;
        const char *prefix = "";
        switch (conversion) {
        case 'd': case 'i': {
            intmax_t value = size >= 2 ? va_arg(arguments, long long) : size == 1 ? va_arg(arguments, long) : va_arg(arguments, int);
            if (size == -1) value = (short)value; else if (size < -1) value = (signed char)value;
            uintmax_t magnitude = value < 0 ? (uintmax_t)0 - (uintmax_t)value : (uintmax_t)value;
            prefix = value < 0 ? "-" : plus ? "+" : space ? " " : "";
            int count = precision == 0 && magnitude == 0 ? 0 : digits(end, magnitude, 10, 0);
            field(&sink, prefix, end - count, count, precision, width, left, zero && precision < 0);
            break;
        }
        case 'u': case 'x': case 'X': case 'o': case 'p': {
            uintmax_t value;
            if (conversion == 'p') { value = (uintptr_t)va_arg(arguments, void *); prefix = "0x"; }
            else value = size >= 2 ? va_arg(arguments, unsigned long long) : size == 1 ? va_arg(arguments, unsigned long) : va_arg(arguments, unsigned int);
            if (size == -1) value = (unsigned short)value; else if (size < -1) value = (unsigned char)value;
            unsigned base = conversion == 'o' ? 8 : conversion == 'u' ? 10 : 16;
            if (alternate && value && base == 16) prefix = conversion == 'X' ? "0X" : "0x";
            int count = precision == 0 && value == 0 ? 0 : digits(end, value, base, conversion == 'X');
            if (alternate && base == 8 && (count == 0 || end[-count] != '0')) { *(end - count - 1) = '0'; count++; }
            field(&sink, prefix, end - count, count, precision, width, left, zero && precision < 0);
            break;
        }
        case 'c': {
            char c = (char)va_arg(arguments, int);
            field(&sink, "", &c, 1, 0, width, left, 0);
            break;
        }
        case 's': {
            const char *text = va_arg(arguments, const char *);
            if (!text) text = "(null)";
            int length = 0;
            while (text[length] && (precision < 0 || length < precision)) length++;
            field(&sink, "", text, length, 0, width, left, 0);
            break;
        }
        case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': case 'a': case 'A': {
            /* Diagnostics only: the integer part and `precision` (6) decimals, truncated, with no exponent form. */
            double value = va_arg(arguments, double);
            if (value != value) { field(&sink, "", "nan", 3, 0, width, left, 0); break; }
            prefix = value < 0 ? "-" : plus ? "+" : space ? " " : "";
            if (value < 0) value = -value;
            if (value > 1e18) { field(&sink, prefix, "inf", 3, 0, width, left, 0); break; }
            int places = precision < 0 ? 6 : precision > 17 ? 17 : precision;
            uintmax_t whole = (uintmax_t)value;
            double fraction = value - (double)whole;
            char *cursor = end;
            for (int i = 0; i < places; i++) fraction *= 10;
            uintmax_t decimals = (uintmax_t)fraction;
            for (int i = 0; i < places; i++) { *--cursor = (char)('0' + decimals % 10); decimals /= 10; }
            if (places > 0 || alternate) *--cursor = '.';
            cursor -= digits(cursor, whole, 10, 0);
            field(&sink, prefix, cursor, (int)(end - cursor), 0, width, left, zero);
            break;
        }
        case 'n': (void)va_arg(arguments, int *); break;
        default: put(&sink, conversion); break;
        }
    }
    if (capacity) out[sink.length < capacity ? sink.length : capacity - 1] = 0;
    return (int)sink.length;
}

int snprintf(char *restrict out, size_t capacity, const char *restrict format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(out, capacity, format, arguments);
    va_end(arguments);
    return length;
}

int vfprintf(FILE *restrict stream, const char *restrict format, va_list arguments) {
    char small[256];
    va_list copy;
    va_copy(copy, arguments);
    int length = vsnprintf(small, sizeof small, format, arguments);
    char *text = small;
    if (length >= (int)sizeof small && (text = malloc((size_t)length + 1))) vsnprintf(text, (size_t)length + 1, format, copy);
    else if (!text) { text = small; length = (int)sizeof small - 1; }
    va_end(copy);
    fwrite(text, 1, (size_t)length, stream);
    if (text != small) free(text);
    return length;
}

int fprintf(FILE *restrict stream, const char *restrict format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int length = vfprintf(stream, format, arguments);
    va_end(arguments);
    return length;
}

int vprintf(const char *restrict format, va_list arguments) { return vfprintf(stdout, format, arguments); }

int printf(const char *restrict format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int length = vfprintf(stdout, format, arguments);
    va_end(arguments);
    return length;
}
#endif
