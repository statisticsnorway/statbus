using System.Collections.Generic;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class PredicateExpression
    {
        public List<PredicateExpressionTuple> Clauses { get; set; }
        public PredicateExpression Left { get; set; }
        public PredicateExpression Right { get; set; }
        public ComparisonEnum Comparison { get; set; }
    }
}
