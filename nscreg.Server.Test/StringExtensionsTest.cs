using nscreg.Utilities;
using Xunit;

namespace nscreg.Server.Test
{
    public class StringExtensionsTest
    {
        [Fact]
        void IsPrintableString()
        {
            Assert.True("123qwe".IsPrintable());
        }

        [Fact]
        void IsNotPrintableString()
        {
            Assert.False("¤•2€3©".IsPrintable());
        }

        [Fact]
        void OnlyFirstLetterCaseLowered()
        {
            Assert.Equal("AbCd".LowerFirstLetter(), "abCd");
        }

        [Fact]
        void SingleLetterStringCaseLowered()
        {
            Assert.Equal("A".LowerFirstLetter(), "a");
        }
    }
}
