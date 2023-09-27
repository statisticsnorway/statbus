using Newtonsoft.Json;
using nscreg.Data.Constants;
using nscreg.Utilities.Attributes;
using nscreg.Utilities.Enums;
using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity stat. unit
    /// </summary>
    public class History
    {
        public int Id { get; set; }
        public DateOnly StartOn { get; set; }
        public DateOnly? StopOn { get; set; }

        public int? LegalFormId { get; set; }
        public int[] SectorCodeIds { get; set; }
        public int[] RegionIds { get; set; }
        public int[] ActivityCategoryIds { get; set; }
        public int? SizeId { get; set; }

        public int? LocalUnitId { get; set; }
        public int? LegalUnitId { get; set; }
        public int? EnterpriseUnitId { get; set; }
        public int? EnterpriseGroupId { get; set; }
        public string Name { get; set; }
        public string ShortName { get; set; }
        public string TaxRegId { get; set; }
        public string ExternalId { get; set; }
        public string ExternalIdType { get; set; }
        public string DataSource { get; set; }
        public int? AddressId { get; set; }
        public virtual Address Address { get; set; }
        public string WebAddress { get; set; }
        public string TelephoneNo { get; set; }
        public string EmailAddress { get; set; }
        public bool FreeEconZone { get; set; }
        public int? NumOfPeopleEmp { get; set; }
        public int? Employees { get; set; }
        public decimal? Turnover { get; set; }
        public bool? Classified { get; set; }

        public DateTimeOffset? LiqDate { get; set; }
        public string LiqReason { get; set; }

        public virtual ICollection<ActivityLegalUnit> ActivitiesForLegalUnit { get; set; } =
            new HashSet<ActivityLegalUnit>();

        public virtual ICollection<PersonForUnit> PersonsForUnit { get; set; } =
            new HashSet<PersonForUnit>();
        public string UserId { get; set; }
        public ChangeReasons ChangeReason { get; set; }
        public string EditComment { get; set; }
        public int? DataSourceClassificationId { get; set; }
        public int? ReorgTypeId { get; set; }
        public int? UnitStatusId { get; set; }
    }
}
