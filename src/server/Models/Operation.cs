namespace Server.Models
{
    public class Operation
    {
        public int Id { get; set; }
        public Role Role { get; set; }
        public OperationType Type { get; set; }
        public Securable Securable { get; set; }
        public bool Allowed { get; set; }
    }
}
