namespace nscreg.Utilities.Configuration.StatUnitAnalysis
{
    /// <summary>
    /// Класс дублирование полей
    /// </summary>
    public class Duplicates
    {
        public bool CheckName{get;set;}
        public bool CheckStatIdTaxRegId{get;set;}
        public bool CheckExternalId{get;set;}
        public bool CheckShortName{get;set;}
        public bool CheckTelephoneNo{get;set;}
        public bool CheckAddressId{get;set;}
        public bool CheckEmailAddress{get;set;}
        public bool CheckContactPerson{get;set;}
        public bool CheckOwnerPerson{get;set;}
        public int MinimalIdenticalFieldsCount { get; set; }
    }
}
