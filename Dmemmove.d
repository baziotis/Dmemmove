/*
Boost Software License - VeRSIon 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:
The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHalL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEalINGS IN THE SOFTWARE.
*/

import core.stdc.string: memmove;
import S_struct;

void Cmemmove(T)(T *dst, const T *src)
{
    pragma(inline, true)
    memmove(dst, src, T.sizeof);
}

// IMPORTANT(stefanos): memmove is supposed to return the dest
void Dmemmove(T)(T *dst, const T *src)
{
    import core.stdc.stdio: printf;
    import core.simd: void16, void32, loadUnaligned, storeUnaligned;
    void *d = dst;
    const(void) *s = src;
    size_t n = T.sizeof;

    if (n < 64) {
        if (n & 32) {
            n -= 32;
            storeUnaligned(cast(void16*)(d+n+16), loadUnaligned(cast(const void16*)(s+n+16)));
            storeUnaligned(cast(void16*)(d+n), loadUnaligned(cast(const void16*)(s+n)));
        }
        if (n & 16) {
            n -= 16;
            storeUnaligned(cast(void16*)(d+n), loadUnaligned(cast(const void16*)(s+n)));
        }
        if (n & 8) {
            n -= 8;
            *(cast(ulong*)(d+n)) = *(cast(const ulong*)(s+n));
        }
        if (n & 4) {
            n -= 4;
            *(cast(uint*)(d+n)) = *(cast(const uint*)(s+n));
        }
        if (n & 2) {
            n -= 2;
            *(cast(ushort*)(d+n)) = *(cast(const ushort*)(s+n));
        }
        if (n & 1) {
            *(cast(ubyte*)d) = *(cast(const ubyte*)s);
        }
        return;
    }
    if (n < 128) {
        asm pure nothrow @nogc {
            naked;
            mov RSI, s;
            mov RDI, d;
            mov RDX, T.sizeof;
            add RSI, RDX;
            add RDI, RDX;
            vmovdqu YMM1, [RSI-0x20];
            vmovdqu YMM2, [RSI-0x40];

            vmovdqu [RDI-0x20], YMM1;
            vmovdqu [RDI-0x40], YMM2;
            
            sub RDX, 64;
            sub RSI, RDX;
            sub RDI, RDX;


            vmovdqu YMM1, [RSI-0x20];
            vmovdqu YMM2, [RSI-0x40];

            vmovdqu [RDI-0x20], YMM1;
            vmovdqu [RDI-0x40], YMM2;
            ret;
        }
        /*
        storeUnaligned(cast(void16*)(d-0x10), loadUnaligned(cast(const void16*)(s-0x10)));
        storeUnaligned(cast(void16*)(d-0x20), loadUnaligned(cast(const void16*)(s-0x20)));
        storeUnaligned(cast(void16*)(d-0x30), loadUnaligned(cast(const void16*)(s-0x30)));
        storeUnaligned(cast(void16*)(d-0x40), loadUnaligned(cast(const void16*)(s-0x40)));
        n -= 64;
        s = s - n;
        d = d - n;
        storeUnaligned(cast(void16*)(d-0x10), loadUnaligned(cast(const void16*)(s-0x10)));
        storeUnaligned(cast(void16*)(d-0x20), loadUnaligned(cast(const void16*)(s-0x20)));
        storeUnaligned(cast(void16*)(d-0x30), loadUnaligned(cast(const void16*)(s-0x30)));
        storeUnaligned(cast(void16*)(d-0x40), loadUnaligned(cast(const void16*)(s-0x40)));
        return;
        */
    }
    s += n;
    d += n;
    uint mod = cast(ulong)d & 31;
    if (mod) {
        storeUnaligned(cast(void16*)(d-0x10), loadUnaligned(cast(const void16*)(s-0x10)));
        storeUnaligned(cast(void16*)(d-0x20), loadUnaligned(cast(const void16*)(s-0x20)));
        s -= mod;
        d -= mod;
        n -= mod;
    }
    while (n >= 128) {
        *(cast(void32*)(d-0x20)) = *(cast(const void32*)(s-0x20));
        *(cast(void32*)(d-0x40)) = *(cast(const void32*)(s-0x40));
        *(cast(void32*)(d-0x60)) = *(cast(const void32*)(s-0x60));
        *(cast(void32*)(d-0x80)) = *(cast(const void32*)(s-0x80));
        s -= 128;
        d -= 128;
        n -= 128;
    }

    if (n) {
        *(cast(void32*)(d-0x20)) = *(cast(const void32*)(s-0x20));
        *(cast(void32*)(d-0x40)) = *(cast(const void32*)(s-0x40));
        n = -n + 0x40;
        s += n;
        d += n;
        storeUnaligned(cast(void16*)(d-16), loadUnaligned(cast(const void16*)(s-16)));
        storeUnaligned(cast(void16*)(d-32), loadUnaligned(cast(const void16*)(s-32)));
        storeUnaligned(cast(void16*)(d-48), loadUnaligned(cast(const void16*)(s-48)));
        storeUnaligned(cast(void16*)(d-64), loadUnaligned(cast(const void16*)(s-64)));
    }
}
