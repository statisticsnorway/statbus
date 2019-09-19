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
        public bool GivenName { get; set; }
        public bool Surname { get; set; }
        public bool MiddleName { get; set; }
        public bool BirthDate { get; set; }
        public bool Sex { get; set; }
        public bool Role { get; set; }
        public bool CountryId { get; set; }
        public bool PhoneNumber { get; set; }
        public bool PhoneNumber1 { get; set; }
        public bool Address { get; set; }
    }
}
