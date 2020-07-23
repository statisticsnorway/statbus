using System.Collections.Generic;

namespace nscreg.Data.Entities
{
    public class EnterpriseGroupRole : CodeLookupBase
    {
        public List<EnterpriseUnit> EnterpriseUnits { get; set; }
    }
}
