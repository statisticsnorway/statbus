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
        private void ShouldReturnValueForDateTime()
        {
            var expected = DateTime.Now.FlushSeconds();
            var raw = expected.ToString(CultureInfo.InvariantCulture);

            var actual = PropertyParser.ConvertOrDefault(typeof(DateTime), raw);

            Assert.Equal(expected, actual);
        }

        //[Fact]
        //private void ShouldReturnValueForNullableDateTime()
        //{
        //    DateTime? expected = DateTime.Now.FlushSeconds();
        //    var raw = expected.ToString();

        //    var actual = (DateTime?) PropertyParser.ConvertOrDefault(typeof(DateTime), raw);

        //    Assert.Equal(expected, actual);
        //}

        [Fact]
        private void ShouldReturnDefaultForDateTime()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(DateTime), "not now");

            Assert.Equal(default(DateTime), actual);
        }

        [Fact]
        private void ShouldReturnNullForNullableDateTime()
        {
            var actual = PropertyParser.ConvertOrDefault(typeof(DateTime?), "not now");

            Assert.Null(actual);
        }
    }
}
