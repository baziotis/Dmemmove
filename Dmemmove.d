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
import std.stdio;

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

////// Mini SIMD library ////////

// TODO(stefanos): Consider making backwards versions

// NOTE - IMPORTANT(stefanos): It's important to use
// DMD's load/storeUnaligned when compiling with DMD (i.e. core.simd versions)
// for correct code generation.
import core.simd: float4;
version (LDC)
{
    import ldc.simd: loadUnaligned, storeUnaligned;
}
else
version (DigitalMars)
{
    import core.simd: void16, loadUnaligned, storeUnaligned;
}
else
{
    static assert(0, "Version not supported");
}

void store16_sse(void *dest, float4 reg)
{
    version (LDC)
    {
        storeUnaligned!float4(reg, cast(float*)dest);
    }
    else
    {
        storeUnaligned(cast(void16*)dest, reg);
    }
}

float4 load16_sse(const(void) *src)
{
    version (LDC)
    {
        return loadUnaligned!(float4)(cast(const(float) *)src);
    }
    else
    {
        return loadUnaligned(cast(void16*)src);
    }
}

/*
void _store128p_sse(void *d, const(void) *s)
{
    _mm_prefetch!(0)(cast(void*)s+0x1a0);
    _mm_prefetch!(0)(cast(void*)s+0x280);
    store128_sse(d, s);
}
*/

void store128_sse(void *d, const(void) *s)
{
    float4 xmm0 = load16_sse(cast(const float*)s);
    float4 xmm1 = load16_sse(cast(const float*)(s+16));
    float4 xmm2 = load16_sse(cast(const float*)(s+32));
    float4 xmm3 = load16_sse(cast(const float*)(s+48));
    float4 xmm4 = load16_sse(cast(const float*)(s+64));
    float4 xmm5 = load16_sse(cast(const float*)(s+80));
    float4 xmm6 = load16_sse(cast(const float*)(s+96));
    float4 xmm7 = load16_sse(cast(const float*)(s+112));

    store16_sse(cast(float*)d, xmm0);
    store16_sse(cast(float*)(d+16), xmm1);
    store16_sse(cast(float*)(d+32), xmm2);
    store16_sse(cast(float*)(d+48), xmm3);
    store16_sse(cast(float*)(d+64), xmm4);
    store16_sse(cast(float*)(d+80), xmm5);
    store16_sse(cast(float*)(d+96), xmm6);
    store16_sse(cast(float*)(d+112), xmm7);
}

void store64_sse(void *d, const(void) *s)
{
    float4 xmm0 = load16_sse(cast(const float*)s);
    float4 xmm1 = load16_sse(cast(const float*)(s+16));
    float4 xmm2 = load16_sse(cast(const float*)(s+32));
    float4 xmm3 = load16_sse(cast(const float*)(s+48));

    store16_sse(cast(float*)d, xmm0);
    store16_sse(cast(float*)(d+16), xmm1);
    store16_sse(cast(float*)(d+32), xmm2);
    store16_sse(cast(float*)(d+48), xmm3);
}

void store32_sse(void *d, const(void) *s)
{
    float4 xmm0 = load16_sse(cast(const float*)s);
    float4 xmm1 = load16_sse(cast(const float*)(s+16));
    store16_sse(cast(float*)d, xmm0);
    store16_sse(cast(float*)(d+16), xmm1);
}

// NOTE(stefanos): This function requires _no_ overlap.
extern(C) void Dmemcpy_small(void *d, const(void) *s, size_t n)
{
    if (n < 16) {
        if (n & 0x01)
        {
            *cast(ubyte*)d = *cast(const ubyte*)s;
            ++d;
            ++s;
        }
        if (n & 0x02)
        {
            *cast(ushort*)d = *cast(const ushort*)s;
            d += 2;
            s += 2;
        }
        if (n & 0x04)
        {
            *cast(uint*)d = *cast(const uint*)s;
            d += 4;
            s += 4;
        }
        if (n & 0x08)
        {
            *cast(ulong*)d = *cast(const ulong*)s;
        }
        return;
    }
    if (n <= 32)
    {
        /*
        import core.simd: void16, storeUnaligned, loadUnaligned;
        void16 xmm0 = loadUnaligned(cast(const void16*)(s));
        void16 xmm1 = loadUnaligned(cast(const void16*)(s-16+n));
        storeUnaligned(cast(void16*)(d), xmm0);
        storeUnaligned(cast(void16*)(d-16+n), xmm1);
        */
        float4 xmm0 = load16_sse(cast(const float*)s);
        float4 xmm1 = load16_sse(cast(const float*)(s-16+n));
        store16_sse(cast(float*)d, xmm0);
        store16_sse(cast(float*)(d-16+n), xmm1);
        return;
    }
    // NOTE(stefanos): I'm writing using load/storeUnaligned() but you possibly can
    // achieve greater performance using naked ASM. Be careful that you should either use
    // only D or only naked ASM.
    if (n <= 64)
    {
        float4 xmm0 = load16_sse(cast(const float*)s);
        float4 xmm1 = load16_sse(cast(const float*)(s+16));
        float4 xmm2 = load16_sse(cast(const float*)(s-32+n));
        float4 xmm3 = load16_sse(cast(const float*)(s-32+n+16));
        store16_sse(cast(float*)d, xmm0);
        store16_sse(cast(float*)(d+16), xmm1);
        store16_sse(cast(float*)(d-32+n), xmm2);
        store16_sse(cast(float*)(d-32+n+16), xmm3);
        return;
    }
    import core.simd: void16;
    store64_sse(d, s);
    // NOTE(stefanos): Requires _no_ overlap.
    n -= 64;
    s = s + n;
    d = d + n;
    store64_sse(d, s);
}

// TODO(stefanos): I tried prefetching. I suppose
// because this is a forward implementation, it should
// actuall reduce performance, but a better check would be good.
// TODO(stefanos): Consider aligning from the end, negate `n` and adding
// every time the `n` (and thus going backwards). That reduces the operations
// inside the loop.
// TODO(stefanos): Consider aligning `n` to 32. This will reduce one operation
// inside the loop but only if the compiler can pick it up (in my tests, it didn't).
// TODO(stefanos): Do a better research on how to inform the compiler about alignment,
// something like assume_aligned.
// NOTE(stefanos): This function requires _no_ overlap.
void Dmemcpy_large(void *d, const(void) *s, size_t n)
{
    // NOTE(stefanos): Alternative - Reach 64-byte
    // (cache-line) alignment and use rep movsb
    // Good for bigger sizes and only for Intel.

    // Align destination (write) to 32-byte boundary
    // NOTE(stefanos): We're using SSE, which needs 16-byte alignment.
    // But actually, 32-byte alignment was quite faster (probably because
    // the loads / stores are faster and there's the bottleneck).
    uint rem = cast(ulong)d & 15;
    if (rem)
    {
        store16_sse(d, load16_sse(s));
        s += 16 - rem;
        d += 16 - rem;
        n -= 16 - rem;
    }

    while (n >= 128)
    {
        // Aligned stores / writes
        store128_sse(d, s);
        d += 128;
        s += 128;
        n -= 128;
    }

    // NOTE(stefanos): We already have checked that the initial size is >= 128
    // to be here. So, we won't overwrite previous data.
    if (n != 0)
    {
        store128_sse(d - 128 + n, s - 128 + n);
    }
}


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
            //pragma(inline, true)
            import core.simd: void16, storeUnaligned, loadUnaligned;
            storeUnaligned(cast(void16*)(dst), loadUnaligned(cast(const void16*)(src)));
        }
        else
        {
            //pragma(inline, true)
            foreach(i; 0 .. T.sizeof/8)
            {
                Dmemcpy((cast(ulong*)dst) + i, (cast(const ulong*)src) + i);
            }
        }

        return;
    }
    else static if (T.sizeof == 32)
    {
        //pragma(inline, true)
        foreach(i; 0 .. T.sizeof/16)
        {
            Dmemcpy((cast(S!16*)dst) + i, (cast(const S!16*)src) + i);
        }
        return;
    }
    else static if (T.sizeof < 64 && !isPowerOf2(T.sizeof))
    {
        //pragma(inline, true)
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
    if (n & 32)
    {
        n -= 32;
        // IMPORTANT(stefanos): Don't call _store* functions as they copy forward.
        // First load both values, _then_ store.
        float4 xmm0 = load16_sse(cast(const float*)(s+n+16));
        float4 xmm1 = load16_sse(cast(const float*)(s+n));
        store16_sse(cast(float*)(d+n+16), xmm0);
        store16_sse(cast(float*)(d+n), xmm1);
    }
    if (n & 16)
    {
        n -= 16;
        float4 xmm0 = load16_sse(cast(const float*)(s+n));
        store16_sse(cast(float*)(d+n), xmm0);
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
        float4 xmm0 = load16_sse(cast(const float*)(s-0x10));
        float4 xmm1 = load16_sse(cast(const float*)(s-0x20));
        float4 xmm2 = load16_sse(cast(const float*)(s-0x30));
        float4 xmm3 = load16_sse(cast(const float*)(s-0x40));
        store16_sse(cast(float*)(d-0x10), xmm0);
        store16_sse(cast(float*)(d-0x20), xmm1);
        store16_sse(cast(float*)(d-0x30), xmm2);
        store16_sse(cast(float*)(d-0x40), xmm3);
        // NOTE(stefanos): We can't do the standard trick where we just go back enough bytes
        // so that we can move the last bytes with a 64-byte move even if they're less than 64.
        // To do that, we have to _not_ have overlap.
        s = s - n;
        d = d - n;
        n -= 64;
        Dmemmove_back_lt64(d, s, n);
        return;
    }
    uint rem = cast(ulong)d & 31;
    if (rem)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        Dmemmove_back_lt64(d-rem, s-rem, rem);
        s -= rem;
        d -= rem;
        n -= rem;
    }
    while (n >= 128)
    {
        // NOTE(stefanos): No problem with the overlap here since
        // we never use overlapped bytes. But, we should still copy backwards.
        // TODO(stefanos): Explore prefetching.
        store16_sse(cast(float*)(d-0x10), load16_sse(cast(const float*)(s-0x10)));
        store16_sse(cast(float*)(d-0x20), load16_sse(cast(const float*)(s-0x20)));
        store16_sse(cast(float*)(d-0x30), load16_sse(cast(const float*)(s-0x30)));
        store16_sse(cast(float*)(d-0x40), load16_sse(cast(const float*)(s-0x40)));
        store16_sse(cast(float*)(d-0x50), load16_sse(cast(const float*)(s-0x50)));
        store16_sse(cast(float*)(d-0x60), load16_sse(cast(const float*)(s-0x60)));
        store16_sse(cast(float*)(d-0x70), load16_sse(cast(const float*)(s-0x70)));
        store16_sse(cast(float*)(d-0x80), load16_sse(cast(const float*)(s-0x80)));
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

void Dmemmove_forw_lt64(void *d, const(void) *s, size_t n)
{
    if (n & 32)
    {
        store32_sse(d, s);
        n -= 32;
        s += 32;
        d += 32;
    }
    if (n & 16)
    {
        store16_sse(d, load16_sse(s));
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
START:
    if (n < 64)
    {
        Dmemmove_forw_lt64(d, s, n);
        return;
    }
    if (n < 128)
    {
        // We know it's >= 64, so move the first 64 bytes freely.
        store64_sse(d, s);
        // NOTE(stefanos): We can't do the standard trick where we just go forward enough bytes
        // so that we can move the last bytes with a 64-byte move even if they're less than 64.
        // To do that, we have to _not_ have overlap.
        s += 64;
        d += 64;
        n -= 64;
        Dmemmove_forw_lt64(d, s, n);
        return;
    }
    uint rem = cast(ulong)d & 31;
    if (rem)
    {
        // NOTE(stefanos): Again, can't use the standard trick because of overlap.
        Dmemmove_forw_lt64(d, s, 32-rem);
        s += 32 - rem;
        d += 32 - rem;
        n -= 32 - rem;
    }

    while (n >= 128)
    {
        // NOTE(stefanos): No problem with the overlap here since
        // we never use overlapped bytes.
        store128_sse(d, s);
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
