using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    public class CustomAnalysisCheck
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Query { get; set; }
        public string TargetUnitTypes { get; set; }

    }
}
