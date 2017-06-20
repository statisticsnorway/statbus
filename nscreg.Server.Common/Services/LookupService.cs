using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
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

        public async Task<List<LookupVm>> GetLookup(LookupEnum lookup)
        {
            List<LookupVm> result = null;
            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.LocalUnits.Where(x => !x.IsDeleted && x.ParrentId == null).ToListAsync());
                    break;
                case LookupEnum.LegalUnitLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.LegalUnits.Where(x => !x.IsDeleted && x.ParrentId == null).ToListAsync());
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.EnterpriseUnits.Where(x => !x.IsDeleted && x.ParrentId == null).ToListAsync());
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParrentId == null).ToListAsync());
                    break;
                case LookupEnum.CountryLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.Countries.OrderBy(x=> x.Name).ToListAsync());
                    break;
                case LookupEnum.LegalFormLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.LegalForms.Where(x => !x.IsDeleted).ToListAsync());
                    break;
                case LookupEnum.SectorCodeLookup:
                    result = Mapper.Map<List<LookupVm>>(await _readCtx.SectorCodes.Where(x => !x.IsDeleted).ToListAsync());
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return result;
        }
    }
}
