using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Data.Constants;
using nscreg.Server.Models.Users;
using nscreg.Utilities;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly NSCRegDbContext _context;
        private readonly UserManager<User> _userManager;
        private readonly RoleManager<Role> _roleManager;

        public UsersController(NSCRegDbContext context,
            UserManager<User> userManager,
            RoleManager<Role> roleManager)
        {
            _context = context;
            _userManager = userManager;
            _roleManager = roleManager;
        }

        [HttpGet]
        public IActionResult GetAllUsers([FromQuery] int page = 0, [FromQuery] int pageSize = 20,
            [FromQuery] bool showAll = false)
            => Ok(UsersListVm.Create(_context, page, pageSize, showAll));

        [HttpGet("{id}")]
        public async Task<IActionResult> GetUserById(string id)
        {
            var user = await _userManager.FindByIdAsync(id);
            return user != null && user.Status == UserStatuses.Active
                ? Ok(UserVm.Create(user, await _userManager.GetRolesAsync(user)))
                : (IActionResult)NotFound();
        }

        [HttpPost]
        public async Task<IActionResult> CreateUser([FromBody] UserCreateM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (await _userManager.FindByNameAsync(data.Login) != null)
            {
                ModelState.AddModelError(nameof(data.Login), "User name is already taken");
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
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (user.Login != data.Login && (await _userManager.FindByNameAsync(data.Login)) != null)
            {
                ModelState.AddModelError(nameof(data.Login), "Login is already taken");
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.NewPassword))
            {
                var removePasswordResult = await _userManager.RemovePasswordAsync(user);
                if (!removePasswordResult.Succeeded)
                {
                    ModelState.AddModelError(nameof(data.NewPassword), "Error while updating password");
                    removePasswordResult.Errors.ForEach(err =>
                        ModelState.AddModelError(nameof(data.NewPassword), $"Code {err.Code}: {err.Description}"));
                    return BadRequest(ModelState);
                }
                var addPasswordResult = await _userManager.AddPasswordAsync(user, data.NewPassword);
                if (!addPasswordResult.Succeeded)
                {
                    ModelState.AddModelError(nameof(data.NewPassword), "Error while updating password");
                    addPasswordResult.Errors.ForEach(err =>
                        ModelState.AddModelError(nameof(data.NewPassword), $"Code {err.Code}: {err.Description}"));
                    return BadRequest(ModelState);
                }
            }
            var oldRoles = await _userManager.GetRolesAsync(user);
            if (!(await _userManager.AddToRolesAsync(user, data.AssignedRoles.Except(oldRoles))).Succeeded ||
                !(await _userManager.RemoveFromRolesAsync(user, oldRoles.Except(data.AssignedRoles))).Succeeded)
            {
                ModelState.AddModelError(nameof(data.AssignedRoles), "Error while updating roles");
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
                ModelState.AddModelError(string.Empty, "Error while updating user");
                return BadRequest(ModelState);
            }
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            var user = await _userManager.FindByIdAsync(id);
            if (user == null) return NotFound();
            var adminRole = _context.Roles.FirstOrDefault(r => r.Name == DefaultRoleNames.SystemAdministrator);
            if (adminRole == null)
            {
                ModelState.AddModelError(string.Empty, "Can't retrieve system administrator role");
                return BadRequest(ModelState);
            }
            var activeUserIds = _context.Users.Where(u => u.Status == UserStatuses.Active).Select(u => u.Id);
            var activeAdminUserRoles = _context.UserRoles.Where(ur => ur.RoleId == adminRole.Id && activeUserIds.Contains(ur.UserId));
            var isLastAdmin = activeAdminUserRoles.Count() == 1 && activeAdminUserRoles.First().UserId == user.Id;
            if (isLastAdmin)
            {
                ModelState.AddModelError(string.Empty, "Can't delete very last system administrator");
                return BadRequest(ModelState);
            }
            user.Status = UserStatuses.Suspended;
            var deleteResult = await _userManager.UpdateAsync(user);
            if (!deleteResult.Succeeded)
            {
                ModelState.AddModelError(string.Empty, "Error while deleting user");
                return BadRequest(ModelState);
            }
            return NoContent();
        }
    }
}
