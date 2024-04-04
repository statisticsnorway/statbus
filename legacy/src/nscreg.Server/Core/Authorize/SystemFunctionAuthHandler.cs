using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;
using nscreg.Server.Common.Services.Contracts;

namespace nscreg.Server.Core.Authorize
{
    // ReSharper disable once ClassNeverInstantiated.Global
    /// <summary>
    /// Class handler authorization system function
    /// </summary>
    public class SystemFunctionAuthHandler :
        AttributeAuthorizationHandler<SystemFunctionAuthRequirement, SystemFunctionAttribute>
    {
        private readonly IUserService _userService;

        public SystemFunctionAuthHandler(IUserService userService)
        {
            _userService = userService;
        }
        /// <summary>
        /// Requirement Handler Method
        /// </summary>
        /// <param name="context">context</param>
        /// <param name="requirement">requirement</param>
        /// <param name="attributes">attributes</param>
        /// <returns></returns>
        protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context,
            SystemFunctionAuthRequirement requirement,
            IEnumerable<SystemFunctionAttribute> attributes)
        {
            foreach (var attribute in attributes)
                if (!await AuthorizeAsync(context.User, attribute.SystemFunctions))
                {
                    context.Fail();
                    return;
                }
            context.Succeed(requirement);
        }
        /// <summary>
        /// Authorization Method
        /// </summary>
        /// <param name="user">user</param>
        /// <param name="permissions">permissions</param>
        /// <returns></returns>
        private async Task<bool> AuthorizeAsync(ClaimsPrincipal user, SystemFunctions[] permissions)
            => (await _userService.GetSystemFunctionsByUserId(user.GetUserId())).Intersect(permissions).Any();
    }
}
