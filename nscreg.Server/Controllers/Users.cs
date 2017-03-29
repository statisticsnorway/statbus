using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models.Users;
using nscreg.Utilities;
using nscreg.Server.Services;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly UserManager<User> _userManager;
        private readonly UserService _userService;

        public UsersController(NSCRegDbContext context,
            UserManager<User> userManager)
        {
            _userManager = userManager;
            _userService = new UserService(context);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.UserView, SystemFunctions.RoleView, SystemFunctions.RoleCreate, SystemFunctions.RoleEdit)]
        public IActionResult GetAllUsers([FromQuery] UserListFilter filter)
        {
            var users = _userService.GetAllPaged(filter);
            return Ok(users);
        }

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.UserView)]
        public IActionResult GetUserById(string id) => Ok(_userService.GetById(id));

        [HttpPost]
        [SystemFunction(SystemFunctions.UserCreate)]
        public async Task<IActionResult> CreateUser([FromBody] UserCreateM data)
        {
            if (await _userManager.FindByNameAsync(data.Login) != null)
            {
                ModelState.AddModelError(nameof(data.Login), nameof(Resource.LoginError));
                return BadRequest(ModelState);
            }
            var dataAccessArray = data.DataAccess.LegalUnit.Where(x=>x.Allowed).Select(x=>$"{nameof(LegalUnit)}.{x.Name}")
                .Concat(data.DataAccess.LocalUnit.Where(x => x.Allowed).Select(x => $"{nameof(LocalUnit)}.{x.Name}"))
                .Concat(data.DataAccess.EnterpriseGroup.Where(x => x.Allowed).Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}"))
                .Concat(data.DataAccess.EnterpriseUnit.Where(x => x.Allowed).Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"));
            var user = new User
            {
                UserName = data.Login,
                Name = data.Name,
                PhoneNumber = data.Phone,
                Email = data.Email,
                Status = data.Status,
                Description = data.Description,
              
                DataAccessArray = dataAccessArray,
                RegionId = data.RegionId
            };
            var createResult = await _userManager.CreateAsync(user, data.Password);
            if (!createResult.Succeeded)
            {
                createResult.Errors.ForEach(err => ModelState.AddModelError(err.Code, err.Description));
                return BadRequest(ModelState);
            }
            var assignRolesResult = await _userManager.AddToRolesAsync(user, data.AssignedRoles);
            if (!assignRolesResult.Succeeded)
            {
                assignRolesResult.Errors.ForEach(err => ModelState.AddModelError(err.Code, err.Description));
                return BadRequest(ModelState);
            }
            return Created($"api/users/{user.Id}", UserVm.Create(user, await _userManager.GetRolesAsync(user)));
        }

        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.UserEdit)]
        public async Task<IActionResult> Edit(string id, [FromBody] UserEditM data)
        {
            var user = await _userManager.FindByIdAsync(id);
            if (user == null) return NotFound(data);
            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), nameof(Resource.NameError));
                return BadRequest(ModelState);
            }
            if (user.Login != data.Login && (await _userManager.FindByNameAsync(data.Login)) != null)
            {
                ModelState.AddModelError(nameof(data.Login), nameof(Resource.LoginError));
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.NewPassword))
            {
                var removePasswordResult = await _userManager.RemovePasswordAsync(user);
                if (!removePasswordResult.Succeeded)
                {
                    ModelState.AddModelError(nameof(data.NewPassword), nameof(Resource.PasswordUpdateError));
                    removePasswordResult.Errors.ForEach(err =>
                            ModelState.AddModelError(nameof(data.NewPassword), $"Code {err.Code}: {err.Description}"));
                    return BadRequest(ModelState);
                }
                var addPasswordResult = await _userManager.AddPasswordAsync(user, data.NewPassword);
                if (!addPasswordResult.Succeeded)
                {
                    ModelState.AddModelError(nameof(data.NewPassword), nameof(Resource.PasswordUpdateError));
                    addPasswordResult.Errors.ForEach(err =>
                            ModelState.AddModelError(nameof(data.NewPassword), $"Code {err.Code}: {err.Description}"));
                    return BadRequest(ModelState);
                }
            }
            var oldRoles = await _userManager.GetRolesAsync(user);
            if (!(await _userManager.AddToRolesAsync(user, data.AssignedRoles.Except(oldRoles))).Succeeded ||
                !(await _userManager.RemoveFromRolesAsync(user, oldRoles.Except(data.AssignedRoles))).Succeeded)
            {
                ModelState.AddModelError(nameof(data.AssignedRoles), nameof(Resource.RoleUpdateError));
                return BadRequest(ModelState);
            }
            var dataAccessArray = data.DataAccess.LegalUnit.Where(x => x.Allowed).Select(x => $"{nameof(LegalUnit)}.{x.Name}")
               .Concat(data.DataAccess.LocalUnit.Where(x => x.Allowed).Select(x => $"{nameof(LocalUnit)}.{x.Name}"))
               .Concat(data.DataAccess.EnterpriseGroup.Where(x => x.Allowed).Select(x => $"{nameof(EnterpriseGroup)}.{x.Name}"))
               .Concat(data.DataAccess.EnterpriseUnit.Where(x => x.Allowed).Select(x => $"{nameof(EnterpriseUnit)}.{x.Name}"));
            user.Name = data.Name;
            user.Login = data.Login;
            user.Email = data.Email;
            user.PhoneNumber = data.Phone;
            user.Status = data.Status;
            user.Description = data.Description;
          
            user.DataAccessArray = dataAccessArray;
            user.RegionId = data.RegionId;

            if (!(await _userManager.UpdateAsync(user)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, nameof(Resource.UserUpdateError));
                return BadRequest(ModelState);
            }
            return NoContent();
        }

        [HttpDelete("{id}")]
		[SystemFunction(SystemFunctions.UserDelete)]
        public async Task<IActionResult> Delete(string id, bool isSuspend)
        {
            await _userService.SetUserStatus(id, isSuspend);
            return NoContent();
        }
    }
}
