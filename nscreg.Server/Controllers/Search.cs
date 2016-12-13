using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class Search : Controller
    {
        private readonly StatUnitSearchService _searchSvc;

        public Search(NSCRegDbContext dbContext)
        {
            _searchSvc = new StatUnitSearchService(dbContext);
        }

        [HttpGet]
        public IActionResult Index([FromQuery] SearchQueryM query)
            => Ok(_searchSvc.Search(query,
                User.FindFirst(CustomClaimTypes.DataAccessAttributes).Value.Split(',')));
    }
}
