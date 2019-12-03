using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity person stat. units
    /// </summary>
    public class PersonStatisticalUnit
    {
        public int UnitId { get; set; }
        public virtual StatisticalUnit Unit { get; set; }
        public int? EnterpriseGroupId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        public int? PersonId { get; set; }
        public virtual Person Person { get; set; }

        public int? PersonTypeId { get; set; }
        public virtual PersonType PersonType { get; set; }
    }
}
