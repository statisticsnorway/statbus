using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseDataSourceClassificationTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseDataSourceClassification($"{nameof(DataSourceClassification.Name)}", expected, null);

            Assert.Equal(actual.Name, expected);
        }
    }
}
