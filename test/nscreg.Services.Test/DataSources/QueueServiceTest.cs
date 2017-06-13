using System;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Services.DataSources;
using nscreg.TestUtils;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Services.Test.DataSources
{
    public class QueueServiceTest
    {
        [Fact]
        private async Task DequeueReturnsNullOnEmptyQueueTest()
        {
            DataSourceQueue actual;
            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx).Dequeue();

            Assert.Equal(null, actual);
        }

        [Fact]
        private async Task DequeueReturnsSingleItemTest()
        {
            var expected = new DataSourceQueue
            {
                DataSource = new DataSource
                {
                    Name = "ds1",
                    Priority = DataSourcePriority.NotTrusted,
                    AllowedOperations = DataSourceAllowedOperation.Alter,
                },
                StartImportDate = DateTime.MinValue,
                Status = DataSourceQueueStatuses.InQueue,
            };
            DataSourceQueue actual;

            using (var ctx = CreateDbContext())
            {
                ctx.Add(expected);
                await ctx.SaveChangesAsync();
                actual = await new QueueService(ctx).Dequeue();
            }

            Assert.NotNull(actual);
            Assert.Equal(actual.Status, DataSourceQueueStatuses.Loading);
            Assert.Equal(actual.StartImportDate.FlushSeconds(), DateTime.Now.FlushSeconds());
        }
    }
}
