namespace nscreg.Server.Common.Models.DataAccess
{
    /// <summary>
    /// Вью модель аттребута доступа к данным
    /// </summary>
    public class DataAccessAttributeVm : DataAccessAttributeM
    {
        public bool Allowed { get; set; }
        public bool CanRead { get; set; }
        public bool CanWrite { get; set; }
    }
}
