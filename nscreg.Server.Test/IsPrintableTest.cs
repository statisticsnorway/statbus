using nscreg.Utilities;
using Xunit;

namespace nscreg.Server.Test
{
    public class IsPrintableTest
    {
        [Fact]
        public void ValidString()
        {
            Assert.True("123qwe".IsPrintable());
        }

        [Fact]
        public void InvalidString()
        {
            Assert.False("¤•2€3©".IsPrintable());
        }
    }
}
