using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Regions
{
    public class RegionNode
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Code { get; set; }
        public IEnumerable<RegionNode> RegionNodes { get; set; }
    }
}
