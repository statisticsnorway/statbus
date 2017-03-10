namespace nscreg.Server.Models.DataAccess
{
    public class DataAccessAttributeModel
    {
        public DataAccessAttributeModel(string name)
        {
            Name = name;
        }

        public DataAccessAttributeModel(string name, bool allowed)
        {
            Name = name;
            Allowed = allowed;
        }

        public DataAccessAttributeModel()
        {
        }

        public string Name { get; set; }
        public bool Allowed { get; set; }
    }
}