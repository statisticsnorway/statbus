using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Data.Entities;

namespace nscreg.Data.DbDataProviders
{
    public class MySqlDataProvider : IDbDataProvider
    {
        public async Task<List<ReportTree>> GetReportsTree(NSCRegDbContext context, string sqlWalletUser, IConfiguration config)
        {
            var sqlWalletProvider = new SqlWalletDataProvider();
            return await sqlWalletProvider.GetReportsTree(context, sqlWalletUser, config);
        }

        public int[] GetActivityChildren(NSCRegDbContext context, object fieldValue)
        {
            return context.ActivityCategories.FromSql("CALL GetActivityChildren({0})", fieldValue).Select(x => x.Id)
                .ToArray();
        }

        public int[] GetRegionChildren(NSCRegDbContext context, object fieldValue)
        {
            return context.Regions.FromSql("CALL GetRegionChildren({0})", fieldValue).Select(x => x.Id)
                .ToArray();
        }
    }
}
