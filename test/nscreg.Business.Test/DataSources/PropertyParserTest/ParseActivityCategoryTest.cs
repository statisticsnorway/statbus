using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseActivityCategoryTest
    {
        [Fact]
        private void ShouldParseName()
        {
            const string expected = "some_name";

            var actual = PropertyParser.ParseActivityCategory($"{nameof(ActivityCategory.Name)}", expected, null);

            Assert.Equal(expected, actual.Name);
        }
    }
}
