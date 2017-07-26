using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Entities;

namespace nscreg.Business.Analysis.StatUnit.Rules
{
    public class ConnectionsManager
    {
        private readonly IStatisticalUnit _unit;

        public ConnectionsManager(IStatisticalUnit unit)
        {
            _unit = unit;
        }

        public (string, string[]) CheckAddress(List<Address> addresses)
        {
            return (!addresses.All(
                a => a.AddressPart1 != _unit.Address.AddressPart1 && a.RegionId != _unit.Address.RegionId))
                ? (null, null)
                : ("Address", new[] {"Stat unit doesn't have related address"});
        }
        
    }
}
