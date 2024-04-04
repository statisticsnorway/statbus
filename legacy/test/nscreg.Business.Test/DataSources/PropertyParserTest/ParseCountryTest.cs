using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseCountryTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseCountry($"{nameof(Country.Name)}", expected, null);

            Assert.Equal(actual.Name, expected);
        }
    }
}
