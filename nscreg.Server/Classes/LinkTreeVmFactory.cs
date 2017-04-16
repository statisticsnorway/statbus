using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Models.Lookup;

namespace nscreg.Server.Classes
{
     public class LinkTreeVmFactory
    {
        private readonly Func<IStatisticalUnit, UnitNodeVm> _converter;
        List<UnitNodeVm> _nodes = new List<UnitNodeVm>();
        HashSet<Tuple<int, StatUnitTypes>> _metadata = new HashSet<Tuple<int, StatUnitTypes>>();

        public LinkTreeVmFactory(Func<IStatisticalUnit, UnitNodeVm> converter)
        {
            _converter = converter;
        }

        public List<UnitNodeVm> Execute(IStatisticalUnit unit)
        {
            _nodes.Clear();
            _metadata.Clear();
            ToNodeVm228(unit);
            return _nodes;
        }

        private void ToNodeVm228(IStatisticalUnit unit, UnitNodeVm child = null)
        {
            var key = Tuple.Create(unit.RegId, unit.UnitType);
            if (!_metadata.Add(key))
            {
                return;
            }

            {
                var u = unit as EnterpriseUnit;
                if (u != null)
                {
                    if (u.EnterpriseGroup == null)
                    {
                        _nodes.Add(_converter(unit));
                    }
                    ToNodeVm228(u.EnterpriseGroup, _converter(u));
                    return;
                }
            }

            {
                var u = unit as EnterpriseGroup;
                if (u != null)
                {


                    //ToNodeVm228(u.EnterpriseGroup, u);
                    return;
                }
            }

            throw new NotImplementedException();
        }
    }
}
