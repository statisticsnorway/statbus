using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccessAttributesController : Controller
    {
        private readonly AccessAttributesService _accessAttribSvc;

        public AccessAttributesController(NSCRegDbContext dbContext)
        {
            _accessAttribSvc = new AccessAttributesService(dbContext);
        }

        public IActionResult SystemFunctions() => Ok(_accessAttribSvc.GetAllSystemFunctions());

        public IActionResult DataAttributes() => Ok(_accessAttribSvc.GetAllDataAttributes());
    }
}
