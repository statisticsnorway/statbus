using System;
using System.Diagnostics;

public class LogExecutionTime : IDisposable
{
    private readonly Stopwatch _sw = Stopwatch.StartNew();
    private readonly string _name;

    public LogExecutionTime(string name)
    {
        _name = name;
        Console.WriteLine($"LogExecutionTime: {_name} starting");
    }

    public void Dispose()
    {
        _sw.Stop();

        Console.WriteLine($"LogExecutionTime: {_name} finished in {_sw.ElapsedMilliseconds}ms");
    }

    public static LogExecutionTime As(string name) => new LogExecutionTime(name);
}
