using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.DataSources;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Services.Test.DataSources.QueueServiceTest
{
    public class QueueServiceGetStatUnitFromRawEntityTest
    {
        [Fact]
        private async Task ShouldCreateStatUnitWithoutComplexEntities()
        {
            const string expected = "42", sourceProp = "activities";
            var raw = new Dictionary<string, string> { [sourceProp] = expected };
            var mapping = new[] { (sourceProp, nameof(StatisticalUnit.StatId)) };
            LegalUnit actual;

            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LegalUnit, mapping) as LegalUnit;

            Assert.NotNull(actual);
            Assert.Equal(expected, actual.StatId);
        }

        [Fact]
        private async Task ShouldGetExistingStatUnitWithoutComplexEntities()
        {
            var raw = new Dictionary<string, string> { ["sourceProp"] = "name42", ["sourceId"] = "42" };
            var mapping = new[] { ("sourceProp", "Name"), ("sourceId", nameof(StatisticalUnit.StatId)) };
            LocalUnit actual;

            using (var ctx = CreateDbContext())
            {
                var unit = new LocalUnit { StatId = "42" };
                ctx.LocalUnits.Add(unit);
                await ctx.SaveChangesAsync();
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LocalUnit, mapping) as LocalUnit;
            }

            Assert.NotNull(actual);
            Assert.Equal("42", actual.StatId);
            Assert.Equal("name42", actual.Name);
        }

        [Fact]
        private async Task ShouldCreateStatUnitAndCreateActivity()
        {
            const string expected = "42", sourceProp = "activities";
            var raw = new Dictionary<string, string>
            {
                [sourceProp] = JsonConvert.SerializeObject(
                    new Activity {ActivityCategory = new ActivityCategory {Code = expected}})
            };
            var mapping = new[]
                {(sourceProp, nameof(StatisticalUnit.Activities))};
            LegalUnit actual;

            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LegalUnit, mapping) as LegalUnit;

            Assert.NotNull(actual);
            Assert.NotEmpty(actual.Activities);
            Assert.NotNull(actual.Activities.First());
            Assert.NotNull(actual.Activities.First().ActivityCategory);
            Assert.Equal(expected, actual.Activities.First().ActivityCategory.Code);
        }

        [Fact]
        private async Task ShouldCreateStatUnitAndGetExistingActivity()
        {
            int expectedId;
            const string expected = "42", sourceProp = "activities";
            var raw = new Dictionary<string, string>
            {
                [sourceProp] = JsonConvert.SerializeObject(
                    new Activity { ActivityCategory = new ActivityCategory { Code = expected } })
            };
            var mapping = new[]
                {(sourceProp, nameof(StatisticalUnit.Activities))};
            LegalUnit actual;

            using (var ctx = CreateDbContext())
            {
                var activityCategory = new ActivityCategory {Code = expected};
                ctx.Activities.Add(new Activity {ActivityCategory = activityCategory});
                await ctx.SaveChangesAsync();
                expectedId = activityCategory.Id;
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LegalUnit, mapping) as LegalUnit;
            }

            Assert.NotNull(actual);
            Assert.NotEmpty(actual.Activities);
            Assert.NotNull(actual.Activities.First());
            Assert.NotNull(actual.Activities.First().ActivityCategory);
            Assert.Equal(expected, actual.Activities.First().ActivityCategory.Code);
            Assert.Equal(expectedId, actual.Activities.First().ActivityCategory.Id);
        }
    }
}
