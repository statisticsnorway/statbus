using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataSourcesQueue;
using System.Threading.Tasks;
using Xunit;
//using static nscreg.Server.Test.Helpers.ServiceFactories;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test.DataSourceQueues
{
    public class ServiceTest
    {
        [Fact]
        private async Task GetAllQueues()
        {
            using (var ctx = CreateDbContext())
            {
                var dataSource = new DataSource {Name = "TestDS"};
                ctx.DataSources.Add(dataSource);

                var user = new User {Name = "TestUser"};
                ctx.Users.Add(user);

                ctx.DataSourceQueues.AddRange(
                    new DataSourceQueue {DataSourceFileName = "Test1", DataSource = dataSource, User = user, DataSourcePath = "TestPath" },
                    new DataSourceQueue {DataSourceFileName = "Test1", DataSource = dataSource, User = user, DataSourcePath = "TestPath" });
                await ctx.SaveChangesAsync();

                //var result = await CreateEmptyConfiguredDataSourceQueueService(ctx)
                //    .GetAllDataSourceQueues(new SearchQueryM());

                //Assert.Equal(2, result.Result.Count());
            }
        }

        [Fact]
        private async Task GetQueuesByStatus()
        {
            using (var ctx = CreateDbContext())
            {
                var query = new SearchQueryM {Status = DataSourceQueueStatuses.DataLoadCompletedPartially};

                var dataSource = new DataSource {Name = "TestDS"};
                ctx.DataSources.Add(dataSource);

                var user = new User {Name = "TestUser"};
                ctx.Users.Add(user);

                ctx.DataSourceQueues.AddRange(
                    new DataSourceQueue
                    {
                        Status = DataSourceQueueStatuses.DataLoadCompletedPartially,
                        DataSource = dataSource,
                        User = user,
                        DataSourceFileName = "TestFileName",
                        DataSourcePath = "TestPath"
                    },
                    new DataSourceQueue
                    {
                        Status = DataSourceQueueStatuses.InQueue,
                        DataSource = dataSource,
                        User = user,
                        DataSourceFileName = "TestFileName",
                        DataSourcePath = "TestPath"
                    });
                await ctx.SaveChangesAsync();

                //var result = await CreateEmptyConfiguredDataSourceQueueService(ctx).GetAllDataSourceQueues(query);

                //Assert.Single(result.Result);
                //Assert.Equal((int) DataSourceQueueStatuses.DataLoadCompletedPartially, result.Result.First()?.Status);
            }
        }
    }
}
