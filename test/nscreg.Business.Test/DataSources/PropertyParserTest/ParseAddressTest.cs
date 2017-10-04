using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Newtonsoft.Json;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseAddressTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";
            var raw = JsonConvert.SerializeObject(new Address
            {
                Region = new Region { Name = expected }
            });

            var actual = PropertyParser.ParseAddress(raw);

            Assert.Equal(actual.Region.Name, expected);
        }
    }
}
