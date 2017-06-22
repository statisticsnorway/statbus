using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services
{
    public class LookupService
    {
        private readonly ReadContext _readCtx;

        public LookupService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
        }

        public async Task<IEnumerable<LookupVm>> GetLookupByEnum(LookupEnum lookup)
        {
            IQueryable<object> query;
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
                case LookupEnum.CountryLookup:
                    query = _readCtx.Countries.OrderBy(x => x.Name);
                    break;
                case LookupEnum.LegalFormLookup:
                    query = _readCtx.LegalForms.Where(x => !x.IsDeleted);
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _readCtx.SectorCodes.Where(x => !x.IsDeleted);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        public async Task<IEnumerable<LookupVm>> GetStatUnitsLookupByType(StatUnitTypes type)
        {
            IQueryable<object> query;
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

        private static async Task<IEnumerable<LookupVm>> Execute(IQueryable<object> query)
            => Mapper.Map<IEnumerable<LookupVm>>(await query.ToListAsync());
    }
}
