#include <math.h>
// -1 preserves the application's choice for translucent backgrounds.
static inline int CPStatusInk(double r, double g, double b, double alpha) {
    if (!isfinite(r) || !isfinite(g) || !isfinite(b) || !isfinite(alpha) || alpha < 0.95) return -1;
    double values[3]={r,g,b};
    for (int i=0;i<3;++i) values[i]=values[i]<=0.04045 ? values[i]/12.92 : pow((values[i]+0.055)/1.055,2.4);
    double luminance=0.2126*values[0]+0.7152*values[1]+0.0722*values[2];
    return luminance>0.179 ? 0 : 1; // dark ink / light ink
}
