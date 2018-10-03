using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Utilities.Configuration;

namespace nscreg.Data.DbInitializers
{
    public interface IDbInitializer
    {
        void Initialize(NSCRegDbContext context, ReportingSettings reportingSettings = null);
    }
}
