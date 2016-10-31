using System.Linq;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Server.Models;
using Server.ViewModels;
using System.Threading.Tasks;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly DatabaseContext _context;
        private readonly RoleManager<Role> _roleManager;

        public RolesController(DatabaseContext context, RoleManager<Role> roleManager)
        {
            _context = context;
            _roleManager = roleManager;
        }

        [HttpGet]
        public IActionResult GetAllRoles() => Ok(_context.Roles.Select(RoleVm.Create));

        [HttpGet("{id}")]
        public IActionResult GetRoleById(string id)
        {
            var role = _context.Roles.SingleOrDefault(r => r.Id == id);
            return role != null ? Ok(RoleVm.Create(role)) : (IActionResult)NotFound();
        }

        [HttpPost]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (_roleManager.RoleExistsAsync(data.Name).Result)
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (!_roleManager.CreateAsync(
                new Role { Name = data.Name, Description = data.Description })
                .Result
                .Succeeded)
            {
                ModelState.AddModelError("", "Error while creating role");
                return BadRequest(ModelState);
            }
            var createdRole = _roleManager.FindByNameAsync(data.Name).Result;
            return Created($"api/roles/{createdRole.Id}", RoleVm.Create(createdRole));
        }

        [HttpPut("{id}")]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var role = _roleManager.FindByIdAsync(id).Result;
            if (role == null) return NotFound(data);
            if (role.Name != data.Name && _roleManager.RoleExistsAsync(data.Name).Result)
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            role.Name = data.Name;
            role.Description = data.Description;
            if (!_roleManager.UpdateAsync(role).Result.Succeeded)
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
            if (role.Users.Any()) return BadRequest(new { message = "Can't delete role with existing users" });
            return (await _roleManager.DeleteAsync(role)).Succeeded
                ? (IActionResult)new StatusCodeResult(202)
                : BadRequest(new { message = "Error while creating role" });
        }
    }
}
