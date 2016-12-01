using System.Linq;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Models.Roles;
using nscreg.Data.Constants;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RolesService _rolesService;
        private readonly NSCRegDbContext _db;
        private readonly RoleManager<Role> _roleManager;
        private readonly UserManager<User> _userManager;

        public RolesController(NSCRegDbContext db, RoleManager<Role> roleManager, UserManager<User> userManager)
        {
            _rolesService = new RolesService(db);
            _db = db;
            _roleManager = roleManager;
            _userManager = userManager;
        }

        [HttpGet]
        public IActionResult GetAllRoles(
            [FromQuery] int page = 0,
            [FromQuery] int pageSize = 20) => Ok(_rolesService.GetAllPaged(page, pageSize));

        [HttpGet("{id}")]
        public IActionResult GetRoleById(string id) => Ok(_rolesService.GetRoleById(id));

        [HttpGet("{id}/users")]
        public IActionResult GetUsersByRole(string id) => Ok(_rolesService.GetUsersByRole(id));

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            if (await _roleManager.RoleExistsAsync(data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            var role = new Role
            {
                Name = data.Name,
                Description = data.Description,
                AccessToSystemFunctionsArray = data.AccessToSystemFunctions,
                StandardDataAccessArray = data.StandardDataAccess,
                NormalizedName = data.Name.ToUpper()
            };
            if (!(await _roleManager.CreateAsync(role)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, "Error while creating role");
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
            role.AccessToSystemFunctionsArray = data.AccessToSystemFunctions;
            role.StandardDataAccessArray = data.StandardDataAccess;
            role.Description = data.Description;
            if (!(await _roleManager.UpdateAsync(role)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, "Error while creating role");
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
            if (users.Any())
            {
                ModelState.AddModelError(string.Empty, "Can't delete role with existing users");
                return BadRequest(ModelState);
            }
            if (role.Name == DefaultRoleNames.SystemAdministrator)
            {
                ModelState.AddModelError(string.Empty, "Can't delete system administrator role");
                return BadRequest(ModelState);
            }
            var deleteResult = await _roleManager.DeleteAsync(role);
            if (!deleteResult.Succeeded)
            {
                ModelState.AddModelError(string.Empty, "Error while creating role");
                return BadRequest(ModelState);
            }
            return NoContent();
        }
    }
}
