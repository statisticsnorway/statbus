using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Server.Data;
using Server.Helpers;
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
            => Ok(_context.Users.Where(u => u.Status == UserStatus.Active).Select(u => UserVm.Create(u, _context)));

        [HttpGet("{id}")]
        public IActionResult GetUserById(string id)
        {
            var user = _context.Users.SingleOrDefault(u => u.Status == UserStatus.Active && u.Id == id);
            return user != null ? Ok(UserVm.Create(user, _context)) : (IActionResult) NotFound();
        }

        [HttpPost]
        public async Task<IActionResult> CreateUser([FromBody] UserSubmitM data)
        {
            if (!data.Name.IsPrintable()) ModelState.AddModelError(nameof(data.Name), "User name contains bad characters");
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
            foreach (var roleName in data.AssignedRoles)
            {
                if (await _roleManager.RoleExistsAsync(roleName))
                    await _userManager.AddToRoleAsync(createdUser, roleName);
                else
                    ModelState.AddModelError(nameof(data.AssignedRoles), $"Error assigning role \"{roleName}\"");
            }
            return Created($"api/users/{createdUser.Id}", UserVm.Create(createdUser, _context));
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Edit(string id, [FromBody] UserSubmitM data)
        {
            if (!data.Name.IsPrintable()) ModelState.AddModelError(nameof(data.Name), "User name contains bad characters");
            if (!ModelState.IsValid) return BadRequest(ModelState);
            
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            var user = await _userManager.FindByIdAsync(id);
            if (user == null) return NotFound();
            var adminRole = await _roleManager.FindByNameAsync("ADMIN???");
            if (adminRole.Users.Count == 1 && adminRole.Users.First().RoleId == id)
                return BadRequest(new {message = "Can't delete very last system administrator"});
            user.Status = UserStatus.Suspended;
            return (await _userManager.UpdateAsync(user)).Succeeded
                ? (IActionResult) new StatusCodeResult(202)
                : BadRequest(new {message = "Error while deleting user"});
        }
    }
}
