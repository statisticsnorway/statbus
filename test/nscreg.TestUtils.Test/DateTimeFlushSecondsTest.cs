using System;
using System.Globalization;
using Xunit;

namespace nscreg.TestUtils.Test
{
    public class DateTimeFlushSecondsTest
    {
        [Fact]
        private void ParseAsStringTest()
        {
            var source = DateTimeOffset.Now;
            var stringified = source.ToString(CultureInfo.InvariantCulture);
            var expected = DateTimeOffset.Parse(stringified, CultureInfo.InvariantCulture);

            var actual = source.FlushSeconds();

            Assert.Equal(expected, actual);
        }
    }
}
