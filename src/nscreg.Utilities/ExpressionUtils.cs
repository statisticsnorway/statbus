using System.Linq.Expressions;
using Microsoft.AspNetCore.Mvc.ViewFeatures.Internal;

namespace nscreg.Utilities
{
    public static class ExpressionUtils
    {
        public static string GetExpressionText(LambdaExpression expr) => ExpressionHelper.GetExpressionText(expr);
    }
}
