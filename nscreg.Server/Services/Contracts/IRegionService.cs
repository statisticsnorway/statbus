using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Models.Regions;

namespace nscreg.Server.Services.Contracts
{
    interface IRegionService
    {
        Task<IList<RegionM>> GetAsync(Expression<Func<Region, bool>> predicate = null, int limit = 5);

        Task<RegionM> GetByCode(string regionCode);
    }
}
