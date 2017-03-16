using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class AccessAttributesController : Controller
    {
        private readonly AccessAttributesService _accessAttribSvc;

        public AccessAttributesController(NSCRegDbContext context)
        {
            _accessAttribSvc = new AccessAttributesService(context);
        }
        [HttpGet("[action]")]
        public IActionResult SystemFunctions() => Ok(_accessAttribSvc.GetAllSystemFunctions());
        [HttpGet("[action]")]
        public IActionResult DataAttributes() => Ok(_accessAttribSvc.GetAllDataAccessAttributes());
        //TODO: REMOVE
        [HttpGet("[action]/{userId}")]
        public IActionResult DataAttributesByUser(string userId) => Ok(_accessAttribSvc.GetAllDataAccessAttributesByUser(userId));
        [HttpGet("[action]/{roleId}")]
        public IActionResult DataAttributesByRole(string roleId) => Ok(_accessAttribSvc.GetAllDataAccessAttributesByRole(roleId));
    }
}
