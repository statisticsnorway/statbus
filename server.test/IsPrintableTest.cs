using Server.Helpers;
using Xunit;

namespace Server.Test
{
    public class IsPrintableTest
    {
        [Fact]
        public void ValidString()
        {
            Assert.True("123".IsPrintable());
        }

        [Fact]
        public void InvalidString()
        {
            Assert.False("¤•2€3©".IsPrintable());
        }
    }
}
