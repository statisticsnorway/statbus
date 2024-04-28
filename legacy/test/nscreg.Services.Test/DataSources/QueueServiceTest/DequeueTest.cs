using System;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Services.DataSources;
using nscreg.TestUtils;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Services.Test.DataSources.QueueServiceTest
{
    public class DequeueTest
    {
        [Fact]
        private async Task DequeueReturnsNullOnEmptyDataSourceQueues()
        {
            DataSourceQueue actual;
            using (var ctx = CreateDbContext())
                actual = await new QueueService(ctx).Dequeue();

            Assert.Null(actual);
        }

        [Fact]
        private async Task DequeueReturnsNullIfNoItemsWithInQueueStatus()
        {
            var expected = new DataSourceQueue
            {
                DataSourceFileName = "TestFileName",
                DataSourcePath = "TestPath",
                DataSource = new DataSource
                {
                    Name = "ds1",
                    Priority = DataSourcePriority.NotTrusted,
                    AllowedOperations = DataSourceAllowedOperation.Alter,
                },
                StartImportDate = DateTimeOffset.MinValue,
                Status = DataSourceQueueStatuses.DataLoadCompleted,
            };
            DataSourceQueue actual;

            using (var ctx = CreateDbContext())
            {
                ctx.Add(expected);
                await ctx.SaveChangesAsync();
                actual = await new QueueService(ctx).Dequeue();
            }

            Assert.Null(actual);
        }

        [Fact]
        private async Task DequeueReturnsSingleItem()
        {
            var expected = new DataSourceQueue
            {
                DataSourceFileName = "TestFileName",
                DataSourcePath = "TestPath",
                DataSource = new DataSource
                {
                    Name = "ds1",
                    Priority = DataSourcePriority.NotTrusted,
                    AllowedOperations = DataSourceAllowedOperation.Alter,
                },
                StartImportDate = DateTimeOffset.MinValue,
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
            Assert.Equal(DataSourceQueueStatuses.Loading, actual.Status);
            Assert.NotNull(actual.StartImportDate);
            Assert.Equal(actual.StartImportDate.Value.FlushSeconds(), DateTimeOffset.Now.FlushSeconds());
        }

        [Fact]
        private async Task DequeuedItemIncludesDataSourceEntity()
        {
            var expected = new DataSourceQueue
            {
                DataSourceFileName = "TestFileName",
                DataSourcePath = "TestPath",
                DataSource = new DataSource
                {
                    Name = "ds1",
                    Priority = DataSourcePriority.NotTrusted,
                    AllowedOperations = DataSourceAllowedOperation.Alter,
                },
                StartImportDate = DateTimeOffset.MinValue,
                Status = DataSourceQueueStatuses.InQueue,
            };
            DataSourceQueue actual;

            using (var ctx = CreateDbContext())
            {
                ctx.Add(expected);
                await ctx.SaveChangesAsync();
                actual = await new QueueService(ctx).Dequeue();
            }

            Assert.NotNull(actual.DataSource);
            Assert.Equal(expected.DataSource.Name, actual.DataSource.Name);
        }
    }
}
