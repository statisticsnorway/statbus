using nscreg.Utilities.Enums.SampleFrame;

namespace nscreg.Utilities.Models.SampleFrame
{
    public class SFExpression
    {
        public ExpressionItem ExpressionItem { get; set; }
        public SFExpression FirstSfExpression { get; set; }
        public SFExpression SecondSfExpression { get; set; }
        public ComparisonEnum Comparison { get; set; }
    }
}
