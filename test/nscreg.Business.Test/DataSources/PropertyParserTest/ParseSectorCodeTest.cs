using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Newtonsoft.Json;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseSectorCodeTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";
            var raw = JsonConvert.SerializeObject(new SectorCode {Name = expected});

            var actual = PropertyParser.ParseSectorCode(raw);

            Assert.Equal(actual.Name, expected);
        }
    }
}
