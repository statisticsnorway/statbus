using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.Roles;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RolesService _rolesService;

        public RolesController(NSCRegDbContext db)
        {
            _rolesService = new RolesService(db);
        }

        [HttpGet]
        public IActionResult GetAllRoles(
            [FromQuery] int page = 0,
            [FromQuery] int pageSize = 20)
            => Ok(_rolesService.GetAllPaged(page, pageSize));

        [HttpGet("{id}")]
        public IActionResult GetRoleById(string id) => Ok(_rolesService.GetRoleById(id));

        [HttpGet("{id}/users")]
        public IActionResult GetUsersByRole(string id) => Ok(_rolesService.GetUsersByRole(id));

        [HttpPost]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var createdRoleVm = _rolesService.Create(data);
            return Created($"api/roles/{createdRoleVm.Id}", createdRoleVm);
        }

        [HttpPut("{id}")]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            _rolesService.Edit(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public IActionResult Delete(string id)
        {
            _rolesService.Suspend(id);
            return NoContent();
        }
    }
}
