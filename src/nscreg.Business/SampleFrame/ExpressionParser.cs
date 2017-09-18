using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.SampleFrame;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    /// <summary>
    /// User expression tree parser
    /// </summary>
    public class ExpressionParser : IExpressionParser
    {
        /// <summary>
        /// Parse user expression tree to .net expression tree
        /// </summary>
        /// <param name="sfExpression"></param>
        /// <returns></returns>
        public Expression<Func<StatisticalUnit, bool>> Parse(SFExpression sfExpression)
        {
            if (sfExpression.ExpressionItems != null)
            {
                var allPredicates = PredicateBuilder.GetPredicates(sfExpression.ExpressionItems);
                var orPredicates = MergeAndPredicates(allPredicates);
                if (orPredicates.Count == 1) return orPredicates[0].Item1;
                var result = GetPredicateOnTwoExpressions(orPredicates[0].Item1, orPredicates[1].Item1, orPredicates[0].Item2);
                for (var i = 1; i < orPredicates.Count - 1; i++)
                {
                    result = GetPredicateOnTwoExpressions(result, orPredicates[i + 1].Item1,
                        orPredicates[i].Item2);
                }

                return result;
            }
            else
            {
                var firstExpressionLambda = Parse(sfExpression.FirstSfExpression);
                var secondExpressionLambda = Parse(sfExpression.SecondSfExpression);
                return GetPredicateOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, sfExpression.Comparison);
            }
        }

        /// <summary>
        /// Merges all "And", "AndNot" predicates and returns "Or" predicates
        /// </summary>
        /// <param name="allPredicates"></param>
        /// <returns></returns>
        private static List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)> MergeAndPredicates(
            List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)> allPredicates)
        {
            var orPredicates = new List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)>();
            for (var i = 0; i < allPredicates.Count; i++)
            {
                if (allPredicates[i].Item2 == ComparisonEnum.Or ||
                    allPredicates[i].Item2 == ComparisonEnum.OrNot || allPredicates[i].Item2 == null)
                    orPredicates.Add((allPredicates[i].Item1, allPredicates[i].Item2));
                else
                {
                    var pred = GetPredicateOnTwoExpressions(allPredicates[i].Item1, allPredicates[i + 1].Item1,
                        allPredicates[i].Item2);
                    orPredicates.Add((pred, allPredicates[i + 1].Item2));
                    i++;
                }
            }
            return orPredicates;
        }

        /// <summary>
        /// Merges two expression
        /// </summary>
        /// <param name="firstExpressionLambda"></param>
        /// <param name="secondExpressionLambda"></param>
        /// <param name="expressionComparison"></param>
        /// <returns></returns>
        private static Expression<Func<StatisticalUnit, bool>> GetPredicateOnTwoExpressions(Expression<Func<StatisticalUnit, bool>> firstExpressionLambda,
            Expression<Func<StatisticalUnit, bool>> secondExpressionLambda, ComparisonEnum? expressionComparison)
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
