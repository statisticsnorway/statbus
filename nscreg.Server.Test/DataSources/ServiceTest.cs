using System;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Models.DataSources;
using nscreg.Server.Services;
using nscreg.Utilities.Enums;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test.DataSources
{
    public class ServiceTest
    {
        [Fact]
        private async Task GetAll()
        {
            using (var ctx = CreateDbContext())
            {
                var query = new SearchQueryM {Wildcard = "2"};
                ctx.DataSources.AddRange(new DataSource {Name = "123"}, new DataSource {Name = "234"});
                await ctx.SaveChangesAsync();

                var actual = await new DataSourcesService(ctx).GetAllDataSources(query);

                Assert.Equal(2, actual.Result.Count());
            }
        }

        [Fact]
        private async Task GetAllSortBy()
        {
            using (var ctx = CreateDbContext())
            {
                var query = new SearchQueryM
                {
                    SortBy = nameof(DataSource.Name),
                    OrderBy = OrderRule.Desc.ToString(),
                };
                ctx.DataSources.AddRange(new DataSource { Name = "123" }, new DataSource { Name = "234" });
                await ctx.SaveChangesAsync();

                var actual = await new DataSourcesService(ctx).GetAllDataSources(query);

                Assert.Equal("234", actual.Result.First()?.Name);
            }
        }

        [Fact]
        private async Task Create()
        {
            using (var ctx = CreateDbContext())
            {
                const string name = "123";
                var attribs = new[] {"1", "two"};
                var createM = new CreateM {Name = name, AllowedOperations = 1, AttributesToCheck = attribs};
                Predicate<DataSource> checkNameAndAttribs =
                    x => x.Name.Equals(name) && x.AttributesToCheckArray.SequenceEqual(attribs);

                await new DataSourcesService(ctx).Create(createM);

                Assert.Contains(
                    ctx.DataSources,
                    checkNameAndAttribs
                );
            }
        }
    }
}
