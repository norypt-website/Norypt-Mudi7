#include "imei.h"
#include <string.h>
/* Show only the last KEEP_TAIL digits ("............572"): enough to see at a
 * glance that old and new differ, while a photo of the panel never reveals
 * the old IMEI (TAC + serial). Inputs of KEEP_TAIL digits or fewer are fully
 * masked, so a short or garbled read can never leak verbatim. */
#define KEEP_TAIL 3
void imei_mask(const char *imei, char *out, size_t outsz) {
    size_t len = strlen(imei), n = len;
    if (outsz == 0) return;
    if (n + 1 > outsz) n = outsz - 1;            /* truncate, still masked */
    const char *tail = imei + (len - n);         /* keep the real last digits */
    for (size_t i = 0; i < n; i++)
        out[i] = (n > KEEP_TAIL && i >= n - KEEP_TAIL) ? tail[i] : '.';
    out[n] = '\0';
}
