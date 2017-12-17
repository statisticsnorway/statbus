using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class PredicateExpressionTuple
    {
        public ExpressionItem ExpressionEntry { get; set; }
        public ComparisonEnum? Comparison { get; set; }
    }
}
