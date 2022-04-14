using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Data.Entities;

namespace nscreg.Data.DbDataProviders
{
    public class MsSqlDbDataProvider : IDbDataProvider
    {
        public async Task<List<ReportTree>> GetReportsTree(NSCRegDbContext context, string sqlWalletUser, IConfiguration config)
        {
            return await context.ReportTree.FromSqlRaw("GetReportsTree @p0", sqlWalletUser).ToListAsync();
        }

        public int[] GetActivityChildren(NSCRegDbContext context, object fieldValue, object fieldValues)
        {
            return context.ActivityCategories.FromSqlRaw("SELECT * FROM [dbo].[GetActivityChildren]({0},{1})", fieldValue, fieldValues).Select(x => x.Id)
                .ToArray();
        }

        public int[] GetRegionChildren(NSCRegDbContext context, object fieldValue)
        {
            return context.Regions.FromSqlRaw("SELECT * FROM [dbo].[GetRegionChildren]({0})", fieldValue).Select(x => x.Id)
                .ToArray();
        }
    }
}
