using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.DataAccess
{
    public class DataAccessAttributeM
    {
        /// <summary>
        /// Модель аттребута доступа к данным
        /// </summary>
        [Required]
        public string Name { get; set; }
        public string GroupName { get; set; }
        public string LocalizeKey { get; set; }
    }
}
