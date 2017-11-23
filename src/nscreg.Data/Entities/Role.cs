using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Newtonsoft.Json;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Класс сущность роль
    /// </summary>
    public class Role : IdentityRole
    {
        public string Description { get; set; }
        public string AccessToSystemFunctions { get; set; }
        public string StandardDataAccess { get; set; }
        public RoleStatuses Status { get; set; }

        [NotMapped]
        public IEnumerable<int> AccessToSystemFunctionsArray
        {
            get
            {
                return string.IsNullOrEmpty(AccessToSystemFunctions)
                    ? new int[0]
                    : AccessToSystemFunctions.Split(',').Select(int.Parse);
            }
            set
            {
                AccessToSystemFunctions = string.Join(",", value);
            }
        }

        [NotMapped]
        public DataAccessPermissions StandardDataAccessArray
        {
            get
            {
                return string.IsNullOrEmpty(StandardDataAccess)
                    ? new DataAccessPermissions()
                    : JsonConvert.DeserializeObject<DataAccessPermissions>(StandardDataAccess);
            }
            set
            {
                StandardDataAccess = JsonConvert.SerializeObject(value);
            }
        }
        [NotMapped]
        public virtual int ActiveUsers { get; set; }
    }
}
