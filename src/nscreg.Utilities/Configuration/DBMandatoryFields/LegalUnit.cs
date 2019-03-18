namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Правовой единицы с обязательными полями 
    /// </summary>
    public class LegalUnit
    {
        public bool EnterpriseRegId { get; set; }
        public bool EnterpriseRegIdDate { get; set; }
        public bool Market { get; set; }
        public bool LegalFormId { get; set; }
        public bool InstSectorCodeId { get; set; }
        public bool TotalCapital { get; set; }
        public bool MunCapitalShare { get; set; }
        public bool StateCapitalShare { get; set; }
        public bool PrivCapitalShare { get; set; }
        public bool ForeignCapitalShare { get; set; }
        public bool ForeignCapitalCurrency { get; set; }
        public bool TaxRegId { get; set; }
        public bool TaxRegDate { get; set; }
    }
}
