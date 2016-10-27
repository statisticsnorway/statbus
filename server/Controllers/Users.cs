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

        [HttpGet("IsUserNameExists/{userName}")]
        public bool CheckUserName(string userName) => _context.Users.Any(u => u.UserName == userName);

        [HttpGet("{id}")]
        public User Get(string id) => _context.Users.SingleOrDefault(u => u.Id == id);

        [HttpPost("{value}")]
        public IActionResult Post([FromBody] User user)
        {
            _context.Add(User);
            _context.SaveChanges();

            return StatusCode(201, user);
        }
    }
}
