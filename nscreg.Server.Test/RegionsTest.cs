using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Server.Models;
using nscreg.Server.Models.Regions;
using nscreg.Server.Services;
using Xunit;

namespace nscreg.Server.Test
{
    public class RegionsTest
    {
        [Fact]
        public async Task AddAndList()
        {
            using (var context = InMemoryDb.CreateContext())
            {
                var service = new RegionsService(context);
                var regionsSource = new[]
                {
                    new RegionM {Name = "Region A"},
                    new RegionM {Name = "Region B"},
                };

                foreach (var region in regionsSource)
                {
                    await service.CreateAsync(region);
                }

                var regionsList = await service.RegionsPaginatedAsync(new PaginationModel());
                Assert.Equal(2, regionsList.TotalCount);
                var names = new HashSet<string>(regionsList.Result.Select(x => x.Name));
                names.ExceptWith(regionsSource.Select(v => v.Name));
                Assert.Equal(0, names.Count);
            }
        }
    }
}
