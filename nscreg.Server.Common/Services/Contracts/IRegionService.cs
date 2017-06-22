using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.Regions;

namespace nscreg.Server.Common.Services.Contracts
{
    interface IRegionService
    {
        Task<IList<RegionM>> GetAsync(Expression<Func<Region, bool>> predicate = null, int limit = 5);

        Task<RegionM> GetByCode(string regionCode);
    }
}
