using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace nscreg.Server.Core
{
    public class ValidateModelStateAttribute : ActionFilterAttribute
    {
        public override void OnActionExecuting(ActionExecutingContext context)
        {
            if (context.ModelState.IsValid)
                base.OnActionExecuting(context);
            else
                context.Result = new BadRequestObjectResult(context.ModelState);
        }
    }
}
