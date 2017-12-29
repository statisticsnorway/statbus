namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Класс Персоны с обязательными полями 
    /// </summary>
    public class Person
    {
        public bool Id { get; set; }
        public bool IdDate { get; set; }
        public bool PersonalId { get; set; }
        public bool UnitId { get; set; }
        public bool GivenName { get; set; }
        public bool Surname { get; set; }
        public bool MiddleName { get; set; }
        public bool BirthDate { get; set; }
        public bool Sex { get; set; }
        public bool Role { get; set; }
        public bool NationalityCode { get; set; }
        public bool Telephone1 { get; set; }
        public bool Telephone2 { get; set; }
        public bool Address { get; set; }
    }
}
