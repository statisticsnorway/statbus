using nscreg.Data.Entities;

namespace nscreg.Server.Models.Roles
{
    public class UserItem
    {
        public static UserItem Create(User user) => new UserItem
        {
            Id = user.Id,
            Name = user.Name,
            Descritpion = user.Description
        };

        public string Id { get; private set; }
        public string Name { get; private set; }
        public string Descritpion { get; private set; }
    }
}
