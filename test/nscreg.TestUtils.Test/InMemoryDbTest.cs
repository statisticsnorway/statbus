using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using Xunit;
using static nscreg.TestUtils.InMemoryDb;

namespace nscreg.TestUtils.Test
{
    public class InMemoryDbTest
    {
        [Fact]
        private async Task DataIsNotPersistedAfterDisposeTest()
        {
            int countBefore, countAfter;

            using (var ctx = CreateDbContext())
            {
                await ctx.Regions.AddAsync(new Region {Name = "123", Code = "TestCode"});
                await ctx.SaveChangesAsync();
                countBefore = ctx.Regions.Count();
            }

            using (var ctx = CreateDbContext())
            {
                countAfter = ctx.Regions.Count();
            }

            Assert.NotEqual(countBefore, countAfter);
            Assert.Equal(1, countBefore);
            Assert.Equal(0, countAfter);
        }
    }
}
