using System;
using System.Linq.Expressions;
using nscreg.Data.Entities;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    /// <summary>
    /// User expression tree parser interface
    /// </summary>
    public interface IExpressionParser
    {
        Expression<Func<StatisticalUnit, bool>> Parse(SFExpression sfExpression);
    }
}
