using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc;
using Server.Models;
using Server.ViewModels;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly DatabaseContext _context;
        private readonly RoleManager<IdentityRole> _roleManager;

        public RolesController(DatabaseContext context, RoleManager<IdentityRole> roleManager)
        {
            _context = context;
            _roleManager = roleManager;
        }

        public IEnumerable<Role> GetAllRoles() => _context.Roles;

        [HttpGet("{id}")]
        public Role GetRoleWithId(string id) => _context.Roles.SingleOrDefault(r => r.Id == id);

        [HttpPost("{value}")]
        public IActionResult CreateRole([FromBody] RoleViewModel roleViewModel)
        {
            if (ModelState.IsValid)
            {
                if (!_roleManager.RoleExistsAsync(roleViewModel.Name).Result)
                {
                    var role = new Role
                    {
                        Name = roleViewModel.Name,
                        Description = roleViewModel.Description
                    };
                    IdentityResult roleResult = _roleManager.CreateAsync(role).Result;
                    if (!roleResult.Succeeded)
                    {
                        ModelState.AddModelError("",
                         "Error while creating role!");
                        return StatusCode(201, role);
                    }
                }
            }

            return StatusCode(201, roleViewModel);
        }
    }
}
