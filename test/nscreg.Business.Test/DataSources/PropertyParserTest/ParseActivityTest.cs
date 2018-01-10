using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ParseActivityTest
    {
        [Fact]
        private void ShouldParseUpToActivityCategoryName()
        {
            const string expected = "some_name";

            var actual =
                PropertyParser.ParseActivity($"{nameof(Activity.ActivityCategory)}.{nameof(ActivityCategory.Name)}",
                    expected, null);

            Assert.Equal(actual.ActivityCategory.Name, expected);
        }
    }
}
