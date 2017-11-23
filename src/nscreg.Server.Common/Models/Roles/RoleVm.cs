using System.Collections.Generic;
using System.Linq;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.DataAccess;
// ReSharper disable MemberCanBePrivate.Global
// ReSharper disable UnusedAutoPropertyAccessor.Global

namespace nscreg.Server.Common.Models.Roles
{
    /// <summary>
    /// Вью модель роли
    /// </summary>
    public class RoleVm
    {
        /// <summary>
        /// Метод создания Вью модели роли
        /// </summary>
        /// <param name="role">Роль</param>
        /// <returns></returns>
        public static RoleVm Create(Role role) => new RoleVm
        {
            Id = role.Id,
            Name = role.Name,
            Description = role.Description,
            AccessToSystemFunctions = role.AccessToSystemFunctionsArray,
            StandardDataAccess = DataAccessModel.FromPermissions(role.StandardDataAccessArray),
            ActiveUsers = role.ActiveUsers,
            Status = role.Status
        };

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Description { get; private set; }
        public IEnumerable<int> AccessToSystemFunctions { get; private set; }
        public DataAccessModel StandardDataAccess { get; private set; }
        public int? ActiveUsers { get; private set; }
        public RoleStatuses Status { get; set; }
    }
}
