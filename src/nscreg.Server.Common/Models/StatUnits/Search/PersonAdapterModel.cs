namespace nscreg.Server.Common.Models.StatUnits.Search
{
    public class PersonAdapterModel
    {
        public PersonAdapterModel(string names)
        {
            ContactPerson = names;
        }

        public string ContactPerson { get; set; }
    }
}
