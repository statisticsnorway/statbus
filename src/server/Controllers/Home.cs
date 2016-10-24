using Microsoft.AspNetCore.Mvc;

namespace Server.Controllers
{
    public class HomeController : Controller
    {
        public IActionResult Index() => Content("Hey! I'm a HomeController!");
    }
}
