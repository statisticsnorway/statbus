using Newtonsoft.Json;
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
            var raw = JsonConvert.SerializeObject(new DataSourceClassification {Name = expected});

            var actual = PropertyParser.ParseDataSourceClassification(raw);

            Assert.Equal(actual.Name, expected);
        }
    }
}
