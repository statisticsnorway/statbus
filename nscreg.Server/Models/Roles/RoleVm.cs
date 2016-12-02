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

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Description { get; private set; }
        public IEnumerable<int> AccessToSystemFunctions { get; private set; }
        public IEnumerable<string> StandardDataAccess { get; private set; }
    }
}
