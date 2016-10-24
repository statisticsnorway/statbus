using Microsoft.AspNetCore.Mvc;
using Server.Models;

namespace Server.Controllers
{
    public class UsersController : Controller
    {
        public IActionResult Index() => View(new User { Id = 1, Login = "login", Password = "pwd" });
    }
}
