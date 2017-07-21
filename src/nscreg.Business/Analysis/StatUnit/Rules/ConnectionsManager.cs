
using System;
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

        public void CheckAddress(List<Address> addresses, ref string key, ref string[] value)
        {
            if (!addresses.All(
                a => a.AddressPart1 != _unit.Address.AddressPart1 && a.RegionId != _unit.Address.RegionId)) return;
            key = "Address";
            value = new[] { "Stat unit doesn't have related address" };
        }
        
    }
}
