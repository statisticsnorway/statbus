using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Models.Users;
using nscreg.Utilities;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly NSCRegDbContext _context;
        private readonly RoleManager<Role> _roleManager;
        private readonly UserManager<User> _userManager;
        private readonly UserService _userService;

        public UsersController(NSCRegDbContext context,
            UserManager<User> userManager,
            RoleManager<Role> roleManager)
        {
            _context = context;
            _roleManager = roleManager;
            _userManager = userManager;
            _userService = new UserService(context);
        }

        [HttpGet]
        public IActionResult GetAllUsers(
            [FromQuery] int page = 0,
            [FromQuery] int pageSize = 20)
            => Ok(_userService.GetAllPaged(page, pageSize));

        [HttpGet("{id}")]
        public IActionResult GetUserById(string id) => Ok(_userService.GetById(id));

        [HttpPost]
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
                DataAccessArray = data.DataAccess,
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
            user.Name = data.Name;
            user.Login = data.Login;
            user.Email = data.Email;
            user.PhoneNumber = data.Phone;
            user.Status = data.Status;
            user.Description = data.Description;
            user.DataAccessArray = data.DataAccess;
            if (!(await _userManager.UpdateAsync(user)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, nameof(Resource.UserUpdateError));
                return BadRequest(ModelState);
            }
            return NoContent();
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(string id)
        {
            _userService.Suspend(id);
            return NoContent();
        }
    }
}
