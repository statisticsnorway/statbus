using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Models.Account;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccountController : Controller
    {
        private readonly SignInManager<User> _signInManager;
        private readonly UserManager<User> _userManager;
        private readonly ILogger<AccountController> _logger;

        public AccountController(
            SignInManager<User> signInManager,
            UserManager<User> userManager,
            ILogger<AccountController> logger)
        {
            _signInManager = signInManager;
            _userManager = userManager;
            _logger = logger;
        }

        [AllowAnonymous, Route("/account/login")]
        public IActionResult LogIn(string urlReferrer = null)
        {
            ViewData["RedirectUrl"] = urlReferrer;
            return View("~/Views/LogIn.cshtml");
        }

        [HttpPost, AllowAnonymous, Route("/account/login")]
        public async Task<IActionResult> LogIn([FromForm] LoginVm data)
        {
            var user = await _userManager.FindByNameAsync(data.Login);
            if (user != null)
            {
                var signInResult = await _signInManager.PasswordSignInAsync(
                    user,
                    data.Password,
                    data.RememberMe,
                    false);
                if (signInResult.Succeeded)
                    return string.IsNullOrEmpty(data.RedirectUrl) || !Url.IsLocalUrl(data.RedirectUrl)
                        ? RedirectToAction(nameof(HomeController.Index), "Home")
                        : (IActionResult) Redirect(data.RedirectUrl);

                _logger.LogInformation($"Log in failed: sign in failure. Message: ${signInResult}");
            }
            else
                _logger.LogInformation($"Log in failed: user with supplied login {data.Login} not found");

            ModelState.AddModelError(string.Empty, nameof(Resource.LoginFailed));
            ViewData["RedirectUrl"] = data.RedirectUrl;
            return View("~/Views/LogIn.cshtml", data);
        }

        [Route("/account/logout")]
        public async Task<IActionResult> LogOut()
        {
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(LogIn));
        }

        public async Task<IActionResult> Details()
        {
            var user = await _userManager.FindByNameAsync(User.Identity.Name);
            return user == null
                ? (IActionResult) NotFound()
                : Ok(DetailsVm.Create(user));
        }

        [HttpPost]
        public async Task<IActionResult> Details([FromBody] DetailsEditM data)
        {
            var user = await _userManager.FindByNameAsync(User.Identity.Name);
            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), nameof(Resource.NameError));
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.CurrentPassword)
                && !await _userManager.CheckPasswordAsync(user, data.CurrentPassword))
            {
                ModelState.AddModelError(nameof(data.CurrentPassword), nameof(Resource.CurrentPasswordisWrong));
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.NewPassword)
                && !(await _userManager.ChangePasswordAsync(user, data.CurrentPassword, data.NewPassword)).Succeeded)
            {
                ModelState.AddModelError(nameof(data.NewPassword), nameof(Resource.PasswordUpdateError));
                return BadRequest(ModelState);
            }

            user.Name = data.Name;
            user.PhoneNumber = data.Phone;
            user.Email = data.Email;

            if ((await _userManager.UpdateAsync(user)).Succeeded) return NoContent();

            ModelState.AddModelError(string.Empty, nameof(Resource.UserUpdateError));
            return BadRequest(ModelState);
        }
    }
}
