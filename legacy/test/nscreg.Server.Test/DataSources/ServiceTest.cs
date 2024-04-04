using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataSources;
using nscreg.Server.Common.Services;
using nscreg.Utilities.Enums;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.Server.Test.DataSources
{
    public class ServiceTest
    {
        private User _user;
        public ServiceTest()
        {
            _user = new User { Name = "TestUser" };
        }


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
        private async Task GetById()
        {
            var expected = new DataSource {Name = "ewq321"};
            DataSourceEditVm actual;

            using (var ctx = CreateDbContext())
            {
                ctx.DataSources.Add(expected);
                await ctx.SaveChangesAsync();

                actual = await new DataSourcesService(ctx).GetById(expected.Id);
            }

            Assert.Equal(expected.Name, actual.Name);
        }

        [Fact]
        private async Task Create()
        {
            using (var ctx = CreateDbContext())
            {
                const string name = "123";
                var attribs = new[] {"1", "two"};
                var createM = new SubmitM {Name = name, AllowedOperations = 1, AttributesToCheck = attribs};

                bool CheckNameAndAttribs(DataSource x) => x.Name.Equals(name) &&
                                                          x.AttributesToCheckArray.SequenceEqual(attribs);

                await new DataSourcesService(ctx).Create(createM, _user.Id);

                Assert.Contains(
                    ctx.DataSources,
                    CheckNameAndAttribs
                );
            }
        }

        [Fact]
        private async Task Edit()
        {
            var entity = new DataSource {Name = "123"};
            var model = new SubmitM {Name = "321"};
            DataSource actual;

            using (var ctx = CreateDbContext())
            {
                ctx.DataSources.Add(entity);
                await ctx.SaveChangesAsync();

                await new DataSourcesService(ctx).Edit(entity.Id, model, _user.Id);
                actual = await ctx.DataSources.FindAsync(entity.Id);
            }

            Assert.Equal(model.Name, actual.Name);
        }

        [Fact]
        private async Task Delete()
        {
            var entity = new DataSource {Name = "123"};
            DataSource actual;

            using (var ctx = CreateDbContext())
            {
                ctx.DataSources.Add(entity);
                await ctx.SaveChangesAsync();

                await new DataSourcesService(ctx).Delete(entity.Id);
                actual = await ctx.DataSources.FindAsync(entity.Id);
            }

            Assert.Null(actual);
        }

        [Fact]
        private void MappingPropertiesContainsCommonAndSpecificAttributes()
        {
            var actual = DataAccessAttributesProvider<LocalUnit>.Attributes.Concat(
                    DataAccessAttributesProvider<LegalUnit>.Attributes).Concat(
                    DataAccessAttributesProvider<EnterpriseUnit>.Attributes).Concat(
                    DataAccessAttributesProvider<EnterpriseGroup>.Attributes).Concat(
                    DataAccessAttributesProvider.CommonAttributes)
                .Select(x => x.Name.Split('.')[1])
                .ToArray();

            Assert.Equal(4, actual.Count(x => x == nameof(IStatisticalUnit.Name)));
            Assert.Equal(1, actual.Count(x => x == nameof(EnterpriseUnit.EntGroupId)));
            Assert.Equal(2, actual.Count(x => x == nameof(LegalUnit.ForeignCapitalCurrency)));
            Assert.Equal(4, actual.Count(x => x == nameof(EnterpriseGroup.NumOfPeopleEmp)));
        }
    }
}
