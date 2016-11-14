using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Utilities;
using Xunit;

namespace nscreg.Server.Test
{
    public class StringExtensionsTest
    {
        [Fact]
        public void IsPrintableString()
        {
            Assert.True("123qwe".IsPrintable());
        }

        [Fact]
        public void IsNotPrintableString()
        {
            Assert.False("¤•2€3©".IsPrintable());
        }

        [Fact]
        public void CheckVerifyPasswordHash()
        {
            var user = new User
            {
                Login = "admin",
                Name = "admin",
                PhoneNumber = "555123456",
                Email = "admin@email.xyz",
                Status = UserStatuses.Active,
                Description = "System administrator account",
                NormalizedUserName = "admin".ToUpper(),
            };
            var hash = "AQAAAAEAACcQAAAAEDukTcNpU25oEAXRrATHqnu7wKlEpf4IYu8gwo0+sue+eiZHVWiZ7Hze/OIQEfgJ2w==";
            var hasher = new CustomPasswordHasher<User>();
            Assert.Equal(1, (int)hasher.VerifyHashedPassword(user, hash, "123qwe"));
        }
    }
}
