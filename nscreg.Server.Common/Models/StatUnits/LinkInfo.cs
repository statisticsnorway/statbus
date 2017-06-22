using System;
using System.Linq.Expressions;
using nscreg.Data.Constants;
using nscreg.Data.Core;
using nscreg.Data.Entities;
using nscreg.Utilities.Classes;

namespace nscreg.Server.Common.Models.StatUnits
{
    internal class LinkInfo
    {
        public StatUnitTypes Type1 { get; set; }
        public StatUnitTypes Type2 { get; set; }

        public object Getter { get; set; }
        public object Setter { get; set; }

        public object LinkExpression { get; set; }

        public Func<IStatisticalUnit, IStatisticalUnit> Link { get; set; }

        public static LinkInfo Create<TParent, TChild>(
            Expression<Func<TChild, int?>> property,
            Expression<Func<TChild, TParent>> link)
            where TParent : class, IStatisticalUnit
            where TChild : class, IStatisticalUnit
        {
            var key = new GenericDataProperty<TChild, int?>(property);
            var entity = new GenericDataProperty<TChild, TParent>(link);
            return new LinkInfo
            {
                Type1 = StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(TParent)),
                Type2 = StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(TChild)),
                Getter = key.Getter,
                Setter = key.Setter,
                LinkExpression = link,
                Link = unit => entity.Getter((TChild) unit)
            };
        }
    }
}
