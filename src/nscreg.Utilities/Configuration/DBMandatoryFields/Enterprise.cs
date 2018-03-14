namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Предприятие с обязательными полями 
    /// </summary>
    public class Enterprise
    {
        public bool EnterpriseGroupId { get; set; }
        public bool EnterpriseGroupIdDate { get; set; }
        public bool Commercial { get; set; }
        public bool InstSectorCode { get; set; }
        public bool TotalCapital { get; set; }
        public bool MunCapitalShare { get; set; }
        public bool StateCapitalShare { get; set; }
        public bool PrivCapitalShare { get; set; }
        public bool ForeignCapitalShare { get; set; }
        public bool ForeignCapitalCurrency { get; set; }
        public bool ActualMainActivityDate { get; set; }
        public bool EnterpriseGroupRole { get; set; }
        public bool TaxRegId { get; set; }
        public bool TaxRegDate { get; set; }
    }
}
