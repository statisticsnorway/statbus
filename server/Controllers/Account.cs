using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using System.Threading.Tasks;
using Server.Data;
using Server.Models;

namespace Server.Controllers
{
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
        public IActionResult LogIn(string urlRefferer) => View();

        // TODO: collect and return errors
        [HttpPost, ValidateAntiForgeryToken, AllowAnonymous]
        public async Task<IActionResult> LogIn(LoginViewModel data)
            => ModelState.IsValid &&
                (await _signInManager.PasswordSignInAsync(data.Login, data.Password, data.RememberMe, false)).Succeeded
                    ? RedirectToAction("Home", "Index")
                    : (IActionResult) Redirect(Request.Headers["Referer"].ToString());

        [Authorize]
        public async Task<IActionResult> LogOut()
        {
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(LogIn));
        }
    }
}
