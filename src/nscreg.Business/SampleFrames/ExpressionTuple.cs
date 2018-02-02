using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Business.SampleFrames
{
    public class ExpressionTuple<T> where T : class
    {
        public T Predicate { get; set; }
        public ComparisonEnum? Comparison { get; set; }
    }
}
