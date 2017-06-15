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
using nscreg.Data.Helpers;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Services.StatUnit
{
    internal static class Common
    {
        public static readonly Expression<Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>>> UnitMapping =
            u => Tuple.Create(
                new CodeLookupVm {Id = u.RegId, Code = u.StatId, Name = u.Name},
                u.GetType());

        public static readonly Func<IStatisticalUnit, Tuple<CodeLookupVm, Type>> UnitMappingFunc =
            UnitMapping.Compile();

        public static async Task<IStatisticalUnit> GetStatisticalUnitByIdAndType(
            NSCRegDbContext dbContext,
            int id,
            StatUnitTypes type,
            bool showDeleted)
        {
            switch (type)
            {
                case StatUnitTypes.LocalUnit:
                    return await GetUnitById<StatisticalUnit>(
                        dbContext,
                        id,
                        showDeleted,
                        query => query
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .Include(v => v.ActualAddress)
                    );
                case StatUnitTypes.LegalUnit:
                    return await GetUnitById<LegalUnit>(
                        dbContext,
                        id,
                        showDeleted,
                        query => query
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .Include(v => v.ActualAddress)
                            .Include(v => v.LocalUnits)
                    );
                case StatUnitTypes.EnterpriseUnit:
                    return await GetUnitById<EnterpriseUnit>(
                        dbContext,
                        id,
                        showDeleted,
                        query => query
                            .Include(x => x.LocalUnits)
                            .Include(x => x.LegalUnits)
                            .Include(v => v.ActivitiesUnits)
                            .ThenInclude(v => v.Activity)
                            .ThenInclude(v => v.ActivityRevxCategory)
                            .Include(v => v.Address)
                            .Include(v => v.ActualAddress));
                case StatUnitTypes.EnterpriseGroup:
                    return await GetUnitById<EnterpriseGroup>(
                        dbContext,
                        id,
                        showDeleted,
                        query => query
                            .Include(x => x.LegalUnits)
                            .Include(x => x.EnterpriseUnits)
                            .Include(v => v.Address)
                            .Include(v => v.ActualAddress));
                default:
                    throw new ArgumentOutOfRangeException(nameof(type), type, null);
            }
        }

        public static IQueryable<T> GetUnitsList<T>(
            NSCRegDbContext dbContext,
            bool showDeleted)
            where T : class, IStatisticalUnit
        {
            var query = dbContext.Set<T>().Where(unit => unit.ParrentId == null);
            if (!showDeleted) query = query.Where(v => !v.IsDeleted);
            return query;
        }

        public static async Task<T> GetUnitById<T>(
            NSCRegDbContext dbContext,
            int id,
            bool showDeleted,
            Func<IQueryable<T>, IQueryable<T>> work = null)
            where T : class, IStatisticalUnit
        {
            var query = GetUnitsList<T>(dbContext, showDeleted);
            if (work != null)
            {
                query = work(query);
            }
            return await query.SingleAsync(v => v.RegId == id);
        }

        public static IStatisticalUnit TrackHistory(IStatisticalUnit unit, IStatisticalUnit hUnit)
        {
            var timeStamp = DateTime.Now;
            unit.StartPeriod = timeStamp;
            hUnit.RegId = 0;
            hUnit.EndPeriod = timeStamp;
            hUnit.ParrentId = unit.RegId;
            return hUnit;
        }

        public static T ToUnitLookupVm<T>(IStatisticalUnit unit) where T : UnitLookupVm, new()
            => ToUnitLookupVm<T>(UnitMappingFunc(unit));

        public static IEnumerable<UnitLookupVm> ToUnitLookupVm(IEnumerable<Tuple<CodeLookupVm, Type>> source)
            => source.Select(ToUnitLookupVm<UnitLookupVm>);

        private static T ToUnitLookupVm<T>(Tuple<CodeLookupVm, Type> unit) where T : UnitLookupVm, new()
        {
            var vm = new T
            {
                Type = StatisticalUnitsTypeHelper.GetStatUnitMappingType(unit.Item2)
            };
            Mapper.Map<CodeLookupVm, UnitLookupVm>(unit.Item1, vm);
            return vm;
        }
    }
}
