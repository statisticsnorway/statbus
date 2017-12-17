using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Business.PredicateBuilders;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
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
        public Expression<Func<StatisticalUnit, bool>> Parse(PredicateExpression sfExpression)
        {
            if (sfExpression.Clauses?.Any() != true)
                return _sfPredicateBuilder.GetPredicateOnTwoExpressions(
                    Parse(sfExpression.Left),
                    Parse(sfExpression.Right),
                    sfExpression.Comparison);
            var orPredicates = MergeAndPredicates(BuildPredicates(sfExpression.Clauses));
            if (orPredicates.Count == 1) return orPredicates[0].Item1;
            var result = _sfPredicateBuilder.GetPredicateOnTwoExpressions(
                orPredicates[0].Item1,
                orPredicates[1].Item1,
                orPredicates[0].Item2);
            for (var i = 1; i < orPredicates.Count - 1; i++)
            {
                result = _sfPredicateBuilder.GetPredicateOnTwoExpressions(
                    result,
                    orPredicates[i + 1].Item1,
                    orPredicates[i].Item2);
            }

            return result;
        }

        /// <summary>
        /// Merges all "And", "AndNot" predicates and returns "Or" predicates
        /// </summary>
        /// <param name="allPredicates">Predicates list</param>
        /// <returns>List of predicates with "Or" comparison</returns>
        private List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)> MergeAndPredicates(
            IReadOnlyList<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)> allPredicates)
        {
            var orPredicates = new List<(Expression<Func<StatisticalUnit, bool>>, ComparisonEnum?)>();
            if (allPredicates.Count == 1)
            {
                // dirty hack, in some cases when `allPredicates[i + 1]` is exception case
                // it's still not fixed, but this condition makes sense for one-clause predicate
                orPredicates.Add((allPredicates[0].Item1, allPredicates[0].Item2));
                return orPredicates;
            }
            for (var i = 0; i < allPredicates.Count; i++)
            {
                if (allPredicates[i].Item2 == ComparisonEnum.Or
                    || allPredicates[i].Item2 == ComparisonEnum.OrNot
                    || allPredicates[i].Item2 == null)
                    orPredicates.Add((allPredicates[i].Item1, allPredicates[i].Item2));
                else
                {
                    var pred = _sfPredicateBuilder.GetPredicateOnTwoExpressions(
                        allPredicates[i].Item1, allPredicates[i + 1].Item1, allPredicates[i].Item2);
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
        private List<(Expression<Func<StatisticalUnit, bool>> predicate, ComparisonEnum? comparison)>
            BuildPredicates(IEnumerable<PredicateExpressionTuple> expressionItems) => expressionItems.Select(x =>
            (_sfPredicateBuilder.GetPredicate(x.ExpressionEntry.Field, x.ExpressionEntry.Value,
                x.ExpressionEntry.Operation), x.Comparison)).ToList();
    }
}
