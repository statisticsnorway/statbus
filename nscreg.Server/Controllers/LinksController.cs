using System;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.Links;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class LinksController : Controller
    {
        private readonly StatUnitService _service;

        public LinksController(NSCRegDbContext context)
        {
            _service = new StatUnitService(context);
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] LinkCreateM model)
        {
            await _service.CreateLink(model);
            return NoContent();
        }

//        [HttpGet]
//        public async Task<IActionResult> List(LinkM model)
//        {
//            throw new NotImplementedException();
//      
//        }

        [HttpDelete]
        public async Task<IActionResult> Delete([FromBody] LinkM model)
        {
            await _service.DeleteLink(model);
            return NoContent();
        }
    }
}
