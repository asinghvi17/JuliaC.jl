#include "program.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    uint64_t a=0, b=0;
    double x=0, t=0;
    assert(lorenz_create(&a) == lorenz_OK);
    assert(lorenz_create(&b) == lorenz_OK);
    assert(lorenz_advance(a, &x) == lorenz_OK);
    /* Reference from a normal Julia solve of exactly this fixed-step problem. */
    assert(isfinite(x) && fabs(x-(-9.408450567062301)) < 1e-8);
    assert(lorenz_time(a, &t) == lorenz_OK && fabs(t-1.0) < 1e-12);
    assert(lorenz_value(b, &x) == lorenz_OK && x == 1.0);
    assert(lorenz_destroy(a) == lorenz_OK);
    assert(lorenz_create(&a) == lorenz_OK);
    assert(lorenz_time(a, &t) == lorenz_OK && t == 0.0);
    assert(lorenz_value(a, &x) == lorenz_OK && x == 1.0);
    assert(lorenz_destroy(a) == lorenz_OK && lorenz_destroy(b) == lorenz_OK);
    puts("PASS: baked SciML integrators, independent state, solve!, reset");
    return 0;
}
