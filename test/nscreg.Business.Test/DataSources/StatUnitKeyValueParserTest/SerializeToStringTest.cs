using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.StatUnitKeyValueParserTest
{
    public class SerializeToStringTest
    {
        [Fact]
        private void SingleMappingProperty()
        {
            var unit = new LegalUnit {Name = "abc, def"};
            var props = new[] {"Name"};
            const string expected = "\"name\":\"abc, def\"";

            var actual = StatUnitKeyValueParser.SerializeToString(unit, props);

            Assert.Contains(expected, actual);
            Assert.DoesNotContain("\"notes\"", actual);
        }

        [Fact]
        private void MultipleMappedProperties()
        {
            var unit = new LocalUnit {Name = "a", Notes = "a, b, c"};
            var props = new[] {"Name", "Notes"};
            const string expectedName = "\"name\":\"a\"";
            const string expectedNotes = "\"notes\":\"a, b, c\"";

            var actual = StatUnitKeyValueParser.SerializeToString(unit, props);

            Assert.Contains(expectedName, actual);
            Assert.Contains(expectedNotes, actual);
            Assert.DoesNotContain("\"shortName\"", actual);
        }
    }
}
