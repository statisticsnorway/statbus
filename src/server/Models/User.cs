namespace Server.Models
{
    public class User
    {
        public int Id { get; set; }
        public string Login { get; set; }
        public string Password { get; set; }
        public string Name { get; set; }
        public string Phone { get; set; }
        public string Email { get; set; }
        public string Description { get; set; }
        //public UserStatusEnum Status { get; set; }
        //public IEnumerable<Role> Roles { get; set; }
    }
}
