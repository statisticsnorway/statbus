using System;

namespace nscreg.TestUtils
{
    public static class DateTimeExtensions
    {
        public static DateTimeOffset FlushSeconds(this DateTimeOffset source)
            => source.AddTicks(-source.Ticks % TimeSpan.TicksPerSecond);
    }
}
