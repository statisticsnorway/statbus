using System;
using System.Collections.Generic;
using System.Text;
using nscreg.Data.Entities;

namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class AddressAdapter
    {
        private readonly StatUnitSearchView _statUnit;

        public AddressAdapter(StatUnitSearchView statUnit)
        {
            _statUnit = statUnit;
        }

        public string AddressPart1 => _statUnit.AddressPart1;
        public string AddressPart2 => _statUnit.AddressPart2;
        public string AddressPart3 => _statUnit.AddressPart3;
    }
}
