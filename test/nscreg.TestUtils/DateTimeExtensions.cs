using System;

namespace nscreg.TestUtils
{
    public static class DateTimeExtensions
    {
        public static DateTime FlushSeconds(this DateTime source)
            => source.AddTicks(-source.Ticks % TimeSpan.TicksPerSecond);
    }
}
