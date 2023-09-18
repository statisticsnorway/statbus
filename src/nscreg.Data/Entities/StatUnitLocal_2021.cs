using System;

namespace nscreg.Data.Entities
{
    public class StatUnitLocal_2021
    {
        public string StatId { get; set; }

        public int? Oblast { get; set; }

        public int? Rayon { get; set; }

        public string ActCat_section_code { get; set; }

        public string ActCat_section_desc { get; set; }

        public string ActCat_2dig_code { get; set; }

        public string ActCat_2dig_desc { get; set; }

        public string ActCat_3dig_code { get; set; }

        public string ActCat_3dig_desc { get; set; }

        public string LegalForm_code { get; set; }

        public string LegalForm_desc { get; set; }

        public string InstSectorCode_level1 { get; set; }

        public string InstSectorCode_level1_desc { get; set; }

        public string InstSectorCode_level2 { get; set; }

        public string InstSectorCode_level2_desc { get; set; }

        public int? SizeCode { get; set; }

        public string SizeDesc { get; set; }

        public decimal? Turnover { get; set; }

        public int? Employees { get; set; }

        public int? NumOfPeopleEmp { get; set; }

        public DateTimeOffset? RegistrationDate { get; set; }

        public DateTimeOffset? LiqDate { get; set; }

        public string StatusCode { get; set; }

        public string StatusDesc { get; set; }

        public bool? Sex { get; set; }
    }
}
