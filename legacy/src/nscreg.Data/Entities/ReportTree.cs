using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Data.Entities
{
    public class ReportTree
    {
        public int Id { get; set; }
        public string Title { get; set; }
        public string Type { get; set; }
        public int? ReportId { get; set; }
        public int? ParentNodeId { get; set; }
        public bool IsDeleted { get; set; }
        public string ResourceGroup { get; set; }
        public string ReportUrl { get; set; }

    }
}
