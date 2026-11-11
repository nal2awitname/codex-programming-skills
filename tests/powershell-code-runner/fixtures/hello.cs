// C# 5 syntax so the built-in .NET Framework compiler can build it too.
using System;

public static class Program
{
    public static int Main(string[] args)
    {
        Console.WriteLine("OK:" + string.Join("|", args));
        return 3;
    }
}
