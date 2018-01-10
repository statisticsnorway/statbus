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
        private void ReplacePathShouldUpdateValueOfInitialObjectByPath(string initial, string path, string value)
        {
            var shape = new { a = new { b = new { c = "" } } };
            var expected = new { a = new { b = new { c = value } } };

            var actual = JsonConvert.DeserializeAnonymousType(ReplacePath(initial, path, value), shape);

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void PathHeadShouldReturnNullIfInputIsNull()
        {
            var actual = PathHead(null);

            Assert.Null(actual);
        }

        [Fact]
        private void PathHeadShouldReturnSameStringIfInputHasNoDots()
        {
            const string expected = "name";
            var actual = PathHead(expected);

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void PathHeadShouldBeOk()
        {
            const string expected = "name";
            var actual = PathHead("name.etc");

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void PathTailShouldReturnNullIfInputIsNull()
        {
            var actual = PathTail(null);

            Assert.Null(actual);
        }

        [Fact]
        private void PathTailShouldReturnEmptyStringIfInputHasNoDots()
        {
            var expected = string.Empty;
            var actual = PathTail(expected);

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void PathTailShouldBeOk()
        {
            const string expected = "name";
            var actual = PathTail("etc.name");

            Assert.Equal(expected, actual);
        }
    }
}
