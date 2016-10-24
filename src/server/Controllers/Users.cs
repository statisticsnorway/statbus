using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Mvc;
using Server.Models;

namespace Server.Controllers
{
    [Route("api/[controller]")]
    public class UsersController : Controller
    {
        private readonly DatabaseContext _context;

        public UsersController(DatabaseContext context)
        {
            _context = context;
        }

        public IEnumerable<User> Get() => _context.Users;

        [HttpGet("{id}")]
        public User Get(int id) => _context.Users.FirstOrDefault(x => x.Id == id);

        [HttpPost("{value}")]
        public IActionResult Post([FromBody] User value)
        {
            _context.Users.Add(value);
            _context.SaveChanges();
            return StatusCode(201, value);
        }
    }
}
