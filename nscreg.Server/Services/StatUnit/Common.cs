using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using AutoMapper;
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
