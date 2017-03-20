using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using nscreg.Data.Constants;
using nscreg.Server.Extension;
using nscreg.Server.Services;
using nscreg.Server.Services.Contracts;

namespace nscreg.Server.Core.Authorize
{
    public class SystemFunctionAuthHandler :
        AttributeAuthorizationHandler<SystemFunctionAuthRequirement, SystemFunctionAttribute>
    {
        private readonly IUserService _userService;

        public SystemFunctionAuthHandler(IUserService userService)
        {
            _userService = userService;
        }

        protected override async Task HandleRequirementAsync(AuthorizationHandlerContext context,
            SystemFunctionAuthRequirement requirement,
            IEnumerable<SystemFunctionAttribute> attributes)
        {
            foreach (var attribute in attributes)
                if (!await AuthorizeAsync(context.User, attribute.Name))
                    return;

            context.Succeed(requirement);
        }

        private async Task<bool> AuthorizeAsync(ClaimsPrincipal user, SystemFunctions permission)
            => (await _userService.GetSystemFunctionsByUserId(user.GetUserId())).Contains(permission);
    }
}