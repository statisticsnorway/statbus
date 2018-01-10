using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseAddressTest
    {
        [Fact]
        private void ShouldParseUpToRegionName()
        {
            const string expected = "some_name";
            var propPath = $"{nameof(Address.Region)}.{nameof(Region.Name)}";

            var actual = PropertyParser.ParseAddress(propPath, expected, null);

            Assert.NotNull(actual);
            Assert.NotNull(actual.Region);
            Assert.Equal(actual.Region.Name, expected);
        }

        [Fact]
        private void ShouldPopulateExistingEntity()
        {
            const string expected1 = "part1";
            const string expected2 = "part2";

            var actual1 = PropertyParser.ParseAddress(nameof(Address.AddressPart1), expected1, null);

            Assert.NotNull(actual1);
            Assert.Equal(expected1, actual1.AddressPart1);

            var actual2 = PropertyParser.ParseAddress(nameof(Address.AddressPart2), expected2, actual1);

            Assert.NotNull(actual2);
            Assert.Equal(expected1, actual2.AddressPart1);
            Assert.Equal(expected2, actual2.AddressPart2);
        }
    }
}
