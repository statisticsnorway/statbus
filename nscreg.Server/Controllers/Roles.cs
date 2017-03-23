using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Core.Authorize;
using nscreg.Server.Models.Roles;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly RoleService _roleService;

        public RolesController(NSCRegDbContext db)
        {
            _roleService = new RoleService(db);
        }

        [HttpGet]
        [SystemFunction(SystemFunctions.RoleView, SystemFunctions.UserEdit, SystemFunctions.UserCreate, SystemFunctions.UserView)]
        public IActionResult GetAllRoles(
                [FromQuery] int page = 0,
                [FromQuery] int pageSize = 20)
            => Ok(_roleService.GetAllPaged(page, pageSize));

        [HttpGet("{id}")]
        [SystemFunction(SystemFunctions.RoleView)]
        public IActionResult GetRoleById(string id) => Ok(_roleService.GetRoleById(id));

        [HttpPost]
        [SystemFunction(SystemFunctions.RoleCreate)]
        public IActionResult Create([FromBody] RoleSubmitM data)
        {
            var createdRoleVm = _roleService.Create(data);
            return Created($"api/roles/{createdRoleVm.Id}", createdRoleVm);
        }

        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.RoleEdit)]
        public IActionResult Edit(string id, [FromBody] RoleSubmitM data)
        {
            _roleService.Edit(id, data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.RoleDelete)]
        public IActionResult Delete(string id)
        {
            _roleService.Suspend(id);
            return NoContent();
        }
    }
}
