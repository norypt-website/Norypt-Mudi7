// LINK: src/imei.c
#include <assert.h>
#include <string.h>
#include "../../src/imei.h"

int main(void) {
    char out[64];
    imei_mask("358835966999572", out, sizeof out);       /* 15 digits */
    assert(strcmp(out, "............572") == 0);          /* only the last 3 shown */
    imei_mask("12345", out, sizeof out);                  /* short read: still masked */
    assert(strcmp(out, "..345") == 0);
    imei_mask("123", out, sizeof out);                    /* <= 3 digits: fully masked */
    assert(strcmp(out, "...") == 0);
    imei_mask("", out, sizeof out);
    assert(strcmp(out, "") == 0);
    char small[6];
    imei_mask("358835966999572", small, sizeof small);   /* truncated output never leaks the head */
    assert(strcmp(small, "..572") == 0);                  /* truncated: still the real tail */
    return 0;
}
