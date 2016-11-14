using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace nscreg.Utilities
{
    public class CustomPasswordHasher<T> : PasswordHasher<T> where T: class
    {
        public CustomPasswordHasher(IOptions<PasswordHasherOptions> optionsAccessor = null) : base(optionsAccessor)
        {
        }
    }
}
