using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.Lookup;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Services
{
    public class LookupService
    {
        private readonly ReadContext _readCtx;

        public LookupService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
        }

        public async Task<IEnumerable<LookupVm>> GetLookupOfNonDeleted(LookupEnum lookup)
        {
            IQueryable<IStatisticalUnit> query;
            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _readCtx.LocalUnits.Where(x => !x.IsDeleted && x.ParrentId == null);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _readCtx.LegalUnits.Where(x => !x.IsDeleted && x.ParrentId == null);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _readCtx.EnterpriseUnits.Where(x => !x.IsDeleted && x.ParrentId == null);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _readCtx.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParrentId == null);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        public async Task<IEnumerable<LookupVm>> GetLookupByType(StatUnitTypes type)
        {
            IQueryable<IStatisticalUnit> query;
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    query = _readCtx.EnterpriseUnits;
                    break;
                case StatUnitTypes.LegalUnit:
                    query = _readCtx.LegalUnits;
                    break;
                case StatUnitTypes.EnterpriseUnit:
                    query = _readCtx.EnterpriseUnits;
                    break;
                case StatUnitTypes.EnterpriseGroup:
                    query = _readCtx.EnterpriseGroups;
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
            return await Execute(query);
        }

        private static async Task<IEnumerable<LookupVm>> Execute(IQueryable<IStatisticalUnit> query)
            => Mapper.Map<IEnumerable<LookupVm>>(await query.ToListAsync());
    }
}
