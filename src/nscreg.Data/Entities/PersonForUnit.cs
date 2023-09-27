using nscreg.Data.Constants;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity person stat. units
    /// </summary>
    public class PersonForUnit
    {
        public int? LocalUnitId { get; set; }
        public virtual LocalUnit LocalUnit { get; set; }
        public int? LegalUnitId { get; set; }
        public virtual LegalUnit LegalUnit { get; set; }
        public int? EnterpriseUnitId { get; set; }
        public virtual EnterpriseUnit EnterpriseUnit { get; set; }
        public int? EnterpriseGroupId { get; set; }
        public virtual EnterpriseGroup EnterpriseGroup { get; set; }

        public int? PersonId { get; set; }
        public virtual Person Person { get; set; }

        public int? PersonTypeId { get; set; }
        public virtual PersonType PersonType { get; set; }
    }
}
