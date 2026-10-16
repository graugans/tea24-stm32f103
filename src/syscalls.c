#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

extern uint8_t _heap_start;
extern uint8_t _heap_end;

/* Minimal allocator backend for newlib malloc/new.
 * Heap grows upward inside [_heap_start, _heap_end].
 */
void *_sbrk(ptrdiff_t increment)
{
    static uint8_t *current_heap_end = 0;

    if (current_heap_end == 0) {
        current_heap_end = &_heap_start;
    }

    if (increment < 0) {
        errno = ENOMEM;
        return (void *)-1;
    }

    if ((current_heap_end + increment) > (&_heap_end)) {
        errno = ENOMEM;
        return (void *)-1;
    }

    uint8_t *previous_heap_end = current_heap_end;
    current_heap_end += increment;
    return previous_heap_end;
}

int _close(int file)
{
    (void)file;
    return -1;
}

int _fstat(int file, struct stat *st)
{
    (void)file;
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int file)
{
    (void)file;
    return 1;
}

off_t _lseek(int file, off_t ptr, int dir)
{
    (void)file;
    (void)ptr;
    (void)dir;
    return 0;
}

ssize_t _read(int file, void *ptr, size_t len)
{
    (void)file;
    (void)ptr;
    (void)len;
    return 0;
}

ssize_t _write(int file, const void *ptr, size_t len)
{
    (void)file;
    (void)ptr;
    return (ssize_t)len;
}
