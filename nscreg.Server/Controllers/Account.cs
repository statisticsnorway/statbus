using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using nscreg.Data.Entities;
using nscreg.Server.Models.Accounts;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Server.Controllers
{
    [Route("[controller]/[action]")]
    public class AccountController : Controller
    {
        private readonly SignInManager<User> _signInManager;
        private readonly UserManager<User> _userManager;
        private readonly ILogger _logger;

        public AccountController(SignInManager<User> signInManager, UserManager<User> userManager, ILoggerFactory loggerFactory)
        {
            _signInManager = signInManager;
            _userManager = userManager;
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
                        : (IActionResult)Redirect(data.RedirectUrl);
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

        public async Task<IActionResult> Details()
        {
            var user = await _userManager.FindByNameAsync(User.Identity.Name);
            if (user == null) return NotFound();
            var account = new DetailsVm
            {
                Name = user.Name,
                PhoneNumber = user.PhoneNumber,
                Email = user.Email
            };
            return Ok(account);
        }

        [HttpPost]
        public async Task<IActionResult> Details([FromBody] DetailsEditM data)
        {
            if (!ModelState.IsValid) return BadRequest(ModelState);
            var user = await _userManager.FindByNameAsync(User.Identity.Name);

            if (user.Name != data.Name && _userManager.Users.Any(u => u.Name == data.Name))
            {
                ModelState.AddModelError(nameof(data.Name), "Name is already taken");
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.CurrentPassword))
            {
                if (!await _userManager.CheckPasswordAsync(user, data.CurrentPassword))
                {
                    ModelState.AddModelError(nameof(data.CurrentPassword), "Current password is wrong");
                    return BadRequest(ModelState);
                }
            }
            if (!string.IsNullOrEmpty(data.NewPassword))
            {
                if (!(await _userManager.ChangePasswordAsync(user, data.CurrentPassword, data.NewPassword)).Succeeded)
                {
                    ModelState.AddModelError(nameof(data.NewPassword), "Error while updating password");
                    return BadRequest(ModelState);
                }
            }
            user.Name = data.Name;
            user.PhoneNumber = data.Phone;
            user.Email = data.Email;
            if (!(await _userManager.UpdateAsync(user)).Succeeded)
            {
                ModelState.AddModelError(string.Empty, "Error while updating user");
                return BadRequest(ModelState);
            }
            return NoContent();
        }
    }
}
