using System.Security.Claims;

namespace nscreg.Server.Core
{
    public static class ClaimsPrincipalExtensions
    {
        public static string GetUserId(this ClaimsPrincipal claimsPrincipal)
            => claimsPrincipal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
