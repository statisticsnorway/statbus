using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Server.Models;
using Server.ViewModels;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly DatabaseContext _context;
        private readonly UserManager<User> _userManager;
        private readonly RoleManager<Role> _roleManager;

        public UsersController(DatabaseContext context,
            UserManager<User> userManager,
            RoleManager<Role> roleManager)
        {
            _context = context;
            _userManager = userManager;
            _roleManager = roleManager;
        }

        public IEnumerable<User> GetAllUsers() => _context.Users;

        [HttpGet("IsUserNameExists/{userName}")]
        public bool CheckUserName(string userName) => _context.Users.Any(u => u.UserName == userName);

        [HttpGet("{id}")]
        public User GetUserWithId(string id) => _context.Users.SingleOrDefault(u => u.Id == id);

        [HttpPost("{value}")]
        public IActionResult RegisterUser([FromBody] RegisterViewModel registerViewModel)
        {
            if (ModelState.IsValid)
            {
                User user = new User
                {
                    UserName = registerViewModel.UserName,
                    Email = registerViewModel.Email,
                    Description = registerViewModel.Description
                };

                var result = _userManager.CreateAsync(user, registerViewModel.Password).Result;

                if (result.Succeeded)
                {
                    if (!_roleManager.RoleExistsAsync("NormalUser").Result)
                    {
                        var role = new Role() { Name = "NormalUser" };
                        IdentityResult roleResult = _roleManager.CreateAsync(role).Result;
                        if (!roleResult.Succeeded)
                        {
                            ModelState.AddModelError("",
                             "Error while creating role!");
                            return StatusCode(201, registerViewModel);
                        }
                    }

                    _userManager.AddToRoleAsync(user,
                                 "NormalUser").Wait();
                    return StatusCode(201, registerViewModel);
                }
            }
            return StatusCode(201, registerViewModel);
        }
    }
}
