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

import S_struct;
import std.traits;

bool isPowerOf2(T)(T x)
if (isIntegral!T)
{
    return (x != 0) && ((x & (x - 1)) == 0);
}

void Dmemcpy(T)(T *dst, const T *src)
if (isScalarType!T)
{
    pragma(inline, true)
        *dst = *src;
}

// This implementation handles type sizes that are not powers of 2
// This implementation can't be @safe because it does pointer arithmetic
void DmemcpyUnsafe(T)(T *dst, const T *src) @trusted
if (is(T == struct))
{
    import core.bitop: bsr;

    static assert(T.sizeof != 0);
    enum prevPowerOf2 = 1LU << bsr(T.sizeof);
    alias TRemainder = S!(T.sizeof - prevPowerOf2);
    auto s = cast(const S!prevPowerOf2*)(src);
    auto d = cast(S!prevPowerOf2*)(dst);
    static if (T.sizeof < 31)
    {
        pragma(inline, true);
        Dmemcpy(d, s);
        Dmemcpy(cast(TRemainder*)(d + 1), cast(const TRemainder*)(s + 1));
    }
    else
    {
        Dmemcpy(d, s);
        Dmemcpy(cast(TRemainder*)(d + 1), cast(const TRemainder*)(s + 1));
    }
}

// NOTE(stefanos): This function requires _no_ overlap.
extern(C) void Dmemcpy_small(void *d, const(void) *s, size_t n)
{
    if (n < 16) {
        if (n & 0x01)
        {
            *cast(ubyte *)d = *cast(const ubyte *)s;
            ++d;
            ++s;
        }
        if (n & 0x02)
        {
            *cast(ushort *)d = *cast(const ushort *)s;
            d += 2;
            s += 2;
        }
        if (n & 0x04)
        {
            *cast(uint *)d = *cast(const uint *)s;
            d += 4;
            s += 4;
        }
        if (n & 0x08)
        {
            *cast(ulong *)d = *cast(const ulong *)s;
        }
        return;
    }
    if (n <= 32)
    {
        import core.simd: void16, storeUnaligned, loadUnaligned;
        void16 xmm0 = loadUnaligned(cast(const void16*)(s));
        void16 xmm1 = loadUnaligned(cast(const void16*)(s-16+n));
        storeUnaligned(cast(void16*)(d), xmm0);
        storeUnaligned(cast(void16*)(d-16+n), xmm1);
        return;
    }
    // NOTE(stefanos): I'm writing using load/storeUnaligned() but you possibly can
    // achieve greater performance using naked ASM. Be careful that you should either use
    // only D or only naked ASM.
    if (n <= 64)
    {
        import core.simd: void16, storeUnaligned, loadUnaligned;
        void16 xmm0 = loadUnaligned(cast(const void16*)(s));
        void16 xmm1 = loadUnaligned(cast(const void16*)(s+16));
        void16 xmm2 = loadUnaligned(cast(const void16*)(s-32+n));
        void16 xmm3 = loadUnaligned(cast(const void16*)(s-32+n+16));
        storeUnaligned(cast(void16*)(d), xmm0);
        storeUnaligned(cast(void16*)(d+16), xmm1);
        storeUnaligned(cast(void16*)(d-32+n), xmm2);
        storeUnaligned(cast(void16*)(d-32+n+16), xmm3);
        return;
    }
    import core.simd: void16, storeUnaligned, loadUnaligned;
    storeUnaligned(cast(void16*)(d), loadUnaligned(cast(const void16*)(s)));
    storeUnaligned(cast(void16*)(d+16), loadUnaligned(cast(const void16*)(s+16)));
    storeUnaligned(cast(void16*)(d+32), loadUnaligned(cast(const void16*)(s+32)));
    storeUnaligned(cast(void16*)(d+48), loadUnaligned(cast(const void16*)(s+48)));
    // NOTE(stefanos): Requires _no_ overlap.
    n -= 64;
    s = s + n;
    d = d + n;
    storeUnaligned(cast(void16*)(d), loadUnaligned(cast(const void16*)(s)));
    storeUnaligned(cast(void16*)(d+16), loadUnaligned(cast(const void16*)(s+16)));
    storeUnaligned(cast(void16*)(d+32), loadUnaligned(cast(const void16*)(s+32)));
    storeUnaligned(cast(void16*)(d+48), loadUnaligned(cast(const void16*)(s+48)));
}

// NOTE(stefanos): This function requires _no_ overlap.
extern(C) void Dmemcpy_large(void *d, const(void) *s, size_t n) {
    // NOTE(stefanos): Alternative - Reach 64-byte
    // (cache-line) alignment and use rep movsb
    // Good for bigger sizes and only for Intel.
    /*
    pragma(inline, false)
    asm pure nothrow @nogc
    {
        mov     RCX, T.sizeof;
        mov     EDX, ESI;                       // save `src`
        and     EDX, 0x3f;                      // mod = src % 64
        je      L5;
        vmovdqu  YMM0, [RSI];
        vmovdqu  YMM1, [RSI+0x20];
        vmovdqu  [RDI], YMM0;
        vmovdqu  [RDI+0x20], YMM1;
        mov    RAX, 0x40;
        sub    RAX, RDX;
        //cdqe   ;
        // src += %t0
        add    RSI, RAX;
        // dst += %t0
        add    RDI, RAX;
        // n -= %t0
        sub    RCX, RAX;
        L5:
        cld;
        rep;
        movsb;
    }
    return;
    */

    // IMPORTANT(stefanos): For anything regarding the Windows calling convention,
    // refer here: https://en.wikipedia.org/wiki/X86_calling_conventions#Microsoft_x64_calling_convention
    // and be sure to follow the links in the Microsoft pages for further info.
    // For anything regarding the calling convention used for POSIX, that is the AMD64 ABI:
    // https://software.intel.com/sites/default/files/article/402129/mpx-linux64-abi.pdf
    version (Windows)
    {
        asm pure nothrow @nogc
        {
            naked;
            // Preserve registers that are used in this ASM. RDI, RSI are non-volatile in Windows.
            push RDI;
            push RSI;
            // Move to Posix registers.
            mov RDI, RCX;
            mov RSI, RDX;
            mov RDX, R8;
        }
    }

    asm pure nothrow @nogc
    {
        naked;
        // Saved addresses for later use in the last 128 bytes.
        lea		R9, [RSI+RDX-128];
        lea		R11, [RDI+RDX-128];
        mov     ECX, EDI;                       // save `src`
        and     ECX, 0x1f;                      // mod = src % 32
        je      L4;
        // if (mod) -> copy enough bytes to reach 32-byte alignment on writes (destination)
        // NOTE(stefanos): No overlap is required.
        vmovdqu YMM0, [RSI];
        vmovdqu [RDI], YMM0;
        // %t0 = 32 - mod
        mov     RAX, 0x20;
        sub     RAX, RCX;
        //cdqe   ;
        // src += %t0
        add     RSI, RAX;
        // dst += %t0
        add     RDI, RAX;
        // n -= %t0
        sub     RDX, RAX;
        // NOTE(stefanos): There is a possibility to go below 128
        // with reaching alignment.
        cmp     RDX, 128;
        jb      L2;
        align 16;
    L4:
        // Because of the above, (at least) the loads
        // are 32-byte aligned.
        vmovdqu YMM0, [RSI];
        vmovdqu YMM1, [RSI+0x20];
        vmovdqu YMM2, [RSI+0x40];
        vmovdqu YMM3, [RSI+0x60];
        vmovdqa [RDI], YMM0;
        vmovdqa [RDI+0x20], YMM1;
        vmovdqa [RDI+0x40], YMM2;
        vmovdqa [RDI+0x60], YMM3;
        // src += 128;
        add    RSI, 128;
        // dst += 128;
        add    RDI, 128;
        // n -= 128;
        sub    RDX, 128;
        // if (n >= 128) loop
        cmp    RDX, 128;
        jge    L4;
    L2:
        // Move any remaining bytes.
        test   RDX, RDX;
        je     L3;
        cmp    RDX, 64;
        ja     L5;
        // Move the last 64
        vmovdqu YMM2, [R9+0x40];
        vmovdqu YMM3, [R9+0x60];
        vmovdqu [R11+0x40], YMM2;
        vmovdqu [R11+0x60], YMM3;
        jmp    L3;
        // if (n != 0)  -> copy the remaining <= 128 bytes
        // NOTE(stefanos): We can do this because to be in Dmemcpy_large,
        // the size is >= 128, so we can go back 128 bytes from the end
        // and copy at once.
        // NOTE(stefanos): No overlap is required.
    L5:
        // Move the last 128.
        vmovdqu YMM0, [R9];
        vmovdqu YMM1, [R9+0x20];
        vmovdqu YMM2, [R9+0x40];
        vmovdqu YMM3, [R9+0x60];
        vmovdqu [R11], YMM0;
        vmovdqu [R11+0x20], YMM1;
        vmovdqu [R11+0x40], YMM2;
        vmovdqu [R11+0x60], YMM3;
    }

    version(Windows)
    {
        asm pure nothrow @nogc
        {
        L3:
            pop RSI;
            pop RDI;
            ret;
        }
    }
    else
    {
        asm pure nothrow @nogc {
        L3:
            ret;
        }
    }
}


pragma(inline, true)
void Dmemcpy(T)(T *dst, const T *src)
if (is(T == struct))
{
    static if (T.sizeof == 1)
    {
        pragma(inline, true)
        Dmemcpy(cast(ubyte*)(dst), cast(const ubyte*)(src));
        return;
    }
    else static if (T.sizeof == 2)
    {
        pragma(inline, true)
        Dmemcpy(cast(ushort*)(dst), cast(const ushort*)(src));
        return;
    }
    else static if (T.sizeof == 4)
    {
        pragma(inline, true)
        Dmemcpy(cast(uint*)(dst), cast(const uint*)(src));
        return;
    }
    else static if (T.sizeof == 8)
    {
        pragma(inline, true)
        Dmemcpy(cast(ulong*)(dst), cast(const ulong*)(src));
        return;
    }
    else static if (T.sizeof == 16)
    {
        version(D_SIMD)
        {
            pragma(inline, true)
            import core.simd: void16, storeUnaligned, loadUnaligned;
            storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
        }
        else
        {
            //pragma(inline, true)
            static foreach(i; 0 .. T.sizeof/8)
            {
                Dmemcpy((cast(ulong*)dst) + i, (cast(const long*)src) + i);
            }
        }

        return;
    }
    else static if (T.sizeof == 32)
    {
        //pragma(inline, true)
        static foreach(i; 0 .. T.sizeof/16)
        {
            Dmemcpy((cast(S!16*)dst) + i, (cast(const S!16*)src) + i);
        }
        return;
    }
    else static if (T.sizeof < 64 && !isPowerOf2(T.sizeof))
    {
        pragma(inline, true)
        DmemcpyUnsafe(dst, src);
        return;
    }
    else static if (T.sizeof == 64)
    {
        Dmemcpy(cast(S!32*)dst, cast(const S!32*)src) ;
        Dmemcpy((cast(S!32*)dst) + 1, (cast(const S!32*)src) + 1);
    }
    else static if (T.sizeof <= 128)
    {
        pragma(inline, true);
        Dmemcpy_small(dst, src, T.sizeof);       
    }
    else
    {
        pragma(inline, true);
        Dmemcpy_large(dst, src, T.sizeof);       
    }
}

void Dmemmove_back_lt64(void *d, const(void) *s, size_t n)
{
    import core.simd: void16, void32, loadUnaligned, storeUnaligned;
    assert(n < 64);
    if (n & 32)
    {
        n -= 32;
        void16 xmm0 = loadUnaligned(cast(const void16*)(s+n+16));
        void16 xmm1 = loadUnaligned(cast(const void16*)(s+n));

        storeUnaligned(cast(void16*)(d+n+16), xmm0);
        storeUnaligned(cast(void16*)(d+n), xmm1);
    }
    if (n & 16)
    {
        n -= 16;
        storeUnaligned(cast(void16*)(d+n), loadUnaligned(cast(const void16*)(s+n)));
    }
    if (n & 8)
    {
        n -= 8;
        *(cast(ulong*)(d+n)) = *(cast(const ulong*)(s+n));
    }
    if (n & 4)
    {
        n -= 4;
        *(cast(uint*)(d+n)) = *(cast(const uint*)(s+n));
    }
    if (n & 2)
    {
        n -= 2;
        *(cast(ushort*)(d+n)) = *(cast(const ushort*)(s+n));
    }
    if (n & 1)
    {
        *(cast(ubyte*)d) = *(cast(const ubyte*)s);
    }
}

// IMPORTANT(stefanos): memmove is supposed to return the dest
void Dmemmove_back(void *d, const(void) *s, size_t n)
{
    import core.stdc.stdio: printf;
    import core.simd: void16, void32, loadUnaligned, storeUnaligned;

START:
    if (n < 64)
    {
        Dmemmove_back_lt64(d, s, n);
        return;
    }
    s += n;
    d += n;
    if (n < 128)
    {
        storeUnaligned(cast(void16*)(d-0x10), loadUnaligned(cast(const void16*)(s-0x10)));
        storeUnaligned(cast(void16*)(d-0x20), loadUnaligned(cast(const void16*)(s-0x20)));
        storeUnaligned(cast(void16*)(d-0x30), loadUnaligned(cast(const void16*)(s-0x30)));
        storeUnaligned(cast(void16*)(d-0x40), loadUnaligned(cast(const void16*)(s-0x40)));
        // NOTE(stefanos): We can't do the standard trick where we just go back enough bytes
        // so that we can move the last bytes with a 64-byte move even if they're less than 64.
        // To do that, we have to _not_ have overlap.
        s = s - n;
        d = d - n;
        n -= 64;
        Dmemmove_back_lt64(d, s, n);
        return;
    }
    uint mod = cast(ulong)d & 31;
    if (mod)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        Dmemmove_back_lt64(d-mod, s-mod, mod);
        s -= mod;
        d -= mod;
        n -= mod;
    }
    while (n >= 128)
    {
        // NOTE(stefanos): No problem with the overlap here since
        // we never use overlapped bytes.
        // TODO(stefanos): Explore prefetching.
        *(cast(void32*)(d-0x20)) = *(cast(const void32*)(s-0x20));
        *(cast(void32*)(d-0x40)) = *(cast(const void32*)(s-0x40));
        *(cast(void32*)(d-0x60)) = *(cast(const void32*)(s-0x60));
        *(cast(void32*)(d-0x80)) = *(cast(const void32*)(s-0x80));
        s -= 128;
        d -= 128;
        n -= 128;
    }

    if (n)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        // Move pointers to their start.
        s -= n;
        d -= n;
        goto START;
    }
}

pragma(inline, true)
void Dmemmove_forw_lt64(void *d, const(void) *s, size_t n)
{
    import core.simd: void16, void32, loadUnaligned, storeUnaligned;
    if (n & 32)
    {
        storeUnaligned(cast(void16*)(d), loadUnaligned(cast(const void16*)(s)));
        storeUnaligned(cast(void16*)(d+16), loadUnaligned(cast(const void16*)(s+16)));
        n -= 32;
        s += 32;
        d += 32;
    }
    if (n & 16)
    {
        storeUnaligned(cast(void16*)(d), loadUnaligned(cast(const void16*)(s)));
        n -= 16;
        s += 16;
        d += 16;
    }
    if (n & 8)
    {
        *(cast(ulong*)(d)) = *(cast(const ulong*)(s));
        n -= 8;
        s += 8;
        d += 8;
    }
    if (n & 4)
    {
        n -= 4;
        *(cast(uint*)(d)) = *(cast(const uint*)(s));
        n -= 4;
        s += 4;
        d += 4;
    }
    if (n & 2)
    {
        n -= 2;
        *(cast(ushort*)(d)) = *(cast(const ushort*)(s));
        n -= 2;
        s += 2;
        d += 2;
    }
    if (n & 1)
    {
        *(cast(ubyte*)d) = *(cast(const ubyte*)s);
    }
}

// IMPORTANT(stefanos): memmove is supposed to return the dest
void Dmemmove_forw(void *d, const(void) *s, size_t n)
{
    import core.stdc.stdio: printf;
    import core.simd: void16, void32, loadUnaligned, storeUnaligned;

START:
    if (n < 64)
    {
        Dmemmove_forw_lt64(d, s, n);
        return;
    }
    if (n < 128)
    {
        // We know it's >= 64, so move the first 64 bytes freely.
        storeUnaligned(cast(void16*)d, loadUnaligned(cast(const void16*)s));
        storeUnaligned(cast(void16*)(d+0x10), loadUnaligned(cast(const void16*)(s+0x10)));
        storeUnaligned(cast(void16*)(d+0x20), loadUnaligned(cast(const void16*)(s+0x20)));
        storeUnaligned(cast(void16*)(d+0x30), loadUnaligned(cast(const void16*)(s+0x30)));
        // NOTE(stefanos): We can't do the standard trick where we just go forward enough bytes
        // so that we can move the last bytes with a 64-byte move even if they're less than 64.
        // To do that, we have to _not_ have overlap.
        s += 64;
        d += 64;
        n -= 64;
        Dmemmove_forw_lt64(d, s, n);
        return;
    }
    uint mod = cast(ulong)d & 31;
    if (mod)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        Dmemmove_forw_lt64(d, s, 32-mod);
        s += 32 - mod;
        d += 32 - mod;
        n -= 32 - mod;
    }
    while (n >= 128)
    {
        // NOTE(stefanos): No problem with the overlap here since
        // we never use overlapped bytes.
        *(cast(void32*)d) = *(cast(const void32*)s);
        *(cast(void32*)(d+0x20)) = *(cast(const void32*)(s+0x20));
        *(cast(void32*)(d+0x40)) = *(cast(const void32*)(s+0x40));
        *(cast(void32*)(d+0x60)) = *(cast(const void32*)(s+0x60));
        s += 128;
        d += 128;
        n -= 128;
    }

    if (n)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        goto START;
    }
}

void Dmemmove(T)(T *dst, const T *src) {
    void *d = dst;
    const void *s = src;
    if ((cast(ulong)d - cast(ulong)s) < T.sizeof)
    {
        Dmemmove_back(d, s, T.sizeof);
    }
    else if ((cast(ulong)s - cast(ulong)d) < T.sizeof)
    {
        Dmemmove_forw(d, s, T.sizeof);
    }
    else
    {
        Dmemcpy(dst, src);
    }
}


/// DYNAMIC ///

import core.stdc.stdio: printf;

void Dmemmove(T)(ref T[] dst, const ref T[] src) {
    assert(dst.length == src.length);
    void *d = dst.ptr;
    const void *s = src.ptr;
    size_t n = dst.length * T.sizeof;
    if ((cast(ulong)d - cast(ulong)s) < n)
    {  // overlap with dst forward
        Dmemmove_back(d, s, n);
    }
    else if ((cast(ulong)s - cast(ulong)d) < n)
    {  // overlap with src forward
        Dmemmove_forw(d, s, n);
    }
    else
    {  // no overlap
        if (n <= 128)
        {
            pragma(inline, true);
            Dmemcpy_small(d, s, n);
        } else {
            pragma(inline, true);
            Dmemcpy_large(d, s, n);
        }
    }
}
