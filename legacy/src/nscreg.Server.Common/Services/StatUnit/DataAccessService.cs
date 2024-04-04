using System.Linq;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Services.StatUnit
{
    public class DataAccessService
    {
        private readonly RoleService _roleService;
        private readonly UserService _userService;
        private readonly IMapper _mapper;

        public DataAccessService(NSCRegDbContext dbContext, IMapper mapper)
        {
            _mapper = mapper;
            _roleService = new RoleService(dbContext);
            _userService = new UserService(dbContext, _mapper);
        }

        public bool CheckWritePermissions(string userId, StatUnitTypes unitType)
        {
            var roleId = _userService.GetUserById(userId).UserRoles.Single().RoleId;
            var role = _roleService.GetRoleById(roleId);
            return role.IsNotAllowedToWrite(unitType);
        }
    }
}
