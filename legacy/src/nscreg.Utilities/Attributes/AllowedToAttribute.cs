using System;
using System.Linq;

namespace nscreg.Utilities.Attributes
{
    [AttributeUsage(AttributeTargets.Field)]
    public class AllowedToAttribute : Attribute
    {
        public AllowedToAttribute(params string[] roles)
        {
            Roles = roles;
        }

        public string[] Roles { get; }

        public bool IsAllowedTo(string role)
        {
            return Roles.Contains(role);
        }
    }
}
