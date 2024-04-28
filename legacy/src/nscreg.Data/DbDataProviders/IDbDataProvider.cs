using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using nscreg.Data.Entities;

namespace nscreg.Data.DbDataProviders
{
    public interface IDbDataProvider
    {
        Task<List<ReportTree>> GetReportsTree(NSCRegDbContext context, string sqlWalletUser, IConfiguration config);
        int[] GetActivityChildren(NSCRegDbContext context, object fieldValue, object fieldValues);
        int[] GetRegionChildren(NSCRegDbContext context, object fieldValue);
    }
}
