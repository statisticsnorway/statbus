using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
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
                    query = _readCtx.LocalUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _readCtx.LegalUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _readCtx.EnterpriseUnits.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _readCtx.EnterpriseGroups.Where(x => !x.IsDeleted && x.ParentId == null);
                    break;
                case LookupEnum.CountryLookup:
                    query = _readCtx.Countries.OrderBy(x => x.Name).Select(x => new LookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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

        public async Task<IEnumerable<LookupVm>> GetPaginateLookupByEnum(LookupEnum lookup, SearchLookupModel searchModel)
        {
            IQueryable<object> query;
            Expression<Func<IStatisticalUnit, bool>> searchCriteia = null;

            if (string.IsNullOrEmpty(searchModel.Wildcard))
                searchCriteia = x => !x.IsDeleted && x.ParentId == null;
            else
                searchCriteia = x => !x.IsDeleted && x.ParentId == null && !string.IsNullOrEmpty(x.Name) &&
                                     x.Name.ToLower().Contains(searchModel.Wildcard.ToLower());

            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _readCtx.LocalUnits.Where(searchCriteia).Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _readCtx.LegalUnits.Where(searchCriteia).Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _readCtx.EnterpriseUnits.Where(searchCriteia).Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _readCtx.EnterpriseGroups.Where(searchCriteia).Skip(searchModel.Page * searchModel.PageSize).Take(searchModel.PageSize);
                    break;
                case LookupEnum.CountryLookup:
                    query = _readCtx.Countries.OrderBy(x => x.Name).Select(x => new LookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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
