using System.Collections.Generic;
using System.Linq;
using nscreg.Business.DataSources;
using Xunit;

namespace nscreg.Business.Test.DataSources.Parsers
{
    public class CsvTest
    {
        [Fact]
        private void GetPropNamesTest()
        {
            var rows = new[]
            {
                "Export of C:\\Users\\digital\\Documents\\FlashPro Calibrations\\camshaft.csv\n",
                "Number of frames 3\n",
                "Length: 0:00:14.336s\n",
                "frame, time,Calc TRQ, TPedal, AFM.v Bank 2\n",
                "0,0,2141,18,a\n",
            };

            var actual = CsvParser.GetPropNames(rows);

            Assert.Equal(5, actual.propNames.Length);
            Assert.Contains("frame", actual.propNames);
            Assert.Contains("Calc TRQ", actual.propNames);
            Assert.Equal(3, actual.count);
        }

        [Fact]
        private void GetParsedEntitiesTest()
        {
            var rawEntities = new List<string> {"0,0,2141,18,a", "1,0.004,2141,18,b", "2,0.01,2141,18,c"};
            var names = new[] {"frame", "time", "Calc TRQ", "TPedal", "AFM.v Bank 2"};
            var expected = new[]
            {
                new Dictionary<string, string>
                {
                    [names[0]] = "0",
                    [names[1]] = "0",
                    [names[2]] = "2141",
                    [names[3]] = "18",
                    [names[4]] = "a",
                },
                new Dictionary<string, string>
                {
                    [names[0]] = "0",
                    [names[1]] = "0.004",
                    [names[2]] = "2141",
                    [names[3]] = "18",
                    [names[4]] = "b",
                },
                new Dictionary<string, string>
                {
                    [names[0]] = "0",
                    [names[1]] = "0.01",
                    [names[2]] = "2141",
                    [names[3]] = "18",
                    [names[4]] = "c",
                },
            };

            var actual = CsvParser.GetParsedEntities(rawEntities, names).ToArray();

            Assert.Equal(expected.Length, actual.Length);
            Assert.Equal(expected[0][names[4]], actual[0][names[4]]);
        }
    }
}
