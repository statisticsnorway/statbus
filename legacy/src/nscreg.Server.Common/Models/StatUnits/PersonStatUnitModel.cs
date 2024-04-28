using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.StatUnits
{
    public class PersonStatUnitModel
    {
        public int? StatRegId { get; set; }
        public int? GroupRegId { get; set; }
        public string Name { get; set; }
        public string StatId { get; set; }
        public string TelephoneNo { get; set; }
        public string EmailAddress { get; set; }
        public string Address { get; set; }
        public int RoleId { get; set; }
    }
}
