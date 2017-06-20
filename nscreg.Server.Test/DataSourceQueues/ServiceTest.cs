using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataSourceQueues;
using nscreg.Server.Common.Services;
using Xunit;

namespace nscreg.Server.Test.DataSourceQueues
{
    public class ServiceTest
    {
        [Fact]
        private async Task GetAllQueues()
        {
            using ( var ctx = InMemoryDb.CreateContext())
            {
                var dataSource = new DataSource {Name = "TestDS"};
                ctx.DataSources.Add(dataSource);

                var user = new User {Name = "TestUser"};
                ctx.Users.Add(user);

                ctx.DataSourceQueues.AddRange(
                    new DataSourceQueue {DataSourceFileName = "Test1", DataSource = dataSource, User = user}, 
                    new DataSourceQueue {DataSourceFileName = "Test1", DataSource = dataSource, User = user});
                await ctx.SaveChangesAsync();

                var result = await new DataSourceQueuesService(ctx).GetAllDataSourceQueues(new SearchQueryM());

                Assert.Equal(2, result.Result.Count());
            }
            
        }

        [Fact]
        private async Task GetQueuesByStatus()
        {
            using (var ctx = InMemoryDb.CreateContext())
            {
                var query = new SearchQueryM {Status = DataSourceQueueStatuses.DataLoadCompletedPartially};

                var dataSource = new DataSource { Name = "TestDS" };
                ctx.DataSources.Add(dataSource);

                var user = new User { Name = "TestUser" };
                ctx.Users.Add(user);

                ctx.DataSourceQueues.AddRange(
                    new DataSourceQueue { Status = DataSourceQueueStatuses.DataLoadCompletedPartially, DataSource = dataSource, User = user}, 
                    new DataSourceQueue { Status = DataSourceQueueStatuses.InQueue, DataSource = dataSource, User = user});
                await ctx.SaveChangesAsync();

                var result = await new DataSourceQueuesService(ctx).GetAllDataSourceQueues(query);

                Assert.Equal(1, result.Result.Count());
                Assert.Equal((int)DataSourceQueueStatuses.DataLoadCompletedPartially, result.Result.First()?.Status);
            }

        }
    }
}
