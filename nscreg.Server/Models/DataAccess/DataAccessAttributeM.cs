using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.DataAccess
{
    public class DataAccessAttributeM
    {
        [Required]
        public string Name { get; set; }
        public string GroupName { get; set; }
        public string LocalizeKey { get; set; }
    }
}
