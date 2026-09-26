#include "pkg2zip_out.h"
#include "pkg2zip_sys.h"
#include "pkg2zip_zip.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static zip out_zip;
static int out_zipped;
static sys_file out_file;
static uint64_t out_file_offset;

// Names already written to the zip. Folders are stored with a trailing '/'.
// A folder added twice is written once; a file added twice is an error, as it
// is for unzipped output, which never overwrites an existing file.
static char** out_zip_names;
static size_t out_zip_name_capacity;
static size_t out_zip_name_count;

static size_t out_name_hash(const char* name)
{
    size_t hash = 14695981039346656037ULL & (size_t)-1;
    for (; *name; name++)
    {
        hash = (hash ^ (unsigned char)*name) * (size_t)1099511628211ULL;
    }
    return hash;
}

static char** out_name_slot(char** table, size_t capacity, const char* name)
{
    size_t index = out_name_hash(name) & (capacity - 1);
    while (table[index] != NULL && strcmp(table[index], name) != 0)
    {
        index = (index + 1) & (capacity - 1);
    }
    return table + index;
}

// Records `name` and returns 1, or returns 0 when it was already recorded.
static int out_zip_record_name(const char* name)
{
    if (2 * (out_zip_name_count + 1) > out_zip_name_capacity)
    {
        size_t capacity = out_zip_name_capacity ? 2 * out_zip_name_capacity : 256;
        char** table = sys_realloc(NULL, capacity * sizeof(char*));
        memset(table, 0, capacity * sizeof(char*));
        for (size_t i = 0; i < out_zip_name_capacity; i++)
        {
            if (out_zip_names[i] != NULL)
            {
                *out_name_slot(table, capacity, out_zip_names[i]) = out_zip_names[i];
            }
        }
        if (out_zip_names != NULL)
        {
            sys_realloc(out_zip_names, 0);
        }
        out_zip_names = table;
        out_zip_name_capacity = capacity;
    }

    char** slot = out_name_slot(out_zip_names, out_zip_name_capacity, name);
    if (*slot != NULL)
    {
        return 0;
    }
    size_t length = strlen(name) + 1;
    *slot = sys_realloc(NULL, length);
    memcpy(*slot, name, length);
    out_zip_name_count++;
    return 1;
}

static void out_zip_add_folder(const char* path)
{
    char name[ZIP_MAX_FILENAME + 1];
    if (snprintf(name, sizeof(name), "%s/", path) >= (int)sizeof(name))
    {
        sys_error("ERROR: dirname too long\n");
    }
    if (out_zip_record_name(name))
    {
        zip_add_folder(&out_zip, path);
    }
}

void out_begin(const char* name, int zipped)
{
    if (zipped)
    {
        zip_create(&out_zip, name);
    }
    out_zipped = zipped;
}

void out_end(void)
{
    if (out_zipped)
    {
        zip_close(&out_zip);
    }
}

void out_add_folder(const char* path)
{
    sys_validate_output_path(path);
    if (out_zipped)
    {
        out_zip_add_folder(path);
    }
    else
    {
        sys_mkdir(path);
    }
}

void out_add_parent(const char* path)
{
    sys_validate_output_path(path);
    char parent[1024];
    const char* lastslash = strrchr(path, '/');
    if (lastslash != NULL)
    {
        size_t length = (size_t)(lastslash - path);
        if (length >= sizeof(parent))
        {
            sys_error("ERROR: output path is too long\n");
        }
        snprintf(parent, sizeof(parent), "%.*s", (int)length, path);
        if (out_zipped)
        {
            out_zip_add_folder(parent);
        }
        else
        {
            sys_mkdir(parent);
        }
    }
}

uint64_t out_begin_file(const char* name, int compress)
{
    sys_validate_output_path(name);
    if (out_zipped)
    {
        if (!out_zip_record_name(name))
        {
            sys_error("ERROR: refusing to write '%s' twice\n", name);
        }
        return zip_begin_file(&out_zip, name, compress);
    }
    else
    {
        out_file = sys_create(name);
        out_file_offset = 0;
        return 0;
    }
}

void out_end_file(void)
{
    if (out_zipped)
    {
        zip_end_file(&out_zip);
    }
    else
    {
        sys_close(out_file);
    }
}

void out_write(const void* buffer, uint32_t size)
{
    if (out_zipped)
    {
        zip_write_file(&out_zip, buffer, size);
    }
    else
    {
        sys_write(out_file, out_file_offset, buffer, size);
        out_file_offset += size;
    }
}

void out_write_at(uint64_t offset, const void* buffer, uint32_t size)
{
    if (out_zipped)
    {
        zip_write_file_at(&out_zip, offset, buffer, size);
    }
    else
    {
        sys_write(out_file, offset, buffer, size);
    }
}

void out_set_offset(uint64_t offset)
{
    if (out_zipped)
    {
        zip_set_offset(&out_zip, offset);
    }
    else
    {
        out_file_offset = offset;

    }
}

uint32_t out_zip_get_crc32(void)
{
    if (out_zipped)
    {
        return zip_get_crc32(&out_zip);
    }
    return 0;
}

void out_zip_set_crc32(uint32_t crc)
{
    if (out_zipped)
    {
        zip_set_crc32(&out_zip, crc);
    }
}
