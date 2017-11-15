using Newtonsoft.Json;
using Xunit;
using static nscreg.Utilities.JsonPathHelper;

namespace nscreg.Server.Test
{
    public class JsonPathHelperTest
    {
        [Theory]
        [InlineData("{}", "a.b.c", "42")]
        [InlineData("{a:{}}", "a.b.c", "42")]
        [InlineData("{a:{b:{c:'17'}}}", "a.b.c", "42")]
        private void ShouldUpdateValueOfInitialObjectByPath (string initial, string path, string value)
        {
            var shape = new { a = new { b = new { c = "" } } };
            var expected = new { a = new { b = new { c = value } } };

            var actual = JsonConvert.DeserializeAnonymousType(ReplacePath(initial, path, value), shape);

            Assert.Equal(expected, actual);
        }
    }
}
