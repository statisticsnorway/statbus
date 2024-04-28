namespace nscreg.Utilities.Configuration.DBMandatoryFields
{
    /// <summary>
    /// Person class with required fields
    /// </summary>
    public class Person
    {
        public bool IdDate { get; set; }
        public bool PersonalId { get; set; }
        public bool GivenName { get; set; }
        public bool Surname { get; set; }
        public bool BirthDate { get; set; }
        public bool Sex { get; set; }
        public bool Role { get; set; }
        public bool CountryId { get; set; }
        public bool Address { get; set; }
    }
}
