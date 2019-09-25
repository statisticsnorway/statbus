using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using nscreg.Data;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class DataAccessService
    {
        private readonly RoleService _roleService;
        private readonly UserService _userService;

        public DataAccessService(NSCRegDbContext dbContext)
        {
            _roleService = new RoleService(dbContext);
            _userService = new UserService(dbContext);
        }

        public bool CheckWritePermissions(string userId, StatUnitTypes unitType)
        {
            var roleId = _userService.GetUserById(userId).UserRoles.Single().RoleId;
            var role = _roleService.GetRoleById(roleId);
            return role.IsNotAllowedToWrite(unitType);
        }
    }
}
