using nscreg.Business.DataSources;
using nscreg.Data.Entities;
using Xunit;

namespace nscreg.Business.Test.DataSources.StatUnitKeyValueParserTest
{
    public class GetStatIdSourceKeyTest
    {
        [Fact]
        private void GetStatIdKeySingleMappingRule()
        {
            const string source = "stat_id",
                target = nameof(IStatisticalUnit.StatId);
            var mapping = new[] {(source, target)};

            var actual = StatUnitKeyValueParser.GetStatIdMapping(mapping);

            Assert.Equal(target, actual);
        }

        [Fact]
        private void GetStatIdKeyMultipleRules()
        {
            const string source1 = "stat_id",
                source2 = "prop2",
                target1 = nameof(IStatisticalUnit.StatId),
                target2 = "Prop2";
            var mapping = new[]
            {
                (source1, target1),
                (source2, target2),
            };

            var actual = StatUnitKeyValueParser.GetStatIdMapping(mapping);

            Assert.Equal(target1, actual);
        }
    }
}
