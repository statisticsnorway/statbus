namespace nscreg.Server.Common.Models.DataAccess
{
    /// <summary>
    /// View data access attrebut model
    /// </summary>
    public class DataAccessAttributeVm : DataAccessAttributeM
    {
        public bool Allowed { get; set; }
        public bool CanRead { get; set; }
        public bool CanWrite { get; set; }
    }
}
