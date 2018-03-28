using System.Collections.Generic;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Models.OrgLinks
{
    /// <summary>
    /// Модель узла организационной связи
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
        /// Метод создания модели узла организационной связи
        /// </summary>
        /// <param name="unit">Единица</param>
        /// <param name="children">Потомок</param>
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
