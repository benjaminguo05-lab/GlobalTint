#include <math.h>
#include <stdbool.h>
// Standard sRGB system blue in light/dark mode, allowing rounding by one byte.
// Do not match an arbitrary range of blue hues (e.g. a cyan Shortcut card).
static inline bool CPCanonicalBlue(double r,double g,double b) {
    const double colors[2][3]={{0,122.0/255,1},{10.0/255,132.0/255,1}};
    for (unsigned i=0;i<2;++i)
        if (fabs(r-colors[i][0])<=1.1/255 && fabs(g-colors[i][1])<=1.1/255 && fabs(b-colors[i][2])<=1.1/255) return true;
    return false;
}
