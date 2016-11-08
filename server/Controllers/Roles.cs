using System.Linq;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using Server.Data;
using Server.Models.Roles;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly DatabaseContext _db;
        private readonly RoleManager<Role> _roleManager;
        private readonly UserManager<User> _userManager;

        public RolesController(DatabaseContext db, RoleManager<Role> roleManager, UserManager<User> userManager)
        {
            _db = db;
            _roleManager = roleManager;
            _userManager = userManager;
        }

        [HttpGet]
        public IActionResult GetAllRoles([FromQuery] int page = 0, [FromQuery] int pageSize = 20)
            => Ok(RolesListVm.Create(_db, page, pageSize));

        [HttpGet("{id}")]
        public IActionResult GetRoleById(string id)
        {
            var role = _db.Roles.SingleOrDefault(r => r.Id == id);
            return role != null ? Ok(RoleVm.Create(role)) : (IActionResult) NotFound();
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (await _roleManager.RoleExistsAsync(data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (!(await _roleManager.CreateAsync(
                new Role {Name = data.Name, Description = data.Description})
                ).Succeeded)
            {
                ModelState.AddModelError("", "Error while creating role");
                return BadRequest(ModelState);
            }
            var createdRole = await _roleManager.FindByNameAsync(data.Name);
            return Created($"api/roles/{createdRole.Id}", RoleVm.Create(createdRole));
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> Edit(string id, [FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var role = await _roleManager.FindByIdAsync(id);
            if (role == null) return NotFound(data);
            if (role.Name != data.Name && await _roleManager.RoleExistsAsync(data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            role.Name = data.Name;
            role.Description = data.Description;
            if (!(await _roleManager.UpdateAsync(role)).Succeeded)
            {
                ModelState.AddModelError("", "Error while creating role");
                return BadRequest(ModelState);
            }
            return NoContent();
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(string id)
        {
            var role = await _roleManager.FindByIdAsync(id);
            if (role == null) return NotFound();
            var users = await _userManager.GetUsersInRoleAsync(role.Name);
            if (users.Any()) return BadRequest(new {message = "Can't delete role with existing users"});
            if (role.Name == DefaultRoleNames.SystemAdministrator)
                return BadRequest(new {message = "Can't delete system administrator role"});
            return (await _roleManager.DeleteAsync(role)).Succeeded
                ? (IActionResult) NoContent()
                : BadRequest(new {message = "Error while creating role"});
        }
    }
}
