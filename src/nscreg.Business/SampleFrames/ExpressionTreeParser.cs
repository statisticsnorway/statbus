using System;
using System.Linq;
using System.Linq.Expressions;
using Microsoft.Extensions.Configuration;
using nscreg.Business.PredicateBuilders;
using nscreg.Business.PredicateBuilders.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class ExpressionTreeParser<T> where T : class, IStatisticalUnit
    {
        private readonly BasePredicateBuilder<T> _predicateBuilder;

        public ExpressionTreeParser(NSCRegDbContext context, IConfiguration configuration)
        {
            _predicateBuilder = SampleFramesPredicateBuilderFactory.CreateFor<T>(context, configuration);
        }

        public Expression<Func<T, bool>> Parse(ExpressionGroup group)
        {
            Expression<Func<T, bool>> pred = null;

            if (group.Rules != null)
                pred = group.Rules.Aggregate(pred, AggregateRules);

            if (group.Groups != null)
                pred = group.Groups.Aggregate(pred, AggregateGroups);
            return pred;
        }

        private Expression<Func<T, bool>> AggregateGroups(Expression<Func<T, bool>> current,
            ExpressionTuple<ExpressionGroup> g)
        {
            var currentPred = Parse(g.Predicate);

            return current == null
                ? currentPred
                : _predicateBuilder.GetPredicateOnTwoExpressions(current, currentPred,
                    g.Comparison ?? ComparisonEnum.And);
        }

        private Expression<Func<T, bool>> AggregateRules(Expression<Func<T, bool>> current,
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
