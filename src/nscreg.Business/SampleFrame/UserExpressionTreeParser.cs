using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using nscreg.Business.PredicateBuilders;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Business.SampleFrame
{
    /// <summary>
    /// User expression tree parser
    /// </summary>
    public class UserExpressionTreeParser
    {
        private readonly SampleFramePredicateBuilder _sfPredicateBuilder;
        public UserExpressionTreeParser()
        {
            _sfPredicateBuilder = new SampleFramePredicateBuilder();
        }

        /// <summary>
        /// Parse user expression tree to .net expression tree
        /// </summary>
        /// <param name="sfExpression">User expression tree</param>
        /// <returns>.Net expression tree</returns>
        public Expression<Func<StatisticalUnit, bool>> Parse(SfExpression sfExpression)
        {
            if (sfExpression.ExpressionItems != null)
            {
                var allPredicates = BuildPredicates(sfExpression.ExpressionItems);
                var orPredicates = MergeAndPredicates(allPredicates);
                if (orPredicates.Count == 1) return orPredicates[0].Item1;
                var result = _sfPredicateBuilder.GetPredicateOnTwoExpressions(orPredicates[0].Item1, orPredicates[1].Item1, orPredicates[0].Item2);
                for (var i = 1; i < orPredicates.Count - 1; i++)
                {
                    result = _sfPredicateBuilder.GetPredicateOnTwoExpressions(result, orPredicates[i + 1].Item1,
                        orPredicates[i].Item2);
                }

                return result;
            }
            else
            {
                var firstExpressionLambda = Parse(sfExpression.FirstSfExpression);
                var secondExpressionLambda = Parse(sfExpression.SecondSfExpression);
                return _sfPredicateBuilder.GetPredicateOnTwoExpressions(firstExpressionLambda, secondExpressionLambda, sfExpression.Comparison);
            }
        }
        
        /// <summary>
        /// Merges all "And", "AndNot" predicates and returns "Or" predicates
        /// </summary>
        /// <param name="allPredicates">Predicates list</param>
        /// <returns>List of predicates with "Or" comparison</returns>
        private List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)> MergeAndPredicates(
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
                    var pred = _sfPredicateBuilder.GetPredicateOnTwoExpressions(allPredicates[i].Item1, allPredicates[i + 1].Item1,
                        allPredicates[i].Item2);
                    orPredicates.Add((pred, allPredicates[i + 1].Item2));
                    i++;
                }
            }
            return orPredicates;
        }

        /// <summary>
        /// Builds predicates on user expressions
        /// </summary>
        /// <param name="expressionItems">List of user expressions</param>
        /// <returns>List of predicates</returns>
        private List<(Expression<Func<StatisticalUnit, bool>> predicate, ComparisonEnum? comparison)> BuildPredicates(IEnumerable<Tuple<ExpressionItem, ComparisonEnum?>> expressionItems)
        {
            var result = new List<(Expression<Func<StatisticalUnit, bool>> predicate, ComparisonEnum? comparison)>();
            
            foreach (var tuple in expressionItems)
                result.Add((_sfPredicateBuilder.GetPredicate(tuple.Item1.Field, tuple.Item1.Value, tuple.Item1.Operation), tuple.Item2));

            return result;
        }
    }
}
