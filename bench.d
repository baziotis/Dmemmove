/*
Boost Software License - Version 1.0 - August 17th, 2003

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
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

import std.datetime.stopwatch;
import Dmemmove: Dmemmove, Cmemmove;
import S_struct;
import std.random;
import std.stdio;
import core.stdc.string;
import std.traits;

///
///   A big thanks to Mike Franklin (JinShil). A big part of code is taken from his memcpyD implementation.
///

// From a very good Chandler Carruth video on benchmarking: https://www.youtube.com/watch?v=nXaxk27zwlk
void escape(void* p)
{
    version(LDC)
    {
        import ldc.llvmasm;
         __asm("", "r,~{memory}", p);
    }
    version(GNU)
    {
        asm { "" : : "g" p : "memory"; }
    }
}

void clobber()
{
    version(LDC)
    {
        import ldc.llvmasm;
        __asm("", "~{memory}");
    }
    version(GNU)
    {
        asm { "" : : : "memory"; }
    }
}

Duration benchmark(T, alias f)(T *dst, T *src, ulong* bytesCopied)
{
    enum iterations = 2^^20 / T.sizeof;
    Duration result;

    auto swt = StopWatch(AutoStart.yes);
    swt.reset();
    while(swt.peek().total!"msecs" < 50)
    {
        auto sw = StopWatch(AutoStart.yes);
        sw.reset();
        foreach (_; 0 .. iterations)
        {
            escape(&dst);   // So optimizer doesn't remove code
            f(dst, src);
            escape(&src);   // So optimizer doesn't remove code
        }
        result += sw.peek();
        *bytesCopied += (iterations * T.sizeof);
    }

    return result;
}

void init(T)(T *v)
{
    static if (is (T == float))
    {
        v = uniform(0.0f, 9_999_999.0f);
    }
    else static if (is(T == double))
    {
        v = uniform(0.0, 9_999_999.0);
    }
    else static if (is(T == real))
    {
        v = uniform(0.0L, 9_999_999.0L);
    }
    else
    {
        auto m = (cast(ubyte*)v)[0 .. T.sizeof];
        for(int i = 0; i < m.length; i++)
        {
            m[i] = uniform!byte;
        }
    }
}

void verify(T)(const T *a, const T *b)
{
    auto aa = (cast(ubyte*)a)[0..T.sizeof];
    auto bb = (cast(ubyte*)b)[0..T.sizeof];
    for(int i = 0; i < T.sizeof; i++)
    {
        assert(aa[i] == bb[i]);
    }
}

bool average;

void testStatic(T)()
{
    ubyte[80000] buf1;
    ubyte[80000] buf2;

    // TODO(stefanos): This should be a static foreach
    for (int j = 0; j < 3; ++j) {
        ubyte *p = buf1.ptr;
        ubyte *q;

        // Relatively aligned
        if (j == 0) {
            q = buf2.ptr;
        } else {
            q = p;
            // src forward
            if (j == 1)
            {
                p += T.sizeof / 2;
            // dst forward
            }
            else
            {
                q += T.sizeof / 2;
            }
        }


        double TotalGBperSec1 = 0.0;
        double TotalGBperSec2 = 0.0;
        enum alignments = 32;

        foreach(i; 0..alignments)
        {
            T* d = cast(T*)(&q[i]);
            T* s = cast(T*)(&p[i]);

            ulong bytesCopied1;
            ulong bytesCopied2;
            init(d);
            init(s);
            immutable d1 = benchmark!(T, Cmemmove)(d, s, &bytesCopied1);
            verify(d, s);

            init(d);
            init(s);
            immutable d2 = benchmark!(T, Dmemmove)(d, s, &bytesCopied2);
            verify(d, s);

            auto secs1 = (cast(double)(d1.total!"nsecs")) / 1_000_000_000.0;
            auto secs2 = (cast(double)(d2.total!"nsecs")) / 1_000_000_000.0;
            auto GB1 = (cast(double)bytesCopied1) / 1_000_000_000.0;
            auto GB2 = (cast(double)bytesCopied2) / 1_000_000_000.0;
            auto GBperSec1 = GB1 / secs1;
            auto GBperSec2 = GB2 / secs2;
            if (average)
            {
                TotalGBperSec1 += GBperSec1;
                TotalGBperSec2 += GBperSec2;
            }
            else
            {
                writeln(T.sizeof, " ", GBperSec1, " ", GBperSec2);
                stdout.flush();
            }
        }

        if (average)
        {
            write(T.sizeof, " ", TotalGBperSec1 / alignments, " ", TotalGBperSec2 / alignments);
            if (j == 0) {
                writeln(" - Relatively aligned");
            } else if (j == 1) {
                writeln(" - src forward");
            } else {
                writeln(" - dst forward");
            }
            stdout.flush();
        }
    }
}

Duration benchmark(T, alias f)(ref T[] dst, const ref T[] src, ulong* bytesCopied)
{
    enum iterations = 2^^20 / T.sizeof;
    Duration result;

    auto swt = StopWatch(AutoStart.yes);
    swt.reset();
    while(swt.peek().total!"msecs" < 50)
    {
        auto sw = StopWatch(AutoStart.yes);
        sw.reset();
        foreach (_; 0 .. iterations)
        {
            escape(cast(void*)dst.ptr);   // So optimizer doesn't remove code
            f(dst, src);
            escape(cast(void*)src.ptr);   // So optimizer doesn't remove code
        }
        result += sw.peek();
        *bytesCopied += (iterations * T.sizeof);
    }

    return result;
}



void testDynamic(size_t n)
{
    ubyte[180000] buf1;
    ubyte[180000] buf2;

    // TODO(stefanos): This should be a static foreach
    for (int j = 0; j < 3; ++j) {
        double TotalGBperSec1 = 0.0;
        double TotalGBperSec2 = 0.0;
        enum alignments = 32;

        foreach(i; 0..alignments)
        {
            ubyte[] p = buf1[i..i+n];
            ubyte[] q;

            // Relatively aligned
            if (j == 0) {
                q = buf2[i..i+n];
            } else {
                // src forward
                if (j == 1)
                {
                    q = p[n/2..n/2+n];
                // dst forward
                }
                else
                {
                    q = p;
                    p = p[n/2..n/2+n];
                }
            }
    

            ulong bytesCopied1;
            ulong bytesCopied2;
            //init(q.ptr);
            //init(p.ptr);
            immutable d1 = benchmark!(ubyte, Cmemmove)(p, q, &bytesCopied1);
            //verify(d, s);

            //init(d);
            //init(s);
            immutable d2 = benchmark!(ubyte, Dmemmove)(p, q, &bytesCopied2);
            //verify(d, s);

            auto secs1 = (cast(double)(d1.total!"nsecs")) / 1_000_000_000.0;
            auto secs2 = (cast(double)(d2.total!"nsecs")) / 1_000_000_000.0;
            auto GB1 = (cast(double)bytesCopied1) / 1_000_000_000.0;
            auto GB2 = (cast(double)bytesCopied2) / 1_000_000_000.0;
            auto GBperSec1 = GB1 / secs1;
            auto GBperSec2 = GB2 / secs2;
            if (average)
            {
                TotalGBperSec1 += GBperSec1;
                TotalGBperSec2 += GBperSec2;
            }
            else
            {
                writeln(n, " ", GBperSec1, " ", GBperSec2);
                stdout.flush();
            }
        }

        if (average)
        {
            write(n, " ", TotalGBperSec1 / alignments, " ", TotalGBperSec2 / alignments);
            if (j == 0) {
                writeln(" - Relatively aligned");
            } else if (j == 1) {
                writeln(" - src forward");
            } else {
                writeln(" - dst forward");
            }
            stdout.flush();
        }
    }
}

void main(string[] args)
{
    average = args.length >= 2;

    // For performing benchmarks
    writeln("size(bytes) Cmemmove(GB/s) Dmemmove(GB/s)");
    stdout.flush();
    /*
    testStatic!(S!1);
    testStatic!(S!3);
    testStatic!(S!7);
    testStatic!(S!13);
    testStatic!(S!22);
    testStatic!(S!29);
    testStatic!(S!39);
    testStatic!(S!45);
    testStatic!(S!54);
    testStatic!(S!63);
    testStatic!(S!64);
    static foreach(i; 120..130)
    {
        testStatic!(S!i);
    }
    static foreach(i; 220..230)
    {
        testStatic!(S!i);
    }
    static foreach(i; 720..730)
    {
        testStatic!(S!i);
    }
    */
    testStatic!(S!3452);
    testStatic!(S!6598);
    testStatic!(S!14928);
    testStatic!(S!27891);
    testStatic!(S!44032);
    testStatic!(S!55897);
    testStatic!(S!79394);

    testStatic!(S!256);
    testStatic!(S!512);
    testStatic!(S!1024);
    testStatic!(S!2048);
    testStatic!(S!4096);
    testStatic!(S!8192);
    testStatic!(S!16384);
    testStatic!(S!32768);
    testStatic!(S!65536);
}
