using System.Security.Claims;

namespace nscreg.Server.Core
{
    /// <summary>
    /// Basic Requirement Extension Class
    /// </summary>
    public static class ClaimsPrincipalExtensions
    {
        /// <summary>
        /// Method returns user id
        /// </summary>
        /// <param name="claimsPrincipal">primary requirements</param>
        /// <returns></returns>
        public static string GetUserId(this ClaimsPrincipal claimsPrincipal)
            => claimsPrincipal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
