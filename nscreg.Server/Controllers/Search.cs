using Microsoft.AspNetCore.Mvc;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class SearchController : Controller
    {
        [Route("api/search")]
        public IActionResult Index(object data) => Ok(data);
    }
}
