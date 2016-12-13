using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.ReadStack;
using nscreg.Server.Models.Account;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]/[action]")]
    public class AccountController : Controller
    {
        private readonly SignInManager<User> _signInManager;
        private readonly UserManager<User> _userManager;
        private readonly ReadContext _readCtx;
        private readonly ILogger _logger;

        public AccountController(
            SignInManager<User> signInManager,
            UserManager<User> userManager,
            ILoggerFactory loggerFactory,
            NSCRegDbContext dbContext)
        {
            _signInManager = signInManager;
            _userManager = userManager;
            _readCtx = new ReadContext(dbContext);
            _logger = loggerFactory.CreateLogger<AccountController>();
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
            if (ModelState.IsValid)
            {
                var user = _readCtx.Users.Include(x => x.Roles).FirstOrDefault(u => u.Login == data.Login);
                var roles = _readCtx.Roles.Where(r => user.Roles.Any(ur => ur.RoleId == r.Id));
                var dataAccessAttributes = roles
                    .SelectMany(r => r.StandardDataAccessArray)
                    .Concat(user.DataAccessArray)
                    .Distinct();
                var systemFunctions = roles
                    .SelectMany(r => r.AccessToSystemFunctionsArray)
                    .Distinct()
                    .Select(x => ((SystemFunctions)x).ToString());
                var addClaimResult = await _userManager.AddClaimsAsync(
                    user,
                    new[]
                    {
                        new Claim(CustomClaimTypes.DataAccessAttributes, string.Join(",", dataAccessAttributes)),
                        new Claim(CustomClaimTypes.SystemFunctions, string.Join(",", systemFunctions)),
                    });
                var signInResult =
                    await _signInManager.PasswordSignInAsync(user, data.Password, data.RememberMe, false);
                if (signInResult.Succeeded)
                    return string.IsNullOrEmpty(data.RedirectUrl) || !Url.IsLocalUrl(data.RedirectUrl)
                        ? RedirectToAction(nameof(HomeController.Index), "Home")
                        : (IActionResult)Redirect(data.RedirectUrl);
            }
            ModelState.AddModelError(string.Empty, "Log in failed");
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
            if (user == null) return NotFound();
            return Ok(DetailsVm.Create(user));
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
            if (!string.IsNullOrEmpty(data.CurrentPassword)
                && !await _userManager.CheckPasswordAsync(user, data.CurrentPassword))
            {
                ModelState.AddModelError(nameof(data.CurrentPassword), "Current password is wrong");
                return BadRequest(ModelState);
            }
            if (!string.IsNullOrEmpty(data.NewPassword)
                && !(await _userManager.ChangePasswordAsync(user, data.CurrentPassword, data.NewPassword)).Succeeded)
            {
                ModelState.AddModelError(nameof(data.NewPassword), "Error while updating password");
                return BadRequest(ModelState);
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
