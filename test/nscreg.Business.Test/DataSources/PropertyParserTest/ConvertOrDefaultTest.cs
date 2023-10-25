using System;
using System.Globalization;
using nscreg.Business.DataSources;
using nscreg.TestUtils;
using Xunit;

namespace nscreg.Business.Test.DataSources.PropertyParserTest
{
    public class ConvertOrDefaultTest
    {
        [Fact]
        private void ShouldReturnValueForInt()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(int), "42");

            Assert.Equal(42, actual);
        }

        [Fact]
        private void ShouldReturnValueForNullableInt()
        {
            var actual = (int?) PropertyParser.ConvertOrDefault(typeof(int), "42");

            Assert.Equal(42, actual);
        }

        [Fact]
        private void ShouldReturnDefaultForInt()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(int), "forty-two");

            Assert.Equal(default(int), actual);
        }

        [Fact]
        private void ShouldReturnNullForNullableInt()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(int?), "forty-two");

            Assert.Null(actual);
        }

        [Fact]
        private void ShouldReturnValueForDecimal()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(decimal), "0.42");

            Assert.Equal(0.42m, actual);
        }

        [Fact]
        private void ShouldReturnValueForNullableDecimal()
        {
            var actual = (decimal?) PropertyParser.ConvertOrDefault(typeof(decimal), "0.42");

            Assert.Equal(0.42m, actual);
        }

        [Fact]
        private void ShouldReturnDefaultForDecimal()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(decimal), "abc");

            Assert.Equal(default(decimal), actual);
        }

        [Fact]
        private void ShouldReturnNullForNullableDecimal()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(decimal?), "abc");

            Assert.Null(actual);
        }

        [Fact]
        private void ShouldReturnStringAsIs()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(string), "42");

            Assert.Equal("42", actual);
        }

        [Fact]
        private void ShouldReturnValueForDateTimeOffset()
        {
            var expected = DateTimeOffset.Now.FlushSeconds();
            var raw = expected.ToString(CultureInfo.InvariantCulture);

            var actual = PropertyParser.ConvertOrDefault(typeof(DateTimeOffset), raw);

            Assert.Equal(expected, actual);
        }

        [Fact]
        private void ShouldReturnDefaultForDateTimeOffset()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(DateTimeOffset), "not now");

            Assert.Equal(default(DateTimeOffset), actual);
        }

        [Fact]
        private void ShouldReturnNullForNullableDateTimeOffset()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(DateTimeOffset?), "not now");

            Assert.Null(actual);
        }
    }
}
