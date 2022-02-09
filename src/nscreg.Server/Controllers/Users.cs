using System.Linq;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.Users;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Extensions;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly UserManager<User> _userManager;
        private readonly IUserService _userService;

        public UsersController(UserManager<User> userManager, IUserService userService)
        {
            _userManager = userManager;
            _userService = userService;
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.UserView, SystemFunctions.RoleView, SystemFunctions.RoleCreate, SystemFunctions.RoleEdit)]
        public async Task<IActionResult> GetAllUsers([FromQuery] UserListFilter filter)
        {
            var users = await _userService.GetAllPagedAsync(filter);
            return Ok(users);
        }

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.UserView)]
        public IActionResult GetUserById(string id) => Ok(_userService.GetUserVmById(id));

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.UserCreate, SystemFunctions.UserEdit)]
        public async Task<IActionResult> IsLoginExist(string login)
        {            
            return Ok(await _userService.IsLoginExist(login));
        }

        [HttpPost]
        [SystemFunction(SystemFunctions.UserCreate)]
        public async Task<IActionResult> CreateUser([FromBody] UserCreateM data)
        {
            if (await _userManager.FindByNameAsync(data.Login) != null)
            {
                ModelState.AddModelError(nameof(data.Login), nameof(Resource.LoginError));
                return BadRequest(ModelState);
            }

            var user = new User
            {
                UserName = data.Login,
                Name = data.Name,
                PhoneNumber = data.Phone,
                Email = data.Email,
                Status = data.Status,
                Description = data.Description,
                DataAccessArray = data.DataAccess.ToStringCollection(),
            };
            var createResult = await _userManager.CreateAsync(user, data.Password);
            if (!createResult.Succeeded)
            {
                createResult.Errors.ForEach(err => ModelState.AddModelError(err.Code, err.Description));
                return BadRequest(ModelState);
            }
            var assignRolesResult = await _userManager.AddToRoleAsync(user, data.AssignedRole);


            if (!assignRolesResult.Succeeded)
            {
                assignRolesResult.Errors.ForEach(err => ModelState.AddModelError(err.Code, err.Description));
                return BadRequest(ModelState);
            }

            await _userService.RelateUserRegionsAsync(user, data);
            await _userService.RelateUserActivityCategoriesAsync(user, data);

            var role = (await _userManager.GetRolesAsync(user)).Single();
            return Created($"api/users/{user.Id}", UserVm.Create(user, role));
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
            if (data.NewPassword.HasValue())
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

            var oldRole = (await _userManager.GetRolesAsync(user)).Single();
            if (oldRole != data.AssignedRole)
            {
                if (!(await _userManager.AddToRoleAsync(user, data.AssignedRole)).Succeeded ||
                    !(await _userManager.RemoveFromRoleAsync(user, oldRole)).Succeeded)
                {
                    ModelState.AddModelError(nameof(data.AssignedRole), nameof(Resource.RoleUpdateError));
                    return BadRequest(ModelState);
                }
            }

            user.Name = data.Name;
            user.Login = data.Login;
            user.Email = data.Email;
            user.PhoneNumber = data.Phone;
            user.Description = data.Description;
            user.DataAccessArray = data.DataAccess.ToStringCollection();
            user.Status = data.Status.Value;

            if (!(await _userManager.UpdateAsync(user)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, nameof(Resource.UserUpdateError));
                return BadRequest(ModelState);
            }

            await _userService.RelateUserRegionsAsync(user, data);
            await _userService.RelateUserActivityCategoriesAsync(user, data);

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
