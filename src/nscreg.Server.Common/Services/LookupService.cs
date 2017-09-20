using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис поиска
    /// </summary>
    public class LookupService
    {
        private readonly ReadContext _readCtx;

        public LookupService(NSCRegDbContext dbContext)
        {
            _readCtx = new ReadContext(dbContext);
        }

        /// <summary>
        /// Метод получения объекта поиска
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <returns></returns>
        public async Task<IEnumerable<CodeLookupVm>> GetLookupByEnum(LookupEnum lookup)
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
                    query = _readCtx.Countries.OrderBy(x => x.Name).Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
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

        /// <summary>
        /// Метод получения пагинации поиска объекта
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <param name="searchModel">модель поиска</param>
        /// <returns></returns>
        public async Task<IEnumerable<CodeLookupVm>> GetPaginateLookupByEnum(LookupEnum lookup, SearchLookupModel searchModel)
        {
            IQueryable<object> query;
            Expression<Func<IStatisticalUnit, bool>> searchCriteia = null;
            Expression<Func<CodeLookupBase, bool>> searchCodeLookupCriteia = null;

            if (string.IsNullOrEmpty(searchModel.Wildcard))
            {
                searchCriteia = x => !x.IsDeleted && x.ParentId == null;
                searchCodeLookupCriteia = x => !x.IsDeleted;
            }
            else
            {
                var loweredWc = searchModel.Wildcard.ToLower();

                searchCriteia = x => !x.IsDeleted && x.ParentId == null && !string.IsNullOrEmpty(x.Name) &&
                                     x.Name.ToLower().Contains(loweredWc);

                searchCodeLookupCriteia = x => !x.IsDeleted
                                               && x.Name.ToLower().Contains(loweredWc)
                                               || x.Code.ToLower().Contains(loweredWc);
            }

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
                    query = _readCtx.Countries.OrderBy(x => x.Name).Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
                    break;
                case LookupEnum.LegalFormLookup:
                    query = _readCtx.LegalForms.Where(searchCodeLookupCriteia)
                        .Skip(searchModel.Page * searchModel.PageSize)
                        .Take(searchModel.PageSize);
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _readCtx.SectorCodes.Where(searchCodeLookupCriteia)
                        .Skip(searchModel.Page * searchModel.PageSize)
                        .Take(searchModel.PageSize);
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        }

        /// <summary>
        /// Метод получения объекта поиска по Id
        /// </summary>
        /// <param name="lookup">объекта поиска</param>
        /// <param name="ids">id</param>
        /// <param name="showDeleted">Флаг удалённости</param>
        /// <returns></returns>
        public virtual async Task<IEnumerable<CodeLookupVm>> GetById(LookupEnum lookup, int[] ids, bool showDeleted = false)
        {
            IQueryable<object> query;

            Expression<Func<IStatisticalUnit, bool>> statUnitSearchCriteia = v => ids.Contains(v.RegId) && v.IsDeleted == showDeleted;

            switch (lookup)
            {
                case LookupEnum.LocalUnitLookup:
                    query = _readCtx.LocalUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.LegalUnitLookup:
                    query = _readCtx.LegalUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.EnterpriseUnitLookup:
                    query = _readCtx.EnterpriseUnits.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.EnterpriseGroupLookup:
                    query = _readCtx.EnterpriseGroups.Where(statUnitSearchCriteia);
                    break;
                case LookupEnum.CountryLookup:
                    query = _readCtx.Countries.Where(x => !x.IsDeleted && ids.Contains(x.Id)).OrderBy(x => x.Name).Select(x => new CodeLookupVm { Id = x.Id, Name = $"{x.Name} ({x.Code})" });
                    break;
                case LookupEnum.LegalFormLookup:
                    query = _readCtx.LegalForms.Where(x => !x.IsDeleted && ids.Contains(x.Id));
                    break;
                case LookupEnum.SectorCodeLookup:
                    query = _readCtx.SectorCodes.Where(x => !x.IsDeleted && ids.Contains(x.Id));
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(lookup), lookup, null);
            }
            return await Execute(query);
        } 

        /// <summary>
        /// Метод выполнения поисковых запросов
        /// </summary>
        /// <param name="query"></param>
        /// <returns></returns>
        private static async Task<IEnumerable<CodeLookupVm>> Execute(IQueryable<object> query)
            => Mapper.Map<IEnumerable<CodeLookupVm>>(await query.ToListAsync());

        
    }
}
