using System.Linq.Expressions;
using Microsoft.AspNetCore.Mvc.ViewFeatures.Internal;

namespace nscreg.Utilities
{
    /// <summary>
    /// Класс сравнения утилит выражений
    /// </summary>
    public static class ExpressionUtils
    {
        /// <summary>
        /// Метод получения текстового выражения
        /// </summary>
        /// <param name="expr">Выражение</param>
        /// <returns></returns>
        public static string GetExpressionText(LambdaExpression expr) => ExpressionHelper.GetExpressionText(expr);
    }
}
