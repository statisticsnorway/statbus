using Newtonsoft.Json;
using nscreg.Data.Constants;
using nscreg.Data.Entities.ComplexTypes;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations.Schema;
using System.Linq;
using Microsoft.AspNetCore.Identity;

namespace nscreg.Data.Entities
{
    /// <summary>
    ///  Class entity role
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
        public string SqlWalletUser { get; set; }

        public bool IsNotAllowedToWrite(StatUnitTypes unitType)
        {
            var permissions =
                StandardDataAccessArray.Permissions.Where(x => x.PropertyName.Split('.')[0] == unitType.ToString());
            return permissions.All(x => x.CanWrite == false);
        }
        public virtual ICollection<UserRole> UserRoles { get; set; }
    }
}
