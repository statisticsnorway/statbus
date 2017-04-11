using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Helpers;
using nscreg.Utilities.Classes;

namespace nscreg.Server.Classes
{
    internal class LinkInfo
    {
        public StatUnitTypes Type1 { get; set; }
        public StatUnitTypes Type2 { get; set; }

        public object Getter { get; set; }
        public object Setter { get; set; }

        public static LinkInfo Create<TParent, TChild>(Expression<Func<TChild, int?>> property)
            where TParent : class, IStatisticalUnit where TChild : class, IStatisticalUnit
        {
            var data = new GenericDataProperty<TChild, int?>(property);
            return new LinkInfo()
            {
                Type1 = StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(TParent)),
                Type2 = StatisticalUnitsTypeHelper.GetStatUnitMappingType(typeof(TChild)),
                Getter = data.Getter,
                Setter = data.Setter
            };
        }
    }
}
