using System.Linq.Expressions;
using System.Web.Mvc;

namespace nscreg.Utilities
{
    /// <summary>
    /// Expression utilities comparison class
    /// </summary>
    public static class ExpressionUtils
    {
        /// <summary>
        /// Method for obtaining a text expression
        /// </summary>
        /// <param name = "expr"> Expression </param>
        /// <returns> </returns>
        public static string GetExpressionText(LambdaExpression expr) => ExpressionHelper.GetExpressionText(expr);
    }
}
