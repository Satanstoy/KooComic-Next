#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*filter_fn)(unsigned char *, int, int, int, int, float, size_t, size_t);
#ifdef STATIC_FILTER
extern int koocomic_filter(unsigned char *, int, int, int, int, float, size_t, size_t);
#endif

int main(int argc, char **argv)
{
#ifdef STATIC_FILTER
    (void)argc; (void)argv;
    filter_fn filter = koocomic_filter;
#else
    assert(argc == 2);
    void *library = dlopen(argv[1], RTLD_NOW);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    filter_fn filter = (filter_fn)dlsym(library, "koocomic_filter");
#endif
    assert(filter);
    unsigned char data[64 * 64 * 4];
    for (size_t i = 0; i < sizeof(data); i += 4) {
        data[i] = 120; data[i + 1] = 95; data[i + 2] = 65; data[i + 3] = 231;
    }
    assert(filter(data, 64, 64, 256, 1, .8f, 1024 * 1024, sizeof(data)) == 0);
    for (size_t i = 0; i < sizeof(data); i += 4) {
        assert(abs(data[i] - 120) <= 2 && abs(data[i + 1] - 95) <= 2 && abs(data[i + 2] - 65) <= 2);
        assert(data[i + 3] == 231);
    }
    unsigned char before[sizeof(data)];
    memcpy(before, data, sizeof(data));
    assert(filter(data, 64, 64, 256, 1, .8f, 1024 * 1024, sizeof(data) - 1) != 0);
    assert(memcmp(before, data, sizeof(data)) == 0);
#ifndef STATIC_FILTER
    dlclose(library);
#endif
    puts("native ABI smoke: OK");
    return 0;
}
