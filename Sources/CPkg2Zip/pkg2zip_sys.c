#include "pkg2zip_sys.h"
#include "pkg2zip_utils.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static HANDLE gStdout;
static int gStdoutRedirected;
static UINT gOldCP;

void sys_output_init(void)
{
    gOldCP = GetConsoleOutputCP();
    SetConsoleOutputCP(CP_UTF8);
    gStdout = GetStdHandle(STD_OUTPUT_HANDLE);

    DWORD mode;
    gStdoutRedirected = !GetConsoleMode(gStdout, &mode);
}

void sys_output_done(void)
{
    SetConsoleOutputCP(gOldCP);
}

void sys_output(const char* msg, ...)
{
    char buffer[1024];

    va_list arg;
    va_start(arg, msg);
    vsnprintf(buffer, sizeof(buffer), msg, arg);
    va_end(arg);

    if (!gStdoutRedirected)
    {
        WCHAR wbuffer[sizeof(buffer)];
        int wcount = MultiByteToWideChar(CP_UTF8, 0, buffer, -1, wbuffer, sizeof(buffer));

        DWORD written;
        WriteConsoleW(GetStdHandle(STD_OUTPUT_HANDLE), wbuffer, wcount - 1, &written, NULL);
        return;
    }
    fputs(buffer, stdout);
}

void sys_error(const char* msg, ...)
{
    char buffer[1024];

    va_list arg;
    va_start(arg, msg);
    vsnprintf(buffer, sizeof(buffer), msg, arg);
    va_end(arg);

    DWORD mode;
    if (GetConsoleMode(GetStdHandle(STD_ERROR_HANDLE), &mode))
    {
        WCHAR wbuffer[sizeof(buffer)];
        int wcount = MultiByteToWideChar(CP_UTF8, 0, buffer, -1, wbuffer, sizeof(buffer));

        DWORD written;
        WriteConsoleW(GetStdHandle(STD_ERROR_HANDLE), wbuffer, wcount - 1, &written, NULL);
    }
    else
    {
        fputs(buffer, stderr);
    }

    SetConsoleOutputCP(gOldCP);
    exit(EXIT_FAILURE);
}

static void sys_mkdir_real(const char* path)
{
    WCHAR wpath[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

    if (CreateDirectoryW(wpath, NULL) == 0)
    {
        if (GetLastError() != ERROR_ALREADY_EXISTS)
        {
            sys_error("ERROR: cannot create '%s' folder\n", path);
        }
    }
}

sys_file sys_open(const char* fname, uint64_t* size)
{
    WCHAR path[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, fname, -1, path, MAX_PATH);

    HANDLE handle = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE)
    {
        sys_error("ERROR: cannot open '%s' file\n", fname);
    }

    LARGE_INTEGER sz;
    if (!GetFileSizeEx(handle, &sz))
    {
        sys_error("ERROR: cannot get size of '%s' file\n", fname);
    }
    *size = sz.QuadPart;

    return handle;
}

sys_file sys_create(const char* fname)
{
    sys_validate_output_path(fname);
    WCHAR path[MAX_PATH];
    MultiByteToWideChar(CP_UTF8, 0, fname, -1, path, MAX_PATH);

    HANDLE handle = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE)
    {
        sys_error("ERROR: cannot create '%s' file\n", fname);
    }

    return handle;
}

void sys_close(sys_file file)
{
    if (!CloseHandle(file))
    {
        sys_error("ERROR: failed to close file\n");
    }
}

void sys_read(sys_file file, uint64_t offset, void* buffer, uint32_t size)
{
    DWORD read;
    OVERLAPPED ov;
    ov.hEvent = NULL;
    ov.Offset = (uint32_t)offset;
    ov.OffsetHigh = (uint32_t)(offset >> 32);
    if (!ReadFile(file, buffer, size, &read, &ov) || read != size)
    {
        sys_error("ERROR: failed to read %u bytes from file\n", size);
    }
}

void sys_write(sys_file file, uint64_t offset, const void* buffer, uint32_t size)
{
    DWORD written;
    OVERLAPPED ov;
    ov.hEvent = NULL;
    ov.Offset = (uint32_t)offset;
    ov.OffsetHigh = (uint32_t)(offset >> 32);
    if (!WriteFile(file, buffer, size, &written, &ov) || written != size)
    {
        sys_error("ERROR: failed to write %u bytes to file\n", size);
    }
}

#else

#define _FILE_OFFSET_BITS 64
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>

static int sys_open_directory_path(const char* path, int create)
{
    sys_validate_output_path(path);
    char* copy = strdup(path);
    if (copy == NULL)
    {
        sys_error("ERROR: out of memory while opening output directory\n");
    }

    int directory = open(".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory < 0)
    {
        free(copy);
        sys_error("ERROR: cannot open extraction root\n");
    }

    char* save = NULL;
    for (char* component = strtok_r(copy, "/", &save);
         component != NULL;
         component = strtok_r(NULL, "/", &save))
    {
        if (create && mkdirat(directory, component, S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) < 0 && errno != EEXIST)
        {
            close(directory);
            free(copy);
            sys_error("ERROR: cannot create output folder '%s'\n", path);
        }

        int next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0)
        {
            close(directory);
            free(copy);
            sys_error("ERROR: unsafe or inaccessible output folder in '%s'\n", path);
        }
        close(directory);
        directory = next;
    }

    free(copy);
    return directory;
}

static int sys_create_relative_file(const char* path)
{
    sys_validate_output_path(path);
    char* copy = strdup(path);
    if (copy == NULL)
    {
        sys_error("ERROR: out of memory while creating output file\n");
    }

    char* basename = strrchr(copy, '/');
    int parent;
    if (basename == NULL)
    {
        basename = copy;
        parent = open(".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    }
    else
    {
        *basename++ = '\0';
        parent = sys_open_directory_path(copy, 0);
    }
    if (parent < 0)
    {
        free(copy);
        sys_error("ERROR: cannot open parent folder for '%s'\n", path);
    }

    int file = openat(parent, basename,
                      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                      S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH);
    close(parent);
    free(copy);
    if (file < 0)
    {
        sys_error("ERROR: cannot safely create '%s'\n", path);
    }
    return file;
}

static int gStdoutRedirected;

void sys_output_init(void)
{
    gStdoutRedirected = !isatty(STDOUT_FILENO);
}

void sys_output_done(void)
{
}

void sys_output(const char* msg, ...)
{
    va_list arg;
    va_start(arg, msg);
    vfprintf(stdout, msg, arg);
    va_end(arg);
}

void sys_error(const char* msg, ...)
{
    va_list arg;
    va_start(arg, msg);
    vfprintf(stderr, msg, arg);
    va_end(arg);

    exit(EXIT_FAILURE);
}

sys_file sys_open(const char* fname, uint64_t* size)
{
    int fd = open(fname, O_RDONLY);
    if (fd < 0)
    {
        sys_error("ERROR: cannot open '%s' file\n", fname);
    }

    struct stat st;
    if (fstat(fd, &st) != 0)
    {
        sys_error("ERROR: cannot get size of '%s' file\n", fname);
    }
    *size = st.st_size;

    return (void*)(intptr_t)fd;
}

sys_file sys_create(const char* fname)
{
    return (void*)(intptr_t)sys_create_relative_file(fname);
}

void sys_close(sys_file file)
{
    if (close((int)(intptr_t)file) != 0)
    {
        sys_error("ERROR: failed to close file\n");
    }
}

void sys_read(sys_file file, uint64_t offset, void* buffer, uint32_t size)
{
    ssize_t read = pread((int)(intptr_t)file, buffer, size, offset);
    if (read < 0 || read != (ssize_t)size)
    {
        sys_error("ERROR: failed to read %u bytes from file\n", size);
    }
}

void sys_write(sys_file file, uint64_t offset, const void* buffer, uint32_t size)
{
    ssize_t wrote = pwrite((int)(intptr_t)file, buffer, size, offset);
    if (wrote < 0 || wrote != (ssize_t)size)
    {
        sys_error("ERROR: failed to read %u bytes from file\n", size);
    }
}

#endif

void sys_validate_output_path(const char* path)
{
    if (path == NULL || path[0] == '\0' || path[0] == '/' || path[0] == '\\')
    {
        sys_error("ERROR: refusing absolute or empty output path\n");
    }

    const char* component = path;
    for (const char* cursor = path; ; cursor++)
    {
        unsigned char value = (unsigned char)*cursor;
        if (value == '\\' || value == ':' || (value < 32 && value != '\0'))
        {
            sys_error("ERROR: refusing unsafe output path '%s'\n", path);
        }

        if (value == '/' || value == '\0')
        {
            size_t length = (size_t)(cursor - component);
            if (length == 0 || (length == 1 && component[0] == '.') ||
                (length == 2 && component[0] == '.' && component[1] == '.'))
            {
                sys_error("ERROR: refusing traversal output path '%s'\n", path);
            }
            if (value == '\0')
            {
                break;
            }
            component = cursor + 1;
        }
    }
}

void sys_mkdir(const char* path)
{
#if defined(_WIN32)
    sys_validate_output_path(path);
    char* copy = strdup(path);
    if (copy == NULL) { sys_error("ERROR: out of memory while creating output folder\n"); }
    char* last = strrchr(copy, '/');
    if (last != NULL)
    {
        *last = '\0';
        sys_mkdir(copy);
        *last = '/';
    }
    sys_mkdir_real(copy);
    free(copy);
#else
    int directory = sys_open_directory_path(path, 1);
    close(directory);
#endif
}

void* sys_realloc(void* ptr, size_t size)
{
    void* result = NULL;
    if (!ptr && size)
    {
        result = malloc(size);
    }
    else if (ptr && !size)
    {
        free(ptr);
        return NULL;
    }
    else if (ptr && size)
    {
        result = realloc(ptr, size);
    }
    else
    {
        sys_error("ERROR: internal error, wrong sys_realloc usage\n");
    }

    if (!result)
    {
        sys_error("ERROR: out of memory\n");
    }

    return result;
}

void sys_vstrncat(char* dst, size_t n, const char* format, ...)
{
    char temp[1024];

    va_list args;
    va_start(args, format);
    vsnprintf(temp, sizeof(temp), format, args);
    va_end(args);

    strncat(dst, temp, n - strlen(dst) - 1);
}

static uint64_t out_size;
static uint32_t out_next;

void sys_output_progress_init(uint64_t size)
{
    out_size = size;
    out_next = 0;
}

void sys_output_progress(uint64_t progress)
{
    if (gStdoutRedirected)
    {
        return;
    }

    uint32_t now = (uint32_t)(progress * 100 / out_size);
    if (now >= out_next)
    {
        sys_output("[*] unpacking... %u%%\r", now);
        out_next = now + 1;
    }
}
