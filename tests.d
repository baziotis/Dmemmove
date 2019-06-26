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

import Dmemmove: Dmemmove;
import S_struct;
import std.random;
import std.stdio;
import core.stdc.string;
import std.traits;

void main(string[] args)
{
    stdout.flush();
    testStaticType!(byte);
    testStaticType!(ubyte);
    testStaticType!(short);
    testStaticType!(ushort);
    testStaticType!(int);
    testStaticType!(uint);
    testStaticType!(long);
    testStaticType!(ulong);
    testStaticType!(float);
    testStaticType!(double);
    testStaticType!(real);
    static foreach (i; 1..100)
    {
        testStaticType!(S!i);
        testStaticArray!(i)();
    }
    testStaticType!(S!3452);
    testStaticArray!(3452)();
    testStaticType!(S!6598);
    testStaticArray!(6598);
    testStaticType!(S!14928);
    testStaticArray!(14928);
    testStaticType!(S!27891);
    testStaticArray!(27891);
    testStaticType!(S!44032);
    testStaticType!(S!55897);
    testStaticType!(S!79394);

    testStaticType!(S!256);
    testStaticType!(S!512);
    testStaticType!(S!1024);
    testStaticType!(S!2048);
    testStaticType!(S!4096);
    testStaticType!(S!8192);
    testStaticType!(S!16384);
    testStaticType!(S!32768);
    testStaticType!(S!65536);
}

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

pragma(inline, false)
void init(T)(T *v)
{
    static if (is(T == float))
    {
        *v = uniform(0.0f, 9_999_999.0f);
    }
    else static if (is(T == double))
    {
        *v = uniform(0.0, 9_999_999.0);
    }
    else static if (is(T == real))
    {
        *v = uniform(0.0L, 9_999_999.0L);
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

pragma(inline, false)
void verifyStaticType(T)(const T *a, const T *b)
{
    const ubyte *aa = (cast(const ubyte*)a);
    const ubyte *bb = (cast(const ubyte*)b);
    for(size_t i = 0; i < T.sizeof; i++)
    {
        assert(aa[i] == bb[i]);
    }
}

pragma(inline, false)
void testStaticType(T)()
{
    T d, s;
    init(&d);
    init(&s);
    Dmemmove(&d, &s);
    verifyStaticType(&d, &s);
}

pragma(inline, false)
void init(T)(ref T[] v)
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
        for(int i = 0; i < v.length; i++)
        {
            v[i] = uniform!byte;
        }
    }
}

pragma(inline, false)
void verifyArray(T, string name)(size_t j, const ref T[] a, const ref T[80000] b)
{
    //assert(a.length == b.length);
    for(int i = 0; i < a.length; i++)
    {
        assert(a[i] == b[i]);
    }
}

pragma(inline, false)
void testStaticArray(size_t n)()
{
    ubyte[80000] buf1;
    ubyte[80000] buf2;

    // TODO(stefanos): This should be a static foreach
    for (int j = 0; j < 3; ++j) {
        enum alignments = 32;

        foreach(i; 0..alignments)
        {
            ubyte[] p = buf1[i..i+n];
            ubyte[] q;

            // Relatively aligned
            if (j == 0)
            {
                q = buf2[0..n];
            }
            else {
                // dst forward
                if (j == 1)
                {
                    q = buf1[i+n/2..i+n/2+n];
                }
                // src forward
                else
                {
                    q = p;
                    p = buf1[i+n/2..i+n/2+n];
                }
            }

            // Use a copy for the cases of overlap.
            ubyte[80000] copy;

            pragma(inline, false);
            init(q);
            pragma(inline, false);
            init(p);
            for (size_t k = 0; k != p.length; ++k)
            {
                copy[k] = p[k];
            }
            pragma(inline, false);
            Dmemmove(q, p);
            pragma(inline, false);
            verifyArray!(ubyte, "Dmemmove")(i, q, copy);
        }
    }
}
