using System.Collections.Generic;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Services.DataSources;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Services.Test.DataSources.QueueServiceTest
{
    public class QueueServiceMainTest
    {
        [Fact]
        private async Task CheckIfUnitExistsOnExistingUnit()
        {
            var unit = new LegalUnit {StatId = "1"};
            bool exists;
            using (var ctx = CreateDbContext())
            {
                ctx.LegalUnits.Add(unit);
                await ctx.SaveChangesAsync();
                exists = await new QueueService(ctx).CheckIfUnitExists(StatUnitTypes.LegalUnit, unit.StatId);
            }

            Assert.True(exists);
        }

        [Fact]
        private async Task CheckIfUnitExistsOnAbsentUnit()
        {
            var unit = new LocalUnit { StatId = "2" };
            bool exists;
            using (var ctx = CreateDbContext())
            {
                ctx.LocalUnits.Add(unit);
                await ctx.SaveChangesAsync();
                exists = await new QueueService(ctx).CheckIfUnitExists(StatUnitTypes.LocalUnit, "42");
            }

            Assert.False(exists);
        }

        [Fact]
        private async Task GetStatUnitFromRawEntityTest()
        {
            var raw = new Dictionary<string, string> {["sourceProp"] = "42"};
            var mapping = new[] {(source: "sourceProp", target: "StatId")};
            LegalUnit actual;

            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LegalUnit, mapping) as LegalUnit;

            Assert.Equal("42", actual.Name);
        }
    }
}
