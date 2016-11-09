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
        public IActionResult LogIn(string urlReferrer = null)
        {
            ViewData["RedirectUrl"] = urlReferrer;
            return View("~/Views/LogIn.cshtml");
        }

        [HttpPost, AllowAnonymous]
        public async Task<IActionResult> LogIn([FromForm] LoginVm data)
        {
            if (ModelState.IsValid)
            {
                var signInResult =
                    await _signInManager.PasswordSignInAsync(data.Login, data.Password, data.RememberMe, false);
                if (signInResult.Succeeded)
                    return string.IsNullOrEmpty(data.RedirectUrl) || !Url.IsLocalUrl(data.RedirectUrl)
                        ? RedirectToAction(nameof(HomeController.Index), "Home")
                        : (IActionResult) Redirect(data.RedirectUrl);
            }
            ModelState.AddModelError(string.Empty, "Log in failed");
            ViewData["RedirectUrl"] = data.RedirectUrl;
            return View("~/Views/LogIn.cshtml", data);
        }

        public async Task<IActionResult> LogOut()
        {
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(LogIn));
        }
    }
}
