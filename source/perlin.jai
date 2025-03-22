
// This code was all stolen and converted into Jai!


SEED : s32 = 0;

HASH := u8.[208,34,231,213,32,248,233,56,161,78,24,140,71,48,140,254,245,255,247,247,40,
                     185,248,251,245,28,124,204,204,76,36,1,107,28,234,163,202,224,245,128,167,204,
                     9,92,217,54,239,174,173,102,193,189,190,121,100,108,167,44,43,77,180,204,8,81,
                     70,223,11,38,24,254,210,210,177,32,81,195,243,125,8,169,112,32,97,53,195,13,
                     203,9,47,104,125,117,114,124,165,203,181,235,193,206,70,180,174,0,167,181,41,
                     164,30,116,127,198,245,146,87,224,149,206,57,4,192,210,65,210,129,240,178,105,
                     228,108,245,148,140,40,35,195,38,58,65,207,215,253,65,85,208,76,62,3,237,55,89,
                     232,50,217,64,244,157,199,121,252,90,17,212,203,149,152,140,187,234,177,73,174,
                     193,100,192,143,97,53,145,135,19,103,13,90,135,151,199,91,239,247,33,39,145,
                     101,120,99,3,186,86,99,41,237,203,111,79,220,135,158,42,30,154,120,67,87,167,
                     135,176,183,191,253,115,184,21,233,58,129,233,142,39,128,211,118,137,139,255,
                     114,20,218,113,154,27,127,246,250,1,8,198,250,209,92,222,173,21,88,102,219];

noise2 :: (x: s32, y: s32) -> s32 {
    yindex := (y + SEED) % 256;
    if (yindex < 0)
        yindex += 256;
    xindex := (HASH[yindex] + x) % 256;
    if (xindex < 0)
        xindex += 256;
    result := HASH[xindex];
    return result;
}

lin_inter :: (x: float64, y: float64, s: float64) -> float64
{
    return x + s * (y-x);
}

smooth_inter :: (x: float64, y: float64, s: float64) -> float64
{
    return lin_inter(x, y, s * s * (3-2*s));
}

noise2d :: (x: float64, y: float64) -> float64
{
    x_int := cast(int)floor( x );
    y_int := cast(int)floor( y );
    x_frac : float64 = x - x_int;
    y_frac : float64 = y - y_int;
    s := noise2( xx x_int, xx y_int );
    t := noise2( xx (x_int+1), xx y_int );
    u := noise2( xx x_int, xx (y_int+1) );
    v := noise2( xx (x_int+1), xx (y_int+1) );
    low := smooth_inter( xx s, xx t, xx x_frac );
    high := smooth_inter( xx u, xx v, xx x_frac );
    result := smooth_inter( xx low, xx high, xx y_frac );
    return result;
}

perlin2d :: (x: float64, y: float64, freq: float64, depth: s32) -> float64
{
    xa : float64 = x*freq;
    ya : float64 = y*freq;
    amp : float64 = 1.0;
    fin : float64 = 0.0;
    div : float64 = 0.0;

    for 0..depth-1 {
        div += 256 * amp;
        fin += noise2d(xa, ya) * amp;
        amp /= 2;
        xa *= 2;
        ya *= 2;
    }

    return fin/div;
}
