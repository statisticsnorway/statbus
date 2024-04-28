using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParsePersonTest
    {
        [Fact]
        private void ShouldParseGivenName()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParsePerson($"{nameof(Person.GivenName)}", expected, null);

            Assert.Equal(actual.GivenName, expected);
        }
    }
}
