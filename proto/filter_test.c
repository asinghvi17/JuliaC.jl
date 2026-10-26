#include "program.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    uint64_t a=0, b=0, c=0, d=0, e=0, old;
    double out=-99;
    int32_t integer=-99;
    assert(filter_create(NULL) == filter_NULL);
    assert(filter_value(0, &out) == filter_INVALID && out == -99);
    assert(filter_step(UINT64_MAX, 1.0, &out) == filter_INVALID);
    assert(filter_destroy(UINT64_C(0x100000005)) == filter_INVALID);
    assert(filter_destroy(UINT64_C(1)) == filter_INVALID); /* generation zero */
    assert(filter_create(&a) == filter_OK && a != 0);
    assert(filter_create(&b) == filter_OK && b != a);
    assert(filter_step(a, 2.0, &out) == filter_OK && out == 2.0);
    assert(filter_step(a, 4.0, &out) == filter_OK && fabs(out-5.0) < 1e-12);
    assert(filter_step(b, 7.0, &out) == filter_OK && out == 7.0);
    assert(filter_value(a, &out) == filter_OK && fabs(out-5.0) < 1e-12);
    assert(filter_value(b, NULL) == filter_NULL);
    assert(filter_checked(a, -1, &integer) == filter_EXCEPTION && integer == -99);
    assert(filter_checked(a, 42, &integer) == filter_OK && integer == 42);
    assert(filter_create(&c) == filter_OK);
    assert(filter_create(&d) == filter_OK);
    e=123;
    assert(filter_create(&e) == filter_EXHAUSTED && e == 123);
    old=a;
    assert(filter_destroy(a) == filter_OK);
    assert(filter_destroy(old) == filter_INVALID);
    assert(filter_value(old, &out) == filter_INVALID);
    assert(filter_create(&a) == filter_OK && a != old);
    assert((uint32_t)a == (uint32_t)old && (a >> 32) == (old >> 32)+1);
    assert(filter_value(a, &out) == filter_OK && out == 0.0);
    assert(filter_step(old, 1.0, &out) == filter_INVALID);
    assert(filter_clear(b) == filter_OK);
    assert(filter_value(b, &out) == filter_OK && out == 0.0);
    assert(filter_destroy(a) == filter_OK);
    assert(filter_destroy(b) == filter_OK);
    assert(filter_destroy(c) == filter_OK);
    assert(filter_destroy(d) == filter_OK);
    for (int i=0; i<1000; ++i) {
        assert(filter_create(&a) == filter_OK);
        assert(filter_value(a, &out) == filter_OK && out == 0.0);
        assert(filter_destroy(a) == filter_OK);
        assert(filter_value(a, &out) == filter_INVALID);
    }
    puts("PASS: independent states, stale/invalid handles, exhaustion, reset, null, exception, void, 1000 reuses");
    return 0;
}
