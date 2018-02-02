using System;
using System.Linq;
using System.Linq.Expressions;
using nscreg.Business.PredicateBuilders;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class ExpressionTreeParser
    {
        private readonly SampleFramePredicateBuilder _predicateBuilder;

        public ExpressionTreeParser()
        {
            _predicateBuilder = new SampleFramePredicateBuilder();
        }

        public Expression<Func<StatisticalUnit, bool>> Parse(ExpressionGroup group)
        {
            Expression<Func<StatisticalUnit, bool>> pred = null;

            if (group.Rules != null)
                pred = group.Rules.Aggregate(pred, AggregateRules);

            if (group.Groups != null)
                pred = group.Groups.Aggregate(pred, AggregateGroups);
            return pred;
        }

        private Expression<Func<StatisticalUnit, bool>> AggregateGroups(Expression<Func<StatisticalUnit, bool>> current,
            ExpressionTuple<ExpressionGroup> g)
        {
            var currentPred = Parse(g.Predicate);

            return current == null
                ? currentPred
                : _predicateBuilder.GetPredicateOnTwoExpressions(current, currentPred,
                    g.Comparison ?? ComparisonEnum.And);
        }

        private Expression<Func<StatisticalUnit, bool>> AggregateRules(Expression<Func<StatisticalUnit, bool>> current,
            ExpressionTuple<Rule> rule)
        {
            var currentPred =
                _predicateBuilder.GetPredicate(rule.Predicate.Field, rule.Predicate.Value, rule.Predicate.Operation);

            return current == null
                ? currentPred
                : _predicateBuilder.GetPredicateOnTwoExpressions(current, currentPred,
                    rule.Comparison ?? ComparisonEnum.And);
        }
    }
}
