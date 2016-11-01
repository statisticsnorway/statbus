using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Server.Data;
using Server.Models.Users;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly DatabaseContext _context;
        private readonly UserManager<User> _userManager;
        private readonly RoleManager<Role> _roleManager;

        public UsersController(DatabaseContext context,
            UserManager<User> userManager,
            RoleManager<Role> roleManager)
        {
            _context = context;
            _userManager = userManager;
            _roleManager = roleManager;
        }

        [HttpGet]
        public IActionResult GetAllUsers()
            => Ok(_context.Users.Where(u => u.Status == UserStatuses.Active).Select(u => UserVm.Create(u, _context)));

        [HttpGet("{id}")]
        public IActionResult GetUserById(string id)
        {
            var user = _context.Users.SingleOrDefault(u => u.Status == UserStatuses.Active && u.Id == id);
            return user != null ? Ok(UserVm.Create(user, _context)) : (IActionResult) NotFound();
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
            var createResult = await _userManager.CreateAsync(
                new User
                {
                    UserName = data.Login,
                    Description = data.Description
                },
                data.Password);
            if (!createResult.Succeeded)
            {
                ModelState.AddModelError("", "Error while creating user");
                return BadRequest(ModelState);
            }
            var createdUser = _userManager.FindByNameAsync(data.Login).Result;
            await _userManager.AddToRolesAsync(createdUser, data.AssignedRoles);
            return Created($"api/users/{createdUser.Id}", UserVm.Create(createdUser, _context));
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Edit(string id, [FromBody] UserEditM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var user = await _userManager.FindByIdAsync(id);
            if (user == null) return NotFound(data);
            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (user.Login != data.Login && (await _userManager.FindByNameAsync(data.Login)) != null)
            {
                ModelState.AddModelError(nameof(data.Login), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (await _userManager.CheckPasswordAsync(user, data.CurrentPassword))
            {
                ModelState.AddModelError(nameof(data.CurrentPassword), "Current password is wrong");
                return BadRequest(ModelState);
            }
            if (!(await _userManager.ChangePasswordAsync(user, data.CurrentPassword, data.NewPassword)).Succeeded)
            {
                ModelState.AddModelError(nameof(data.NewPassword), "Error while updating password");
                ModelState.AddModelError(nameof(data.ConfirmPassword), "Error while updating password");
                return BadRequest(ModelState);
            }
            if (!(await _userManager.AddToRolesAsync(user, data.AssignedRoles)).Succeeded ||
                !(await _userManager.RemoveFromRolesAsync(user,
                _context.Roles.Where(r => data.AssignedRoles.All(ar => r.Name != ar)).Select(r => r.Name))
                ).Succeeded)
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
            if (!(await _userManager.UpdateAsync(user)).Succeeded)
            {
                ModelState.AddModelError("", "Error while updating user");
                return BadRequest(ModelState);
            }
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            var user = await _userManager.FindByIdAsync(id);
            if (user == null) return NotFound();
            var adminRole = await _roleManager.FindByNameAsync(DefaultRoleNames.SystemAdministrator);
            if (adminRole.Users.Count == 1 && adminRole.Users.First().RoleId == id)
                return BadRequest(new {message = "Can't delete very last system administrator"});
            user.Status = UserStatuses.Suspended;
            return (await _userManager.UpdateAsync(user)).Succeeded
                ? (IActionResult) new StatusCodeResult(202)
                : BadRequest(new {message = "Error while deleting user"});
        }
    }
}
