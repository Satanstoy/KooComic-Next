/* SPDX-License-Identifier: AGPL-3.0-only
 * Bounded host prototype; run inside one isolated worker, never a UI callback.
 */
#include <limits.h>
#include <stdint.h>
#include "vendor/moire_filter_kissfft.c"

EXPORT int koocomic_filter(unsigned char *data, int width, int height, int stride,
                          int is_colored, float strength, size_t memory_budget, size_t data_size)
{
    if (!data || width <= 0 || height <= 0 || width % 2 || height % 2 ||
        !isfinite(strength) || strength < 0.0f || strength > 1.0f ||
        (is_colored != 0 && is_colored != 1)) return -1;
    uint64_t pixels = (uint64_t)width * (uint64_t)height;
    if (pixels > INT_MAX || width > INT_MAX / 4 ||
        (stride != width && stride != width * 4) || (is_colored && stride != width * 4) ||
        (uint64_t)stride * (uint64_t)height > INT_MAX ||
        (uint64_t)stride * (uint64_t)height > data_size) return -1;
    /* Includes two complex work buffers, two FFT configs, chroma and caller data.
       An isolated worker still needs an OS memory limit; this is admission only. */
    if (pixels * 64u + 65536u > memory_budget) return -2;
    if (strength == 0.0f) return 0;
    if (init_resources(width, height) != 0) return -3;
    remove_moire(data, width, height, stride, is_colored != 0, strength);
    cleanup_resources();
    return 0;
}
