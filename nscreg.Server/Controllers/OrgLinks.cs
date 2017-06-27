using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.Links;
using nscreg.Server.Common.Services.StatUnit;
using nscreg.Server.Core.Authorize;


namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class OrgLinksController : Controller
    {
        private readonly OrgLinkService _service;

        public OrgLinksController(NSCRegDbContext context)
        {
            _service = new OrgLinkService(context);
        }

        [HttpGet("[action]")]
        [SystemFunction(SystemFunctions.OrgLinksView)]
        public async Task<IActionResult> GetAllOrgLinks([FromQuery] LinkSearchM model)
        => Ok(await _service.GetAllOrgLinks(model));

    }
}
