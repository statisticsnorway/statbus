using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;
using nscreg.Server.Common.Services.DataSources;
using nscreg.Business.DataSources;

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
            var unit = new LocalUnit {StatId = "2"};
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
        private async Task GetStatUnitFromRawEntityOnNewUnit()
        {
            var raw = new Dictionary<string, string> {["sourceProp"] = "42"};
            var mapping = new[] {("sourceProp", "StatId")};
            LegalUnit actual;

            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LegalUnit, mapping) as LegalUnit;

            Assert.NotNull(actual);
            Assert.Equal("42", actual.StatId);
        }

        [Fact]
        private async Task GetStatUnitFromRawEntityOnExistingUnit()
        {
            var raw = new Dictionary<string, string> {["sourceProp"] = "name42", ["sourceId"] = "42"};
            var mapping = new[] {("sourceProp", "Name"), ("sourceId", "StatId")};
            LocalUnit actual;

            using (var ctx = CreateDbContext())
            {
                var unit = new LocalUnit {StatId = "42"};
                ctx.LocalUnits.Add(unit);
                await ctx.SaveChangesAsync();
                actual = await new QueueService(ctx)
                    .GetStatUnitFromRawEntity(raw, StatUnitTypes.LocalUnit, mapping) as LocalUnit;
            }

            Assert.NotNull(actual);
            Assert.NotNull(actual.RegId);
            Assert.Equal("42", actual.StatId);
            Assert.Equal("name42", actual.Name);
        }

        [Theory]
        [InlineData(DataUploadingLogStatuses.Done)]
        [InlineData(DataUploadingLogStatuses.Warning)]
        [InlineData(DataUploadingLogStatuses.Error)]
        private async Task LogStatUnitUplaodTest(DataUploadingLogStatuses status)
        {
            var unit = new LegalUnit {StatId = "123", Name = "name42"};
            var props = new[] {"StatId", "Name"};
            var started = DateTime.Now;
            var ended = DateTime.Now;
            DataUploadingLog actual;
            using (var ctx = CreateDbContext())
            {
                var queueItem = new DataSourceQueue();
                ctx.DataSourceQueues.Add(queueItem);
                await ctx.SaveChangesAsync();
                await new QueueService(ctx).LogStatUnitUpload(
                    queueItem,
                    unit,
                    props,
                    started,
                    ended,
                    status,
                    string.Empty);
                actual = queueItem.DataUploadingLogs.FirstOrDefault();
            }

            Assert.NotNull(actual);
            Assert.Equal(started, actual.StartImportDate);
            Assert.Equal(ended, actual.EndImportDate);
            Assert.Equal(status, actual.Status);
            Assert.Equal(StatUnitKeyValueParser.SerializeToString(unit, props), actual.SerializedUnit);
        }

        [Theory]
        [InlineData(false, DataSourceQueueStatuses.DataLoadCompleted)]
        [InlineData(true, DataSourceQueueStatuses.DataLoadCompletedPartially)]
        private async Task FinishQueueItemTest(bool hasUntrusted, DataSourceQueueStatuses expectedStatus)
        {
            var actual = new DataSourceQueue();

            using (var ctx = CreateDbContext())
            {
                ctx.DataSourceQueues.Add(actual);
                await ctx.SaveChangesAsync();
                await new QueueService(ctx).FinishQueueItem(actual, hasUntrusted);
            }

            Assert.Equal(expectedStatus, actual.Status);
        }

        [Theory]
        [InlineData(typeof(LegalUnit), StatUnitTypes.LegalUnit)]
        [InlineData(typeof(LocalUnit), StatUnitTypes.LocalUnit)]
        [InlineData(typeof(EnterpriseUnit), StatUnitTypes.EnterpriseUnit)]
        [InlineData(typeof(EnterpriseGroup), StatUnitTypes.EnterpriseGroup)]
        private async Task GetStatUnitFromRawEntityTest(Type type, StatUnitTypes unitType)
        {
            var raw = new Dictionary<string, string> {["source"] = "name42", ["sourceId"] = "qwe"};
            var mapping = new[] {("source", "Name"), ("sourceId", "StatId")};
            IStatisticalUnit actual;

            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx).GetStatUnitFromRawEntity(raw, unitType, mapping);

            Assert.Equal(actual.GetType(), type);
        }

        [Fact]
        private async Task ResetDequeuedIfTimedOut()
        {
            const int timeout = 6000;
            DataSourceQueue actual;

            using (var ctx = CreateDbContext())
            {
                ctx.DataSourceQueues.Add(new DataSourceQueue
                {
                    DataSource = new DataSource(),
                    StartImportDate = DateTime.Now.AddHours(-1),
                    Status = DataSourceQueueStatuses.Loading,
                });
                await ctx.SaveChangesAsync();

                await new QueueService(ctx).ResetDequeuedByTimeout(timeout);

                actual = await ctx.DataSourceQueues.SingleAsync();
            }

            Assert.NotNull(actual);
            Assert.Equal(DataSourceQueueStatuses.InQueue, actual.Status);
        }
    }
}
