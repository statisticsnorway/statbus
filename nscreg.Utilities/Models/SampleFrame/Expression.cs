using nscreg.Utilities.Enums.SampleFrame;

namespace nscreg.Utilities.Models.SampleFrame
{
    public class Expression
    {
        public ExpressionItem ExpressionItem { get; set; }
        public Expression FirstExpression { get; set; }
        public Expression SecondExpression { get; set; }
        public ComparisonEnum Comparison { get; set; }
    }
}
