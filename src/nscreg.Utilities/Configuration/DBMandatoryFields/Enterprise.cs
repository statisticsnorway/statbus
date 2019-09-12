namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Предприятие с обязательными полями 
    /// </summary>
    public class Enterprise
    {
        public bool EntGroupId { get; set; }
        public bool EntGroupIdDate { get; set; }
        public bool Commercial { get; set; }
        public bool InstSectorCodeId { get; set; }
        public bool TotalCapital { get; set; }
        public bool MunCapitalShare { get; set; }
        public bool StateCapitalShare { get; set; }
        public bool PrivCapitalShare { get; set; }
        public bool ForeignCapitalShare { get; set; }
        public bool ForeignCapitalCurrency { get; set; }
        public bool EntGroupRole { get; set; }
        public bool LegalUnits { get; set; }
    }
}
