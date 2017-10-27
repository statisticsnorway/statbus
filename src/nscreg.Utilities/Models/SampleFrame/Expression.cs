using System;
using System.Collections.Generic;
using nscreg.Utilities.Enums.Predicate;

namespace nscreg.Utilities.Models.SampleFrame
{
    public class SFExpression
    {
        public List<Tuple<ExpressionItem, ComparisonEnum?>> ExpressionItems { get; set; }
        public SFExpression FirstSfExpression { get; set; }
        public SFExpression SecondSfExpression { get; set; }
        public ComparisonEnum Comparison { get; set; }
    }
}
