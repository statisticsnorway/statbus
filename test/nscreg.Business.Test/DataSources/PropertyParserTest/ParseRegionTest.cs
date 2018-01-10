using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseRegionTest
    {
        [Fact]
        private void ShouldParseName()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseRegion($"{nameof(Region.Name)}", expected, null);

            Assert.Equal(expected, actual.Name);
        }
    }
}
