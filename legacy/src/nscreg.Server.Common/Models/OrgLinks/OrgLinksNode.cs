using System.Collections.Generic;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Models.OrgLinks
{
    /// <summary>
    /// Organization Communications Node Model
    /// </summary>
    public class OrgLinksNode
    {
        private OrgLinksNode(StatisticalUnit unit, IEnumerable<OrgLinksNode> children)
        {
            RegId = unit.RegId;
            Name = unit.Name;
            ParentOrgLink = unit.ParentOrgLink;
            OrgLinksNodes = children;
        }

        /// <summary>
        /// Method for creating a model of an organizational link node
        /// </summary>
        /// <param name="unit">unit</param>
        /// <param name="children">children</param>
        /// <returns></returns>
        public static OrgLinksNode Create(StatisticalUnit unit, IEnumerable<OrgLinksNode> children)
        {
            return unit != null ? new OrgLinksNode(unit, children) : throw new NotFoundException(nameof(Resource.OrgLinksNotFound));
        }

        public int RegId { get; }
        public string Name { get; }
        public int? ParentOrgLink { get; }
        public IEnumerable<OrgLinksNode> OrgLinksNodes { get; }
    }
}
