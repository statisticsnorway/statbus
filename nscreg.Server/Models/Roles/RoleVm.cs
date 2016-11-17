using nscreg.Data.Entities;
using System.Collections.Generic;

namespace nscreg.Server.Models.Roles
{
    public class RoleVm
    {
        public static RoleVm Create(Role role) => new RoleVm
        {
            Id = role.Id,
            Name = role.Name,
            Description = role.Description,
            AccessToSystemFunctions = role.AccessToSystemFunctionsArray,
            StandardDataAccess = role.StandardDataAccessArray,
        };

        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public IEnumerable<int> AccessToSystemFunctions { get; set; }
        public IEnumerable<int> StandardDataAccess { get; set; }
    }
}
