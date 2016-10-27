using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc;
using Server.Models;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class RolesController : Controller
    {
        private readonly DatabaseContext _context;

        public RolesController(DatabaseContext context)
        {
            _context = context;
        }

        public IEnumerable<IdentityRole> Get() => _context.Roles;

        [HttpGet("{id}")]
        public IdentityRole Get(string id) => _context.Roles.SingleOrDefault(r => r.Id == id);

        [HttpPost("{value}")]
        public IActionResult Post([FromBody] IdentityRole role)
        {
            _context.Roles.Add(role);
            _context.SaveChanges();

            return StatusCode(201, role);
        }
    }
}
