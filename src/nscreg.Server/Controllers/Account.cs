using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using System.Linq;
using System.Threading.Tasks;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.Account;
using nscreg.Server.Core;
using nscreg.Server.Core.Authorize;
using nscreg.Utilities.Extensions;
using System.Collections.Generic;

namespace nscreg.Server.Controllers
{
    /// <summary>
    /// Account controller
    /// </summary>
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

        /// <summary>
        /// Method returning the login page
        /// </summary>
        /// <param name="urlReferrer"></param>
        /// <returns></returns>
        [AllowAnonymous, Route("/account/login")]
        public IActionResult LogIn(string urlReferrer = null)
        {

            ViewData["RedirectUrl"] = urlReferrer;
            ViewData["Localization"] = new Dictionary<string, string>
            {
                { "LoginTitle", Resource.LoginTitle },
                { "LoginInputLogin", Resource.LoginInputLogin },
                { "LoginInputPassword", Resource.LoginInputPassword },
                { "LoginInputRemember", Resource.LoginInputRemember },
                { "LoginInputButton", Resource.LoginInputButton },
                { "LoginFailed", Resource.LoginFailed }
            };
            return View("~/Views/LogIn.cshtml");
        }
        /// <summary>
        ///
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost, AllowAnonymous, Route("/account/login"), DisableValidateModelState]
        public async Task<IActionResult> LogIn([FromForm] LoginVm data)
        {
            if (ModelState.IsValid)
            {
                var user = await _userManager.FindByNameAsync(data.Login);
                if (user != null && user.Status == UserStatuses.Active)
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
            }
            ModelState.AddModelError(string.Empty, nameof(Resource.LoginFailed));
            ViewData["RedirectUrl"] = data.RedirectUrl;
            ViewData["Localization"] = new Dictionary<string, string>
            {
                { "LoginTitle", Resource.LoginTitle },
                { "LoginInputLogin", Resource.LoginInputLogin }, 
                { "LoginInputPassword", Resource.LoginInputPassword },
                { "LoginInputRemember", Resource.LoginInputRemember },
                { "LoginInputButton", Resource.LoginInputButton },
                { "LoginFailed", Resource.LoginFailed }
            };
            return View("~/Views/LogIn.cshtml", data);
        }
        /// <summary>
        ///
        /// </summary>
        /// <param name="data"></param>
        /// <returns></returns>
        [HttpPost, AllowAnonymous, Route("/account/loginjs")]
        public async Task<IActionResult> LogInJs([FromBody] LoginVm data)
        {
            var user = await _userManager.FindByNameAsync(data.Login);
            if (user != null && user.Status == UserStatuses.Active)
            {
                var signInResult = await _signInManager.PasswordSignInAsync(
                    user,
                    data.Password,
                    data.RememberMe,
                    false);
                if (signInResult.Succeeded)
                    return NoContent();

                _logger.LogInformation($"Log in failed: sign in failure. Message: ${signInResult}");
            }
            else
                _logger.LogInformation($"Log in failed: user with supplied login {data.Login} not found");

            return BadRequest();
        }
        /// <summary>
        /// Logout method
        /// </summary>
        /// <returns></returns>
        [Route("/account/logout")]
        public async Task<IActionResult> LogOut()
        {
            await _signInManager.SignOutAsync();
            return RedirectToAction(nameof(LogIn));
        }
        /// <summary>
        /// Method returning detailed user account information
        /// </summary>
        /// <returns></returns>
        [SystemFunction(SystemFunctions.AccountView)]
        public async Task<IActionResult> Details()
        {
            var user = await _userManager.FindByNameAsync(User.Identity.Name);
            return user == null
                ? (IActionResult)NotFound()
                : Ok(DetailsVm.Create(user));
        }
        /// <summary>
        /// Method accepts and writes user account data
        /// </summary>
        /// <param name="data">User data</param>
        /// <returns></returns>
        [HttpPost]
        [SystemFunction(SystemFunctions.AccountEdit)]
        public async Task<IActionResult> Details([FromBody] DetailsEditM data)
        {
            var user = await _userManager.FindByNameAsync(User.Identity.Name);
            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), nameof(Resource.NameError));
                return BadRequest(ModelState);
            }
            if (data.CurrentPassword.HasValue()
                && !await _userManager.CheckPasswordAsync(user, data.CurrentPassword))
            {
                ModelState.AddModelError(nameof(data.CurrentPassword), nameof(Resource.CurrentPasswordisWrong));
                return BadRequest(ModelState);
            }
            if (data.NewPassword.HasValue()
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
