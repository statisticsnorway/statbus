using System.Security.Claims;

namespace nscreg.Server.Core
{
    /// <summary>
    /// Класс расширения основных требований
    /// </summary>
    public static class ClaimsPrincipalExtensions
    {
        /// <summary>
        /// Метод возвращает id пользователя
        /// </summary>
        /// <param name="claimsPrincipal">основные требования</param>
        /// <returns></returns>
        public static string GetUserId(this ClaimsPrincipal claimsPrincipal)
            => claimsPrincipal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    }
}
