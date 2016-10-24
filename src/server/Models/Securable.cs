using System.Collections.Generic;

namespace Server.Models
{
    public class Securable
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public SecurableType Type { get; set; }
        public Securable Parent { get; set; }
        public IEnumerable<OperationType> OperationTypes { get; set; }
    }
}
