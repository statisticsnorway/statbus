using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities.ComplexTypes
{
    public class AddressComplexType
    {
        private readonly StatUnitSearchView _statUnit;

        public AddressComplexType(StatUnitSearchView statUnit)
        {
            _statUnit = statUnit;
        }

        public string AddressPart1 => _statUnit.AddressPart1;
        public string AddressPart2 => _statUnit.AddressPart2;
        public string AddressPart3 => _statUnit.AddressPart3;
    }
}
