using System.Collections.Generic;

namespace Server.Models
{
    public class Role
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public IEnumerable<Operation> Operations { get; set; }
    }
}
