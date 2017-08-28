using System;
using System.Linq.Expressions;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.SampleFrame;
using Expression = nscreg.Utilities.Models.SampleFrame.Expression;
using LinqExpression = System.Linq.Expressions.Expression;

namespace nscreg.Business.SampleFrame
{
    public class ExpressionParser : IExpressionParser
    {
        public Expression<Func<StatisticalUnit, bool>> Parse(Expression expression)
        {
            var result = string.Empty;
            if (expression.ExpressionItem != null)
                return GetLambda(expression);
            else
            {
                var firstExpressionLambda = Parse(expression.FirstExpression);
                var secondExpressionLambda = Parse(expression.SecondExpression);

                return GetLambdaOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, expression.Comparison);
            }
        }

        private Expression<Func<StatisticalUnit, bool>> GetLambda(Expression expression)
        {
            var parameter = LinqExpression.Parameter(typeof(StatisticalUnit), "x");
            var property = LinqExpression.Property(parameter, expression.ExpressionItem.Field.ToString());
            var constantValue = LinqExpression.Constant(expression.ExpressionItem.Value);

            BinaryExpression binaryExpression = null;
            switch (expression.ExpressionItem.Operation)
            {
                case OperationEnum.Equal:
                    binaryExpression = LinqExpression.Equal(property, constantValue);
                    break;
                case OperationEnum.LessThan:
                    binaryExpression = LinqExpression.LessThan(property, constantValue);
                    break;
                case OperationEnum.LessThanOrEqual:
                    binaryExpression = LinqExpression.LessThanOrEqual(property, constantValue);
                    break;
                case OperationEnum.GreaterThan:
                    binaryExpression = LinqExpression.GreaterThan(property, constantValue);
                    break;
                case OperationEnum.GreaterThanOrEqual:
                    binaryExpression = LinqExpression.GreaterThanOrEqual(property, constantValue);
                    break;
                case OperationEnum.NotEqual:
                    binaryExpression = LinqExpression.NotEqual(property, constantValue);
                    break;
                case OperationEnum.FromTo:
                    binaryExpression = LinqExpression.NotEqual(property, constantValue);
                    break;
                default:
                    return null;
            }
            var lambda = LinqExpression.Lambda<Func<StatisticalUnit, bool>>(binaryExpression, parameter);

            return lambda;
        }

        private Expression<Func<StatisticalUnit, bool>> GetLambdaOnTwoExpressions(LinqExpression firstExpressionLambda,
            LinqExpression secondExpressionLambda, ComparisonEnum expressionComparison)
        {
            BinaryExpression resultExpression = null;

            switch (expressionComparison)
            {
                case ComparisonEnum.And:
                    resultExpression = LinqExpression.AndAlso(firstExpressionLambda, secondExpressionLambda);
                    break;
                case ComparisonEnum.AndNot:
                    resultExpression = LinqExpression.(firstExpressionLambda, secondExpressionLambda);
                    break;
                case ComparisonEnum.Or:
                    resultExpression = LinqExpression.OrElse(firstExpressionLambda, secondExpressionLambda);
                    break;
                case ComparisonEnum.Or:
                    resultExpression = LinqExpression.Or(firstExpressionLambda, secondExpressionLambda);
                    break;
            }

            var resultLambda = LinqExpression.Lambda<Func<StatisticalUnit, bool>>(resultExpression);

            return resultLambda;
        }
    }
}
