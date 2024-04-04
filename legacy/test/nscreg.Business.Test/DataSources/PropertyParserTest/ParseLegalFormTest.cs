using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseLegalFormTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseLegalForm($"{nameof(LegalForm.Name)}", expected, null);

            Assert.Equal(actual.Name, expected);
        }
    }
}
