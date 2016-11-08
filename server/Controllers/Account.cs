using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using System.Threading.Tasks;
using Server.Data;
using Server.Models;

namespace Server.Controllers
{
    [Route("[controller]/[action]")]
    public class AccountController : Controller
    {
        private readonly SignInManager<User> _signInManager;
        private readonly ILogger _logger;

        public AccountController(SignInManager<User> signInManager, ILoggerFactory loggerFactory)
        {
            _signInManager = signInManager;
            _logger = loggerFactory.CreateLogger<AccountController>();
        }

        [AllowAnonymous]
        public IActionResult LogIn(string urlRefferer = null)
        {
            ViewData["RedirectUrl"] = urlRefferer;
            return View("~/Views/LogIn.cshtml");
        }

        [HttpPost, AllowAnonymous, ValidateAntiForgeryToken]
        public async Task<IActionResult> LogIn([FromBody] LoginVm data, [FromQuery] string redirectUrl = null)
        {
            if (ModelState.IsValid)
                if ((await _signInManager.PasswordSignInAsync(data.Login, data.Password, data.RememberMe, false)).Succeeded)
                    return string.IsNullOrEmpty(redirectUrl) || !Url.IsLocalUrl(redirectUrl)
                        ? RedirectToAction(nameof(HomeController.Index), "Home")
                        : (IActionResult)Redirect(redirectUrl);
            ModelState.AddModelError(string.Empty, "Log in failed");
            ViewData["RedirectUrl"] = redirectUrl;
            return View("~/Views/LogIn.cshtml", data);
        }

        [Authorize]
        public async Task<IActionResult> LogOut()
        {
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(LogIn));
        }
    }
}
