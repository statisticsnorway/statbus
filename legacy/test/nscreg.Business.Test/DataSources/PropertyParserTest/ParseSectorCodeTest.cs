using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseSectorCodeTest
    {
        [Fact]
        private void ShouldParseName()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseSectorCode($"{nameof(SectorCode.Name)}", expected, null);

            Assert.Equal(actual.Name, expected);
        }
    }
}
