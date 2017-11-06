using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Newtonsoft.Json;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseActivityTest
    {
        [Fact]
        private void ShouldParseSimilarJsonShape()
        {
            const string expected = "some_name";
            var raw = JsonConvert.SerializeObject(new Activity
            {
                ActivityCategory = new ActivityCategory {Name = expected}
            });

            var actual = PropertyParser.ParseActivity(raw);

            Assert.Equal(actual.ActivityCategory.Name, expected);
        }
    }
}
