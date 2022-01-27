using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class DataAccessService
    {
        private readonly RoleService _roleService;
        private readonly IUserService _userService;

        public DataAccessService(RoleService roleService, IUserService userService)
        {
            _roleService = roleService;
            _userService = userService;
        }

        public bool CheckWritePermissions(string userId, StatUnitTypes unitType)
        {
            var roleId = _userService.GetUserById(userId).UserRoles.Single().RoleId;
            var role = _roleService.GetRoleById(roleId);
            return role.IsNotAllowedToWrite(unitType);
        }
    }
}
