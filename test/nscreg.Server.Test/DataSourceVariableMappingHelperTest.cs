using System.Collections.Generic;
using Xunit;
using static nscreg.Utilities.DataSourceVariableMappingHelper;

namespace nscreg.Server.Test
{
    public class DataSourceVariableMappingHelperTest
    {
        [Fact]
        private void ParseStringToDictionaryTest()
        {
            const string source = "a-b,c-d";
            var expected = new Dictionary<string, string> {["a"] = "b", ["c"] = "d"};

            var actual = ParseStringToDictionary(source);

            Assert.Equal(expected, actual);
        }
    }
}
