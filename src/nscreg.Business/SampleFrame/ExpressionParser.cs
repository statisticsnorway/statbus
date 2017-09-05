using System;
using System.Linq.Expressions;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.SampleFrame;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    public class ExpressionParser : IExpressionParser
    {
        public Expression<Func<StatisticalUnit, bool>> Parse(SFExpression sfExpression)
        {
            if (sfExpression.ExpressionItem != null)
                return PredicateBuilder.GetLambda(sfExpression.ExpressionItem);
            else
            {
                var firstExpressionLambda = Parse(sfExpression.FirstSfExpression);
                var secondExpressionLambda = Parse(sfExpression.SecondSfExpression);
                return GetLambdaOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, sfExpression.Comparison);
            }
        }
        
        private static Expression<Func<StatisticalUnit, bool>> GetLambdaOnTwoExpressions(Expression<Func<StatisticalUnit, bool>> firstExpressionLambda,
            Expression<Func<StatisticalUnit, bool>> secondExpressionLambda, ComparisonEnum expressionComparison)
        {
            BinaryExpression expression = null;
            switch (expressionComparison)
            {
                case ComparisonEnum.And:
                    expression =
                        Expression.AndAlso(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], secondExpressionLambda.Parameters[0])
                                .Visit(firstExpressionLambda.Body), secondExpressionLambda.Body);
                    break;

                case ComparisonEnum.AndNot:
                    var andNegatedExpression =
                        Expression.Lambda<Func<StatisticalUnit, bool>>(Expression.Not(secondExpressionLambda.Body),
                            secondExpressionLambda.Parameters[0]);
                    expression =
                        Expression.AndAlso(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], andNegatedExpression.Parameters[0])
                                .Visit(firstExpressionLambda.Body), andNegatedExpression.Body);
                    break;

                case ComparisonEnum.Or:
                    expression =
                        Expression.OrElse(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], secondExpressionLambda.Parameters[0])
                                .Visit(firstExpressionLambda.Body), secondExpressionLambda.Body);
                    break;

                case ComparisonEnum.OrNot:
                    var orNegatedExpression =
                        Expression.Lambda<Func<StatisticalUnit, bool>>(Expression.Not(secondExpressionLambda.Body),
                            secondExpressionLambda.Parameters[0]);
                    expression =
                        Expression.OrElse(
                            new SwapVisitor(firstExpressionLambda.Parameters[0], orNegatedExpression.Parameters[0])
                                .Visit(firstExpressionLambda.Body), orNegatedExpression.Body);
                    break;
            }

            var resultLambda = Expression.Lambda<Func<StatisticalUnit, bool>>(expression, secondExpressionLambda.Parameters);

            return resultLambda;
        }
    }
}
